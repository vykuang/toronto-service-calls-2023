#!/usr/bin/env python
# coding: utf-8

from pathlib import Path
from google.cloud import storage
import requests
from shutil import unpack_archive
import pandas as pd
from tempfile import TemporaryDirectory
import argparse
from prefect import flow, task, get_run_logger

# Toronto Open Data is stored in a CKAN instance. It's APIs are documented here:
# https://docs.ckan.org/en/latest/api/

# To hit our API, you'll be making requests to:
BASE_URL = "https://ckan0.cf.opendata.inter.prod-toronto.ca/api/3/action/"

# Datasets are called "packages". Each package can contain many "resources"
# To retrieve the metadata for this package and its resources, use the package name in this page's URL:

# example of link to download:
# https://ckan0.cf.opendata.inter.prod-toronto.ca/dataset/7e876c24-177c-4605-9cef-e50dd74c617f/resource/98b63ba7-24ba-41da-a788-1c28d21a39d1/download/bikeshare-ridership-2017.zip
# {BASE_CKAN_URL}/dataset/<package_id>/resource/<resource_id>/download/<file_name.type>


def get_package_metadata(
    action: str = "package_show",
    resource_id: str = "311-service-requests-customer-initiated",
) -> dict:
    """See CKAN API endpoints for different action params"""
    params = {"id": resource_id}
    package = requests.get(BASE_URL + action, params=params, timeout=5).json()
    return package


@task(tags=["extract", "API"])
def get_zip_uri(year: str = "2020") -> str:
    """Retrieve URL of 311 service call data given the year"""
    resource_metadata = get_package_metadata()["result"]["resources"]
    url = [
        resource["url"] for resource in resource_metadata if year in resource["name"]
    ][0]
    return url


@task(tags=["extract"])
def extract(zip_uri: str, tmp_dir: Path, chunk_size=10000) -> Path:
    """
    Downloads zip from source to temporary dir, extracts and unzip the csv
    to tmp_dir

    Parameters:
    -------------
    zip_uri: str
        URI for the zip file to download, from open data directory

    tmp_dir: str
        folder to store the unzipped csv

    chunk_size: int
        chunk size in bytes used to stream the download

    Returns:
    --------
    tmpcsv_path: Path
        Temporary path to local csv to be uploaded
    """
    zipname = zip_uri.split("/")[-1]
    with requests.get(zip_uri, stream=True, timeout=4) as tmpzip:
        tmpzip.raise_for_status()
        # context mgr automatically removes .zip after extract
        with TemporaryDirectory() as tmpzip_dir:
            tmpzip_path = Path(tmpzip_dir) / zipname
            with open(tmpzip_path, "wb") as zipfile:
                for chunk in tmpzip.iter_content(chunk_size=chunk_size):
                    zipfile.write(chunk)

            unpack_archive(filename=tmpzip_path, extract_dir=tmp_dir)

    return Path(tmp_dir) / zipname.replace(".zip", ".csv")


@task(tags=["extract"])
def convert_to_parquet(csv_path: Path, pq_path: Path, test: bool = False) -> None:
    """Converts csv to parquet format for compression

    Parameters:
    -----------
    csv_path: Path
        path to csv
    pq_path: Path
        path to converted parquet

    Returns
    --------
    None
    """
    logger = get_run_logger()
    if test:
        nrows = 100
    else:
        nrows = None
    df = pd.read_csv(csv_path, nrows=nrows)
    logger.info(f"{len(df)} rows read\ncd ..dtypes: \n{df.dtypes}")
    # cast datetime
    creation_datetime = pd.to_datetime(df["Creation Date"])

    # extract ward name and ward ID
    col_name = "ward_name"
    col_id = "ward_id"

    def extract_name_id(ward: str) -> pd.Series:
        idx = ward.index("(")
        ward_name = ward[: idx - 1]
        ward_id = int(ward[idx + 1 : idx + 3])
        return pd.Series([ward_name, ward_id], [col_name, col_id])

    ward_ids = (
        df["Ward"].apply(extract_name_id).astype({col_name: "string", col_id: "Int8"})
    )

    df_drop = df.drop(columns=["Creation Date", "Ward"]).astype("string")
    df_union = pd.concat([df_drop, ward_ids], axis=1)
    df_union["creation_datetime"] = creation_datetime
    logger.info(f"union cols:\n{df_union.columns}\n dtypes:\n{df_union.dtypes}")
    df_union.to_parquet(pq_path, index=False)


@task(tags=["extract"])
def blob_exists(blob_path: str, bucket_name: str) -> bool:
    """
    Does this blob exist?
    """
    logger = get_run_logger()
    gcs = storage.Client()
    bucket = gcs.bucket(bucket_name=bucket_name)
    exists = storage.Blob(bucket=bucket, name=blob_path).exists(client=gcs)
    logger.info(f"{blob_path} already exists: {exists}")
    return exists


@task(tags=["extract"])
def upload_gcs(bucket_name: str, src_file: Path, dst_file: str):
    """
    Upload the local parquet file to GCS
    Ref: https://cloud.google.com/storage/docs/uploading-objects#storage-upload-object-python
    Authentication woes:
    https://cloud.google.com/docs/authentication/client-libraries
    MUST SET UP APPLICATION DEFAULT CREDENTIALS FOR CLIENT LIBRARIES
    DOES NOT USE SAME CREDS AS GCLOUD AUTH
    USE gcloud auth application-default login
    To use service accounts (instead of user accounts),
    env var GOOGLE_APPLICATION_CREDENTIALS='/path/to/key.json'
    especially relevant for docker images, if they have fine-grain
    controlled permissions
    not required if you're on a credentialled GCE
    """
    logger = get_run_logger()
    logger.info(f"{bucket_name}: storage bucket\n{dst_file}: destination file")
    gcs_client = storage.Client()
    bucket = gcs_client.bucket(bucket_name)
    blob = bucket.blob(dst_file)

    # set to zero to avoid overwrite
    try:
        blob.upload_from_filename(
            src_file,
            # if_generation_match=int(replace),
            timeout=90,
        )
    except Exception as e:
        logger.error(f"Error raised:\n{e}")
    logger.info(f"{src_file} uploaded to {dst_file}")


@flow()
def extract_service_calls(
    bucket_name: str,
    year: str = "2020",
    # csv_dir: str = "../data/notebooks",
    # pq_dir: str = "../data/notebooks",
    overwrite: bool = True,
    test: bool = False,
):
    """
    Downloads the zipped csv from opendata API and stores as parquet
    """
    logger = get_run_logger()
    zip_uri = get_zip_uri(year)
    fname = zip_uri.split("/")[-1]
    # gsc paths
    csv_path = f'raw/csv/{fname.replace("zip", "csv")}'
    pq_path = f'raw/pq/{fname.replace("zip", "parquet")}'
    csv_exists = blob_exists(csv_path, bucket_name)
    pq_exists = blob_exists(pq_path, bucket_name)
    # save csv to temp dir for conversion to pq and upload
    with TemporaryDirectory() as tmp_dir:
        if not pq_exists or overwrite:
            if not csv_exists or overwrite:
                logger.info(f"downloading from {zip_uri} and extracting to {tmp_dir}")
                tmpcsv_path = extract(zip_uri=zip_uri, tmp_dir=tmp_dir)
                logger.info(f"Uploading csv to {csv_path}")
                upload_gcs(
                    bucket_name=bucket_name, src_file=tmpcsv_path, dst_file=csv_path
                )
            else:
                logger.warning(f"{csv_path} already exists")
                tmpcsv_path = f"gs://{bucket_name}/{csv_path}"
                logger.info(f"{tmpcsv_path} will be read instead")

            logger.info(f"Converting to {pq_path}")
            convert_to_parquet(
                csv_path=tmpcsv_path, pq_path=f"gs://{bucket_name}/{pq_path}", test=test
            )
        else:
            logger.warning(f"{pq_path} already exists")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        prog="Fetch311Records",
        description="Fetch 311 service records and stores as parquet",
        epilog="DE zoomcamp project",
    )
    opt = parser.add_argument
    opt(
        "-b",
        "--bucket_name",
        type=str,
        help="GCS bucket to store the CSV and parquet files",
    )
    opt("-y", "--year", default="2020", type=str)
    # opt('-c', '--csv_dir', type=str, help='directory to store unzipped csv')
    # opt('-p', '--pq_dir', type=str, help='directory to store parquet')
    opt(
        "-O",
        "--overwrite",
        action="store_true",
        default=False,
        help="If specified, overwrites existing parquet file",
    )
    opt(
        "-t",
        "--test",
        action="store_true",
        default=False,
        help="If specified, only reads small section of csv",
    )
    args = parser.parse_args()
    extract_service_calls(
        bucket_name=args.bucket_name,
        year=args.year,
        # csv_dir=args.csv_dir,
        # pq_dir=args.pq_dir,
        overwrite=args.overwrite,
        test=args.test,
    )