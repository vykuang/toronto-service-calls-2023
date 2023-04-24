# Transformation with dbt

## dbt vs spark

### Pros

- Since all transforms can be done with SQL, dbt is the simpler choice vs spark
- no setup for clusters/staging bucket
- no overhead required to run the clusters
- the small dataset size doesn't require the distributed computing capability of spark; everything can still be done in-memory, on a single machine

### Cons

- another account/vendor to upkeep? vs only GCP

## Setup

- Connect Bigquery to dbt
  - create service account for dbt with the necessary bigquery permissions
    - viewer - all GCP
    - bq data editor
    - bq job user
    - bq user
    - **bigquery.datasets.create**
  - permission analysis shows all the excessive permissions so there is opportunity to make it more secure
  - Manage key -> add key -> download json key file
- Configure project setup on dbt cloud
  - upload the json key
  - set the dev `dataset`
    - this does not need to be created beforehand
- setup repo via github to allow continuous integration (e.g. run jobs on pull requests)
  - git clone/@git will not enable CI
  - alternatively, create managed repository via dbt, if the email used for dbt cloud is different from the email linked to your github account
    - meant to trial dbt without needing a new repo
    - must contact support to transfer contents out
    - does not support pull requests, and so cannot automatically invoke `dbt build`
- prepare the raw datasets in the data warehouse for dbt to source from
  - loading the data into the warehouse will be part of the upstream pipeline as orchestrated by prefect
