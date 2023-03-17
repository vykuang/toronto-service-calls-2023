#!/usr/bin/env python
# coding: utf-8

from pathlib import Path
import requests
from shutil import unpack_archive
import pandas as pd
from tempfile import TemporaryDirectory
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
def extract(zip_uri: str, csv_dir: Path, chunk_size=10000):
    """
    Downloads zip from source to temporary dir, extracts and unzip the csv
    to csv_dir

    Parameters:
    -------------
    zip_uri: str
        URI for the zip file to download, from open data directory

    csv_dir: str
        folder to store the unzipped csv

    chunk_size: int
        chunk size in bytes used to stream the download

    Returns:
    --------
    None
    """
    zipname = zip_uri.split("/")[-1]
    with requests.get(zip_uri, stream=True, timeout=4) as tmpzip:
        tmpzip.raise_for_status()
        with TemporaryDirectory() as tmpdir:
            tmpzip_path = Path(tmpdir) / zipname
            with open(tmpzip_path, "wb") as zipfile:
                for chunk in tmpzip.iter_content(chunk_size=chunk_size):
                    zipfile.write(chunk)

            unpack_archive(filename=tmpzip_path, extract_dir=csv_dir)


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


@flow()
def extract_service_calls(
    year: str = "2020",
    csv_dir: str = "../data/notebooks",
    pq_dir: str = "../data/notebooks",
    overwrite: bool = True,
    test: bool = False,
):
    """
    Downloads the zipped csv from opendata API and stores as parquet
    """
    logger = get_run_logger()
    zip_uri = get_zip_uri(year)
    fname = zip_uri.split("/")[-1]
    csv_path = Path(csv_dir) / fname.replace("zip", "csv")
    if not csv_path.exists():
        logger.info(f"downloading and extracting to {csv_path}")
        extract(zip_uri=zip_uri, csv_dir=csv_dir)
    else:
        logger.info(f"{csv_path} already exists")
    pq_path = Path(pq_dir) / fname.replace("zip", "parquet")
    if not pq_path.exists() or overwrite:
        logger.info(f"Converting to {pq_path}")
        convert_to_parquet(csv_path=csv_path, pq_path=pq_path, test=test)
    else:
        logger.info(f"{pq_path} already exists")


if __name__ == "__main__":
    extract_service_calls(test=True)
