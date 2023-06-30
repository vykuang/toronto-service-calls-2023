# Take vars directly from shell env var
# fills in empty string if not supplied

# LOCAL_TAG:=$(shell date +"%Y%m%d_%H%M%S")
LOCAL_TAG:=$(shell date +"%Y%m%d")
LOCAL_EL_IMAGE:=service-calls:${LOCAL_TAG}
LOCAL_DBT_IMAGE:=service-calls-dbt:${LOCAL_TAG}
DOCKER_REPO:=vykuang
GCP_CONFIG_DIR=/home/${USER}/.config/gcloud
GOOGLE_APPLICATION_CREDENTIALS=/home/root/.config/gcloud/application_default_credentials.json
DBT_PROJECT_DIR:=./dbt-core-service/
KEYFILE_LOCATION=/usr/app/keyfile.json


quality_checks:
	black --fast .

export_reqs:
	poetry export \
	-f requirements.txt \
	-o dockerfiles/requirements.txt

build_prep: quality_checks export_reqs

build_dev: build_prep
	docker build \
	-t ${DOCKER_REPO}/${LOCAL_EL_IMAGE} \
	-f dockerfiles/Dockerfile.extract_load \
	--build-arg GCP_PROJECT_ID=$(TF_VAR_project_id) \
	--build-arg LOCATION=$(TF_VAR_region) \
	--build-arg BQ_DATASET=$(TF_VAR_bq_dataset) \
	--build-arg GCS_BUCKET=$(TF_VAR_gcs_bucket) \
	--build-arg SCRIPT_DIR=jobs/ \
	.

run_dev_local:
	docker run \
	-v=/home/klang/.config/gcloud/:/home/root/.config/gcloud/:ro \
	-e GOOGLE_APPLICATION_CREDENTIALS=$(GOOGLE_APPLICATION_CREDENTIALS) \
	${DOCKER_REPO}/${LOCAL_EL_IMAGE} --year=2023 --overwrite --test

build_dbt_dev:
	docker build \
	-t ${DOCKER_REPO}/${LOCAL_DBT_IMAGE} \
	-f dockerfiles/Dockerfile.dbt \
	--build-arg GCP_PROJECT_ID=$(TF_VAR_project_id) \
	--build-arg BQ_LOCATION=$(TF_VAR_region) \
	--build-arg BQ_DATASET=$(TF_VAR_bq_dataset) \
	--build-arg DBT_PROJECT_DIR=$(DBT_PROJECT_DIR) \
	--build-arg KEYFILE_LOCATION=$(KEYFILE_LOCATION) \
	.

dbt_dev_local:
	docker run \
	-v=${GCP_CONFIG_DIR}/service-dbt.json:$(KEYFILE_LOCATION) \
	-e TARGET=dev \
	${DOCKER_REPO}/${LOCAL_DBT_IMAGE} \

build_prod: build_prep
	docker build -t vykuang/service-calls:prod-latest .

cbuild_dev: build_prep
	gcloud builds submit \
    --config=cloudbuild.yaml \
	--substitutions=_LOCATION=$(TF_VAR_region),_REPOSITORY=$(TF_VAR_repository),_IMAGE_EL=$(IMAGE_EL),_IMAGE_T=$(IMAGE_T) .

cbuild_prod: build_prep
	gcloud builds submit \
	--config=cloudbuild.yaml \
	--substitutions=_LOCATION=$(TF_VAR_region),_REPOSITORY=$(TF_VAR_repository)

check_env:
	@echo ${TEST_ENV}
	@echo ${TEST_ENV2}
