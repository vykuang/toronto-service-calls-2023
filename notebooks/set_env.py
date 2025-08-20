import os
import json
import argparse


def set_env(**envs):
    """Given dict of env vars(name: value),
    set them in the cloud run container
    """
    for env_name in envs:
        print(f"Setting {env_name} = {envs[env_name]}")
        os.environ[env_name] = envs[env_name]


def parse_env_list(env_seq: str) -> dict:
    return {pair.split("=")[0]: pair.split("=")[1] for pair in env_seq.split(",")}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    opt = parser.add_argument
    opt("-i", "--envs", type=parse_env_list)
    args = parser.parse_args()
    set_env(**args.envs)
