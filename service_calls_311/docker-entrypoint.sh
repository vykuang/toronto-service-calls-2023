#!/bin/sh

# exit script if error occurs
set -e # 1
# expand args passed to --entrypoint to support ENV VAR substitution
eval "exec $@" # 2
