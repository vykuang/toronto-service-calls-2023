# Take vars directly from shell env var
# fills in empty string if not supplied

LOCAL_TAG:=$(shell date +"%Y%m%d_%H%M%S")
LOCAL_IMG_NAME:=service-calls:${LOCAL_TAG}
GOOGLE_APPLICATION_CREDENTIALS=/home/root/.config/gcloud/application_default_credentials.json
# TF_VAR_region:=us-west1
# TF_VAR_repository:=task-containers
# IMAGE_EL:=extract_load
# IMAGE_T:=dbt

quality_checks:
	black --fast .

export_reqs:
	poetry export -f requirements.txt -o dockerfiles/requirements.txt

build_prep: quality_checks export_reqs

build_dev: build_prep
	docker build \
	-t vykuang/${LOCAL_IMG_NAME} \
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
	vykuang/service-calls:20230626_161614 --year=2023 --overwrite --test

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
