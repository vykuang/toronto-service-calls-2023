# Best practices

## Engineering

- managed, serverless containers
- loosely-coupled systems
  - containerization via cloud run
  - orchestration does not touch transformation logic, only scheduling, monitor, logging, restarts
- security via IAM
- orchestration
  - logging
  - restarts
  - monitoring

## Makefile

### Install make

```bash
sudo apt install make
# confirm install
make --version
```

### Usage

Create a `Makefile` in project root. Sample:

```Makefile
integration_test: test
	echo other_thing

quality_checks: integration_test
	isort .
	black .
	pylint .
```

`make quality_checks` will first run `integration_test` (as a dependency) before running its own set of terminal commands

Assign local makefile variables:

```make
LOCAL_TAG:=$(shell date +"%Y-%m-%d-%H-%M-%S")
LOCAL_IMG_NAME:=stream-model-duration:${LOCAL_TAG}
```

### Quirks

Make commands require **tab** indents; but once we're inside a bash script, need to go back to to **spaces** for indents

## pytest
