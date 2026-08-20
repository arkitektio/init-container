# syntax=docker/dockerfile:1
FROM python:3.11-slim
WORKDIR /workspace

ARG TARGETARCH
# curl is only needed to fetch the mc client; ca-certificates stays for TLS.
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
 && curl -fsSL https://dl.min.io/client/mc/release/linux-${TARGETARCH}/mc \
      -o /workspace/mc \
 && chmod +x /workspace/mc \
 && apt-get purge -y --auto-remove curl \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir pydantic pyyaml

COPY . /workspace/

CMD ["python", "init.py"]
