# Prefect

## integration with gcp

- server on GCE
- worker as cloud run *service*
- package flows as docker containers
- store them in artifact registry
- worker will trigger those containers as cloud run *jobs*

### worker as service

- create service account with these roles
    - `"roles/iam.serviceAccountUser"`
    - `"roles/run.admin"`
- deploy as cloud run service
    - region/allow unauth will be prompted in UI if not spec'd
    - default memory limit of 512MB is not sufficient, so set to 2Gi 

```sh
PREFECT_API_URL=http://$(gcloud compute instances list --filter="name=('server')" --format "value(EXTERNAL_IP)"):4200/api
PREFECT_SERVICE_ACCT=service-agent@to-service-311.iam.gserviceaccount.com
PREFECT_WORK_POOL=service-calls
gcloud run deploy prefect-worker --image=prefecthq/prefect:3-latest \
--set-env-vars PREFECT_API_URL=$PREFECT_API_URL \
--region $TF_VAR_region \
--service-account $PREFECT_SERVICE_ACCT \
--no-cpu-throttling \
--no-allow-unauthenticated \
--memory 2Gi \
--startup-probe httpGet.port=8080,httpGet.path=/health,initialDelaySeconds=100,periodSeconds=20,timeoutSeconds=20 \
--args "prefect","worker","start","--install-policy","always","--with-healthcheck","-p","$PREFECT_WORK_POOL","-t","cloud-run"
```

- min-instances 1 - command not found?? 

### `prefect.yaml`

[docs here](https://docs.prefect.io/integrations/prefect-gcp/gcp-worker-guide#creating-a-prefect-yaml-file)

```sh
prefect init --recipe docker
```

responsible for managing the deployments of this repo

