#!/usr/bin/env python
# coding: utf-8

from pathlib import Path
from google.cloud import storage, bigquery
import requests
from shutil import unpack_archive
import pandas as pd
from tempfile import TemporaryDirectory
import argparse
from prefect import flow, task, get_run_logger
from dotenv import load_dotenv
import os

load_dotenv()

LOCATION = os.getenv("TF_VAR_region", default="us-west1")
BUCKET = os.getenv("TF_VAR_data_lake_bucket", default="service-data-lake")
DATASET = os.getenv("TF_VAR_bq_dataset", default="service_calls_models")


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
def extract(zip_uri: str, tmp_dir: Path, chunk_size=10000) -> Path | None:
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
    tmpcsv_path: Path | None
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

    if len(tmp_glob := list(tmp_dir.glob("*.csv"))) == 1:
        tmpcsv_path = tmp_glob[0]
    else:
        tmpcsv_path = None
    return tmpcsv_path


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
    df = pd.read_csv(
        csv_path,
        nrows=nrows,
        # can sub in a callable to process bad lines
        # see https://pandas.pydata.org/pandas-docs/stable/reference/api/pandas.read_csv.html
        on_bad_lines="skip",
    )
    logger.info(f"{len(df)} rows read\ncd ..dtypes: \n{df.dtypes}")
    # cast datetime
    creation_datetime = pd.to_datetime(df["Creation Date"])

    # extract ward name and ward ID
    col_name = "ward_name"
    col_id = "ward_id"

    def extract_name_id(ward: str) -> pd.Series:
        # "(" will not always be found. need to be more robust...
        try:
            idx = ward.index("(")
            ward_name = ward[: idx - 1]
            ward_id = int(ward[idx + 1 : idx + 3])

        except ValueError as e:
            if "substring not found" in repr(e):
                logger.warning("Ward field did not have '(' to search for ID")
                #  set to null
                ward_name = None
                ward_id = None
        finally:
            return pd.Series([ward_name, ward_id], [col_name, col_id])

    ward_ids = (
        df["Ward"].apply(extract_name_id).astype({col_name: "string", col_id: "Int8"})
    )

    df_drop = df.drop(columns=["Creation Date", "Ward"]).astype("string")
    # add ward_id and ward_name
    df_union = pd.concat([df_drop, ward_ids], axis=1)
    # add datetime casted field
    df_union["creation_datetime"] = creation_datetime
    # rename to remove capitals and spaces
    df_union = df_union.rename(columns={"First 3 Chars of Postal Code": "fsa_code"})
    df_union = df_union.rename(mapper=str.lower, axis="columns")
    df_union.columns = df_union.columns.str.replace(" ", "_")
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


@task(tags=["load"])
def load_bigquery(src_uris: str, dest_table: str, location: str = LOCATION):
    """
    Loads file from URIs to bigquery table
    Parameters
    ----------
    src_uris: str
        URIs of data files to be loaded; in format gs://<bucket_name>/<object_name_or_glob>.
    dest_table: str
        Table into which data is to be loaded

    Returns
    -------
    LoadJob class object
    """
    logger = get_run_logger()
    client = bigquery.Client(
        location=location,
        # project=project_id # infer from env
        # credentials=creds # not needed if instance is already credentialled
    )
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.PARQUET,
        time_partitioning=bigquery.TimePartitioning(
            type_=bigquery.TimePartitioningType.DAY, field="creation_datetime"
        ),
        clustering_fields=["service_request_type", "ward_id"],
    )
    load_job = client.load_table_from_uri(
        src_uris,
        dest_table,
        job_config=job_config,
        project=GCP_PROJECT_ID,
    )
    logger.info(f"Job creation time: {load_job.created}")
    load_job.add_done_callback(
        lambda x: logger.info(
            f"Job duration: {load_job.ended - load_job.started}\nState: {load_job.state}"
        )
    )
    load_job.result(timeout=3.0)
    return load_job


@flow()
def extract_service_calls(
    bucket_name: str,
    year: str = "2020",
    overwrite: bool = False,
    test: bool = False,
):
    """
    Downloads the zipped csv from opendata API and stores as parquet in gcs

    Parameters
    ----------
    bucket_name: str
        name of bucket in GCS
    year: str
        year for which to extract the service call request records
    overwrite: bool
        if true, overwrite existing parquet/dataset
    test: bool
        if true, load only a small subset onto bigquery

    Returns
    -------
    gs_pq_path: str
        GS URI of the uploaded parquet
    """
    logger = get_run_logger()
    zip_uri = get_zip_uri(year)
    fname = zip_uri.split("/")[-1]
    # gsc paths
    csv_path = f'raw/csv/{fname.replace("zip", "csv")}'
    pq_path = f'raw/pq/{fname.replace("zip", "parquet")}'
    gs_pq_path = f"gs://{bucket_name}/{pq_path}"
    csv_exists = blob_exists(csv_path, bucket_name)
    pq_exists = blob_exists(pq_path, bucket_name)
    # save csv to temp dir for conversion to pq and upload
    with TemporaryDirectory() as tmp_dir:
        if not pq_exists or overwrite:
            if not csv_exists or overwrite:
                logger.info(f"downloading from {zip_uri} and extracting to {tmp_dir}")
                tmpcsv_path = extract(zip_uri=zip_uri, tmp_dir=Path(tmp_dir))
                logger.info(f"Uploading csv to {csv_path}")
                upload_gcs(
                    bucket_name=bucket_name, src_file=tmpcsv_path, dst_file=csv_path
                )
            else:
                logger.warning(f"{csv_path} already exists")
                tmpcsv_path = f"gs://{bucket_name}/{csv_path}"
                logger.info(f"{tmpcsv_path} will be read instead")

            logger.info(f"Converting to {pq_path}")
            convert_to_parquet(csv_path=tmpcsv_path, pq_path=gs_pq_path, test=test)
        else:
            logger.warning(f"{pq_path} already exists")

    return gs_pq_path


@flow
def load(src_uris: str, dataset_name: str, year: str):
    """
    Loads parquets from GCS to bigquery

    Parameters
    ----------
    src_uris: str
        URIs of data files to be loaded; in format gs://<bucket_name>/<object_name_or_glob>.
    dataset: str
        Bigquery dataset into which data will be loaded. <project_id>.<dataset_id>
        project_id is optional, since it can be taken from environment context by
        bigquery's client library
    year: str
        year which the parquet file belongs to; used to construct table name

    Returns
    -------
    None
    """
    logger = get_run_logger()
    dest_table = f"{dataset_name}.facts_{year}_partitioned"
    logger.info(f"loading from {src_uris} into {dest_table}")
    load_job = load_bigquery(src_uris, dest_table)
    return load_job


@flow
def extract_load_service_calls(
    bucket_name: str,
    dataset_name: str,
    year: str = "2020",
    overwrite: bool = False,
    test: bool = False,
):
    """ "
    Extracts CSV as parquets and loads into bigquery dataset

    Parameters
    ----------
    bucket_name: str
        name of bucket in GCS
    dataset_name: str
        name of dataset in bigquery
    year: str
        year for which to extract the service call request records
    overwrite: bool
        if true, overwrite existing parquet/dataset
    test: bool
        if true, load only a small subset onto bigquery

    """
    gs_pq_path = extract_service_calls(
        bucket_name=bucket_name,
        year=year,
        overwrite=overwrite,
        test=test,
    )
    load_job = load(
        src_uris=gs_pq_path,
        dataset_name=dataset_name,
    )


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
        default=BUCKET,
        help="GCS bucket to store the CSV and parquet files",
    )
    opt(
        "-d",
        "--dataset_name",
        type=str,
        default=DATASET,
        help="bigquery dataset name in which to load table",
    )
    opt("-y", "--year", default="2020", type=str)
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
    extract_load_service_calls(
        bucket_name=args.bucket_name,
        year=args.year,
        dataset_name=args.dataset_name,
        overwrite=args.overwrite,
        test=args.test,
    )
