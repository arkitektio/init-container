# syntax=docker/dockerfile:1

# Pinned by digest as well as by tag. 3.14.7 is the newest stable CPython — 3.15 is still
# at release candidate — and it publishes linux/arm64 alongside linux/amd64.
FROM python:3.14.7-slim@sha256:cae66f2ef0ec51a9891263eeee7f987dacf0a9879e8aa9353d5606e0530619a5
WORKDIR /workspace

# Set by CI from the git tag.
ARG VERSION="0.0.0"

LABEL org.opencontainers.image.title="init" \
      org.opencontainers.image.description="Creates the buckets an Arkitekt deployment expects, then exits" \
      org.opencontainers.image.source="https://github.com/arkitektio/init-container" \
      org.opencontainers.image.version="${VERSION}"

# The MinIO client, by release rather than by the moving `mc` symlink, and checked against
# the checksum MinIO publishes beside it. Everything this container does, it does through
# `mc`, so an unverified download of it is the whole trust boundary.
ARG TARGETARCH
ARG MC_RELEASE="RELEASE.2025-08-13T08-35-41Z"
ARG MC_SHA256_amd64="01f866e9c5f9b87c2b09116fa5d7c06695b106242d829a8bb32990c00312e891"
ARG MC_SHA256_arm64="14c8c9616cfce4636add161304353244e8de383b2e2752c0e9dad01d4c27c12c"
# Fetched from GitHub releases, not dl.min.io: MinIO took that host down and every
# path under it now answers 410, the pinned version included. The two SHA256 pins
# below are unchanged and still verify -- the GitHub asset is the same artifact,
# byte for byte -- so the trust boundary described above is intact.
# curl is only needed to fetch the mc client; ca-certificates stays for TLS.
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
 && curl -fsSL "https://github.com/minio/mc/releases/download/${MC_RELEASE}/mc.linux-${TARGETARCH}.${MC_RELEASE}" \
      -o /workspace/mc \
 && case "${TARGETARCH}" in \
      amd64) expected="${MC_SHA256_amd64}" ;; \
      arm64) expected="${MC_SHA256_arm64}" ;; \
      *) echo "no mc checksum recorded for ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && echo "${expected}  /workspace/mc" | sha256sum -c - \
 && chmod +x /workspace/mc \
 && apt-get purge -y --auto-remove curl \
 && rm -rf /var/lib/apt/lists/*

# Pinned, so that two builds of the same commit install the same code. `pip install
# pydantic pyyaml` resolved to whatever PyPI served that day.
COPY requirements.txt /workspace/requirements.txt
RUN pip install --no-cache-dir -r /workspace/requirements.txt

COPY . /workspace/

CMD ["python", "init.py"]
