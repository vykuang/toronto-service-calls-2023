# Take vars directly from shell env var
# fills in empty string if not supplied

# LOCAL_TAG:=$(shell date +"%Y%m%d_%H%M%S")
LOCAL_TAG:=$(shell date +"%Y%m%d")
LOCAL_EL_IMAGE:=service-calls:${LOCAL_TAG}
LOCAL_DBT_IMAGE:=service-calls-dbt:${LOCAL_TAG}
DOCKER_REPO:=vykuang
ARTIFACT_REGISTRY:=task-containers
GCP_CONFIG_DIR=/home/${USER}/.config/gcloud
GOOGLE_APPLICATION_CREDENTIALS=/home/root/.config/gcloud/application_default_credentials.json
HOST_PROJECT_DIR:=./dbt-core-service/
KEYFILE_LOCATION=/usr/dbt/auth/keyfile.json


quality_checks:
	black --fast .

export_reqs:
	poetry export \
	-f requirements.txt \
	-o dockerfiles/requirements.txt

build_prep: quality_checks export_reqs

build_docker: build_prep
	docker build \
	-t ${DOCKER_REPO}/${LOCAL_EL_IMAGE} \
	-f dockerfiles/Dockerfile.extract_load \
	--build-arg GCP_PROJECT_ID=$(TF_VAR_project_id) \
	--build-arg LOCATION=$(TF_VAR_region) \
	--build-arg BQ_DATASET=$(TF_VAR_bq_dataset) \
	--build-arg GCS_BUCKET=$(TF_VAR_gcs_bucket) \
	--build-arg SCRIPT_DIR=jobs/ \
	.

run_docker:
	docker run --rm \
	-v=/home/klang/.config/gcloud/:/home/root/.config/gcloud/:ro \
	-e GOOGLE_APPLICATION_CREDENTIALS=$(GOOGLE_APPLICATION_CREDENTIALS) \
	${DOCKER_REPO}/${LOCAL_EL_IMAGE} --year=2023 --overwrite --test

build_dbt_docker: quality_checks
	docker build \
	-t ${DOCKER_REPO}/${LOCAL_DBT_IMAGE} \
	-f dockerfiles/Dockerfile.dbt \
	--build-arg GCP_PROJECT_ID=$(TF_VAR_project_id) \
	--build-arg BQ_LOCATION=$(TF_VAR_region) \
	--build-arg BQ_DATASET=$(TF_VAR_bq_dataset) \
	--build-arg HOST_PROJECT_DIR=$(HOST_PROJECT_DIR) \
	--build-arg KEYFILE_LOCATION=$(KEYFILE_LOCATION) \
	--build-arg TARGET=docker \
	.

run_dbt_docker: quality_checks
	docker run --rm \
	-v=${GCP_CONFIG_DIR}/service-dbt.json:$(KEYFILE_LOCATION) \
	--entrypoint="/usr/local/bin/dbt"  \
	${DOCKER_REPO}/${LOCAL_DBT_IMAGE} test --target=docker


cbuild: build_prep
	gcloud builds submit \
    --config=cloudbuild.yaml \
	--substitutions=_REPOSITORY=$(TF_VAR_repository),_IMAGE_EL=$(IMAGE_EL),_IMAGE_T=$(IMAGE_T) .

cbuild_prod: build_prep
	gcloud builds submit \
	--config=cloudbuild.yaml \
	--substitutions=_REPOSITORY=$(TF_VAR_repository)

cbuild_dbt: build_prep
check_env:
	@echo ${TEST_ENV}
	@echo ${TEST_ENV2}
