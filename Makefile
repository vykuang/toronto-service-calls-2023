
LOCAL_TAG:=$(shell date +"%Y%m%d_%H%M%S")
LOCAL_IMG_NAME:=stream-model-duration:${LOCAL_TAG}
LOCATION:=us-west1
REPOSITORY:=task-containers
IMAGE_EL:=extract_load
IMAGE_T:=dbt
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
	--substitutions=_LOCATION=$(LOCATION),_REPOSITORY=$(REPOSITORY),_IMAGE_EL=$(IMAGE_EL),_IMAGE_T=$(IMAGE_T) .
