# Init Server

This is an init container for the arkitekt platform. It provisions a MinIO
server — creating the buckets, users and access policies defined in a config
file — by driving the bundled MinIO client (`mc`).

It is published as the multi-arch image `jhnnsrs/init` (`linux/amd64` +
`linux/arm64`); the correct `mc` binary is downloaded per architecture at build
time, so it runs natively on both x86-64 and ARM hosts.

## Usage

The init container is used in the `initContainers` section of a deployment, run
once before the main workload to prepare MinIO.

### Environment variables

| Variable             | Required | Description                                      |
| -------------------- | -------- | ------------------------------------------------ |
| `MINIO_HOST`         | yes      | MinIO endpoint, e.g. `http://minio:9000`         |
| `MINIO_ROOT_USER`    | yes      | MinIO root access key                            |
| `MINIO_ROOT_PASSWORD`| yes      | MinIO root secret key                            |
| `CONFIG_PATH`        | no       | Path to the config file (default `./config.yaml`)|
| `LOG_LEVEL`          | no       | Log verbosity, e.g. `DEBUG` / `INFO` (default `INFO`) |

Missing required variables cause the container to exit non-zero with a clear
message rather than silently doing nothing.

### Configuration

Mount a `config.yaml` (or point `CONFIG_PATH` at it) describing the buckets and
users to create:

```yaml
buckets:
  - name: media
  - name: zarr

users:
  - name: media-service
    access_key: media
    secret_key: changeme
    policies:
      - readwrite
```

## Debugging

The init script emits structured, timestamped logs of every step:

- host platform and architecture, and the resolved `mc --version`, are logged on
  startup — making an architecture-mismatched `mc` ("exec format error") obvious
  immediately instead of failing silently downstream;
- each `mc` command is logged before it runs (secrets are masked), and any
  non-zero exit is logged with stdout/stderr **and aborts the container** (it no
  longer swallows failures);
- set `LOG_LEVEL=DEBUG` to also see `mc` stdout for successful commands.

## Building

The image is built and pushed by CI for both architectures. To build locally:

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -t jhnnsrs/init:dev --push .
```
