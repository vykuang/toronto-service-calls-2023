# Data engineering zoomcamp - 311 Service Calls

This is a visualization of the service calls initiated by Toronto citizens. The choropleth map is broken down into the resident's ward and their forward sortation area (FSA), as well as the types of requests being made. The result is a heatmap of the types of service requests fulfilled by each neighborhood in Toronto.

## Motivation

Besides finding the area with the most noise complaints, this project is an exercise in implementing a data pipeline that incorporates reliability, traceability, and resiliency. Concretely speaking, a pipeline following those principles should have these characteristics:

- restartable - can each step be replayed without introducing duplicates or creating errors?
- monitoring and logging - each step should provide some heartbeat pulse if successful, or error logs if otherwise
- simple - no extra code
- able to handle schema drift *or* enforce a data contract
- efficiency - relating to reliability, how do we model our data to minimize compute? Perhaps via partitioning and/or clustering, or creating a compact view for end-user to query against, instead of querying against the whole dataset
- able to handle late data
- good data quality - processing to remove void entries, e.g. entries missing ward or FSA code

## Data visualization


## Project architecture

- Data is pulled on a monthly basis to sync with its refresh rate at the source
- data lake: GCS
    - stores raw csv and cleaned parquets
- batch processing: dataproc (spark)
    - remove outliers in dates
    - remove entries without ward/FSA data
    - feature engineer
- data warehouse: Bigquery
    - stores the various models used for visualizations
    - partitioning/clustering
- orchestration: Prefect
    - facilitates monthly refresh: pull, process, store models
    - monitoring and logging
    - restarts
    - handles late data
- Visualization: Metabase/Streamlit
    - combine with geojson to produce choropleth map
- IaC: Terraform
    - responsible for cloud infra
    - bucket
    - bigquery dataset
    - dataproc cluster

## Run it yourself!


## data resources

Full credits to statscan and open data toronto for providing these datasets.

- [city ward geojson](https://open.toronto.ca/dataset/city-wards/)
- [forward sortation area boundary file](https://www12.statcan.gc.ca/census-recensement/2011/geo/bound-limit/bound-limit-2016-eng.cfm)
    - FSA is the first three characters in the postal code and correspond roughly to a neighborhood
- [Article on converting that to geojson](https://medium.com/dataexplorations/generating-geojson-file-for-toronto-fsas-9b478a059f04)
- [311 service requests](https://open.toronto.ca/dataset/311-service-requests-customer-initiated/)
- [article on using folium](https://realpython.com/python-folium-web-maps-from-data/)


## Log

- 23/3/14 - Outline project architecture - 311 service calls
- 23/3/15 - download 311 service data from open data toronto
- 23/3/16 - choropleth with geojson in folium