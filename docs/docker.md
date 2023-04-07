# Containerizing the app

## Credentials

### Local

In local dev environment, pass the application default credential that's created through the web-based authentication flow. By default that is stored in `~/.config/gcloud/application_default_credentials.json`. Mount that as a volume, and pass an environment variable that points to the mount location:

```bash
ADC=~/.config/gcloud/application_default_credentials.json
docker run \
    <YOUR PARAMS> \
    -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/keys/FILE_NAME.json \
    -v ${ADC}:/tmp/keys/FILE_NAME.json:ro
```

Alternatively, mount the entire `~/.config/gcloud` folder directly to the container's own `~/.config/gcloud`, without specifying the ADC env var

### Production

Ideally we don't pass any credentials and [configure specific IAM roles](https://cloud.google.com/run/docs/authenticating/service-to-service) handle authentication. Concretely speaking, if we're deploying this container to cloud, whatever's running the container should have a service account attached to it that already has the necessary permissions

### Execution

There's two ways:

1. Since the code is already written as a flow, we set up the environment in which to run the code. The container only `poetry installs` all dependencies for the code to run.
2. We encapsulate the code inside the container, and the prefect flow is further abstracted to a mere invocation of this container, while still supplying the necessary arguments
    - existing work resembles the first option more, so let's go with 1.

### Custom image

Due to the size of dependencies, it would be faster to pre-package it as an image to be pulled, instead of installing them at runtime at each invocation

Dockerfile will set up poetry and run `poetry install`. Presumably prefect will load the flow code inside and run it. Uncertainty here is that I'll need to run `poetry run`, and I don't think prefect will do that. In fact I have no idea how prefect will execute the code inside a custom image.

Let's try it locally by mounting the flow code

- `gcloud` not installed, obviously
- needed `poetry run` in order to access the poetry env
- supply `GOOGLE_CLOUD_PROJECT=${TF_VAR_project_id}` in list of env vars
- supply `PREFECT_API_KEY` and `PREFECT_API_URL`? I think it needs to access the google secret for the key.
