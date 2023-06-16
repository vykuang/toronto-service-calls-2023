FROM prefecthq/prefect:2.8.4-python3.10
RUN apt-get update && apt-get install
RUN pip install -U pip

WORKDIR /tmp

COPY requirements.txt ./
RUN pip install --no-cache-dir --no-input --no-deps -r requirements.txt --dry-run
# RUN pwd && ls
# RUN head -n 5 requirements.txt

WORKDIR /opt/prefect

COPY jobs/main.py ./

ENTRYPOINT [ "python3", "main.py" ]
