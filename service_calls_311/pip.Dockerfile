FROM prefecthq/prefect:2.8.4-python3.10
RUN pip install -U pip poetry

WORKDIR /service

COPY poetry.lock pyproject.toml /service/
RUN poetry export -f requirements.txt -o requirements.txt
RUN pip install --no-cache-dir --no-input --no-deps -r requirements.txt

WORKDIR /opt/prefect
