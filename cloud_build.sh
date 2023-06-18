#! /usr/bin/env sh
gcloud builds submit \
    --config=cloudbuild.yaml \
    --substitutions=_LOCATION="us-west1",_REPOSITORY="task-containers",_IMAGE1="quickstart-sample",_IMAGE2="agent:test" .
