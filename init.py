import subprocess
from pydantic import BaseModel, Field
from typing import Optional, List
import uuid
import os
import yaml

minio_address = os.getenv("MINIO_HOST")
root_user = os.getenv("MINIO_ROOT_USER")
root_password = os.getenv("MINIO_ROOT_PASSWORD")

alias = "local"


class Bucket(BaseModel):
    name: str


class User(BaseModel):
    name: str
    access_key: str
    secret_key: str
    policies: List[str]


class Config(BaseModel):
    users: List[User]
    buckets: List[Bucket]


def main():
    with open("./config.yaml", "r") as f:
        x = yaml.safe_load(f)
        config = Config(**x)

    subprocess.call(
        f"./mc alias set {alias} {minio_address} {root_user} {root_password}",
        shell=True,
    )

    for bucket in config.buckets:
        subprocess.call(f"./mc mb {alias}/{bucket.name}", shell=True)

    for user in config.users:
        subprocess.call(
            f"./mc admin user add {alias} {user.access_key} {user.secret_key}",
            shell=True,
        )
        for policy in user.policies:
            subprocess.call(
                f"./mc admin policy attach {alias} {policy} --user {user.access_key}",
                shell=True,
            )


if __name__ == "__main__":
    main()
