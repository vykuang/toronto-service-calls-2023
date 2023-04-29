
LOCAL_TAG:=$(shell date +"%Y%m%d_%H%M%S")
LOCAL_IMG_NAME:=stream-model-duration:${LOCAL_TAG}

quality_checks:
	black .

export_reqs:
	poetry export -f requirements.txt -o requirements.txt

build_dev: quality_checks export_reqs
	docker build -t vykuang/service-calls:dev-${LOCAL_TAG} .

build_prod: quality_checks export_reqs
	docker build -t vykuang/service-calls:prod-latest
