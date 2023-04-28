FROM prefecthq/prefect:2.8.4-python3.10
RUN apt-get update && apt-get install
RUN pip install -U pip

WORKDIR /service

COPY requirements.txt ./
# RUN poetry export --only main -f requirements.txt -o requirements.txt
RUN pip install --no-cache-dir --no-input --no-deps -r requirements.txt

WORKDIR /opt/prefect
