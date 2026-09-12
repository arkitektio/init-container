# syntax=docker/dockerfile:1

# Pinned by digest as well as by tag. 3.14.7 is the newest stable CPython — 3.15 is still
# at release candidate — and it publishes linux/arm64 alongside linux/amd64.
FROM python:3.14.7-slim@sha256:cae66f2ef0ec51a9891263eeee7f987dacf0a9879e8aa9353d5606e0530619a5
WORKDIR /workspace

# Set by CI from the git tag.
ARG VERSION="0.0.0"

LABEL org.opencontainers.image.title="init" \
      org.opencontainers.image.description="Creates the buckets and users an Arkitekt deployment expects in RustFS, then exits" \
      org.opencontainers.image.source="https://github.com/arkitektio/init-container" \
      org.opencontainers.image.version="${VERSION}"

# The RustFS client (`rc`), by release and checked against the checksum RustFS
# publishes beside it. Everything this container does, it does through `rc`, so an
# unverified download of it is the whole trust boundary.
#
# This replaced MinIO's `mc`: the storage backend is RustFS now, and `mc`'s admin
# commands (user add, policy attach) speak MinIO's own admin API, which RustFS does
# not serve compatibly. `rc` is the RustFS equivalent and takes the same argument
# shapes, so init.py reads almost identically.
ARG TARGETARCH
ARG RC_VERSION="v0.1.35"
ARG RC_SHA256_amd64="f852392837e2b56c4785ea7f4e4a0e3f58a5df19fe317eb80bcc1bfaa41a2893"
ARG RC_SHA256_arm64="3d8e125f878f295dedeb40a03a85c311588205601f5076fbc8b341fe40b41b1b"
# curl is only needed to fetch the rc client; ca-certificates stays for TLS.
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
 && curl -fsSL "https://github.com/rustfs/cli/releases/download/${RC_VERSION}/rustfs-cli-linux-${TARGETARCH}-${RC_VERSION}.tar.gz" \
      -o /tmp/rc.tar.gz \
 && case "${TARGETARCH}" in \
      amd64) expected="${RC_SHA256_amd64}" ;; \
      arm64) expected="${RC_SHA256_arm64}" ;; \
      *) echo "no rc checksum recorded for ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && echo "${expected}  /tmp/rc.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/rc.tar.gz -C /workspace rc \
 && rm /tmp/rc.tar.gz \
 && chmod +x /workspace/rc \
 && apt-get purge -y --auto-remove curl \
 && rm -rf /var/lib/apt/lists/*

# Pinned, so that two builds of the same commit install the same code. `pip install
# pydantic pyyaml` resolved to whatever PyPI served that day.
COPY requirements.txt /workspace/requirements.txt
RUN pip install --no-cache-dir -r /workspace/requirements.txt

COPY . /workspace/

CMD ["python", "init.py"]
