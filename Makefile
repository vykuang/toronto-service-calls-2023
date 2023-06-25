# Take vars directly from shell env var
# fills in empty string if not supplied

# LOCAL_TAG:=$(shell date +"%Y%m%d_%H%M%S")
# LOCAL_IMG_NAME:=stream-model-duration:${LOCAL_TAG}
# TF_VAR_region:=us-west1
# TF_VAR_repository:=task-containers
# IMAGE_EL:=extract_load
# IMAGE_T:=dbt

quality_checks:
	black .

export_reqs:
	poetry export -f requirements.txt -o dockerfiles/requirements.txt

build_prep: quality_checks export_reqs

build_dev: build_prep
	docker build -t vykuang/service-calls:dev-${LOCAL_TAG} .

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
