# Data engineering zoomcamp - Project

This is a visualization of the service calls initiated by Toronto citizens. The choropleth map is broken down into the resident's ward and their forward sortation area (FSA), as well as the types of requests being made. The result is a heatmap of the types of service requests fulfilled by each neighborhood in Toronto.

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
- orchestration: Prefect
    - facilitates monthly refresh: pull, process, store models
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