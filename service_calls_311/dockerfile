FROM python:3.10-slim as base

ENV POETRY_VERSION=1.3.2
ENV POETRY_HOME=/opt/poetry
ENV POETRY_VENV=/opt/poetry-venv

# cache and venv location
ENV POETRY_CACHE_DIR=/opt/.cache

# builder stage for poetry installation
FROM base as builder

# new venv for just poetry, and install poetry with pip; see official doc link
RUN python3 -m venv $POETRY_VENV \
    && ${POETRY_VENV}/bin/pip install --upgrade pip \
    && ${POETRY_VENV}/bin/pip install poetry==${POETRY_VERSION}

# final stage for image
FROM base as app

# copies the poetry installation from builder img to app img
COPY --from=builder ${POETRY_VENV} ${POETRY_VENV}

# allows poetry to be recognized in shell
ENV PATH="${PATH}:${POETRY_VENV}/bin"

# ARG APPDIR=/service
WORKDIR /service

COPY poetry.lock pyproject.toml /service/

# [optional] validate project config
RUN poetry check

# install dependencies
RUN poetry install --no-root --no-interaction --no-cache --without dev

# start in poetry env
ENTRYPOINT ["/bin/bash", "-c", "source $(poetry env info --path)/bin/activate"]
# ENTRYPOINT [ "el.sh" ]
# ENTRYPOINT [ "poetry", "run" ]
# CMD ["python"]
# CMD ["&&", "python", "-c", "import pandas as pd; print(pd.__version__)" ]
