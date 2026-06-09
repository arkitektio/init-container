import logging
import os
import platform
import subprocess
import sys
from typing import List, NamedTuple

import yaml
from pydantic import BaseModel

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("init")

MC = "./mc"
ALIAS = "local"
CONFIG_PATH = os.getenv("CONFIG_PATH", "./config.yaml")


class Credentials(NamedTuple):
    address: str
    user: str
    password: str


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


def mask(secret: str) -> str:
    """Mask a secret for logging, keeping a short prefix for debuggability."""
    if not secret:
        return "<empty>"
    if len(secret) <= 4:
        return "*" * len(secret)
    return secret[:2] + "*" * (len(secret) - 2)


def run_mc(*args: str, redact: int = -1) -> subprocess.CompletedProcess:
    """Run an `mc` subcommand, logging the (optionally redacted) command and its
    output, and raising on a non-zero exit.

    `redact` is the index into `args` of an argument to mask in logs (e.g. a
    secret key); use -1 to log everything.
    """
    shown = list(args)
    if 0 <= redact < len(shown):
        shown[redact] = mask(shown[redact])
    logger.info("Running: %s %s", MC, " ".join(shown))

    result = subprocess.run(
        [MC, *args],
        capture_output=True,
        text=True,
    )
    if result.stdout.strip():
        logger.debug("stdout: %s", result.stdout.strip())
    if result.returncode != 0:
        logger.error(
            "Command failed (exit %s): %s %s",
            result.returncode,
            MC,
            " ".join(shown),
        )
        if result.stdout.strip():
            logger.error("stdout: %s", result.stdout.strip())
        if result.stderr.strip():
            logger.error("stderr: %s", result.stderr.strip())
        result.check_returncode()  # raises CalledProcessError
    return result


def check_environment() -> Credentials:
    """Read required configuration from the environment, failing fast with a
    clear message if anything is missing."""
    address = os.getenv("MINIO_HOST")
    user = os.getenv("MINIO_ROOT_USER")
    password = os.getenv("MINIO_ROOT_PASSWORD")

    missing = [
        name
        for name, value in (
            ("MINIO_HOST", address),
            ("MINIO_ROOT_USER", user),
            ("MINIO_ROOT_PASSWORD", password),
        )
        if not value
    ]
    if missing:
        logger.error("Missing required environment variables: %s", ", ".join(missing))
        sys.exit(1)

    assert address and user and password  # narrowed for the type checker
    return Credentials(address=address, user=user, password=password)


def log_diagnostics(creds: Credentials) -> None:
    """Log host/binary details that make arch-mismatch bugs obvious."""
    logger.info("Host platform: %s %s", platform.system(), platform.machine())
    logger.info("MinIO address: %s", creds.address)
    logger.info("Root user: %s", creds.user)
    logger.info("Root password: %s", mask(creds.password))
    logger.info("Config path: %s", CONFIG_PATH)
    try:
        version = subprocess.run(
            [MC, "--version"], capture_output=True, text=True, check=True
        )
        logger.info("mc binary: %s", version.stdout.strip().splitlines()[0])
    except FileNotFoundError:
        logger.error("mc binary not found at %s", MC)
        sys.exit(1)
    except subprocess.CalledProcessError as exc:
        # An arch-mismatched binary ("exec format error") surfaces right here
        # instead of silently no-op'ing later.
        logger.error("Failed to execute mc binary: %s", exc)
        logger.error(
            "This usually means the bundled mc is built for the wrong "
            "architecture (host is %s).",
            platform.machine(),
        )
        sys.exit(1)


def main() -> None:
    logger.info("Initializing MinIO server...")
    creds = check_environment()
    log_diagnostics(creds)

    logger.info("Loading config from %s", CONFIG_PATH)
    with open(CONFIG_PATH, "r") as f:
        config = Config(**yaml.safe_load(f))
    logger.info(
        "Loaded config: %d bucket(s), %d user(s)",
        len(config.buckets),
        len(config.users),
    )

    run_mc("alias", "set", ALIAS, creds.address, creds.user, creds.password, redact=5)

    for bucket in config.buckets:
        logger.info("Ensuring bucket: %s", bucket.name)
        run_mc("mb", "--ignore-existing", f"{ALIAS}/{bucket.name}")

    for user in config.users:
        logger.info("Creating user: %s (access key: %s)", user.name, user.access_key)
        run_mc(
            "admin", "user", "add", ALIAS, user.access_key, user.secret_key, redact=5
        )
        for policy in user.policies:
            logger.info("Attaching policy %s to user %s", policy, user.access_key)
            run_mc(
                "admin",
                "policy",
                "attach",
                ALIAS,
                policy,
                "--user",
                user.access_key,
            )

    logger.info("MinIO initialization complete.")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        # Already logged with full output by run_mc; exit non-zero without
        # dumping a traceback (its args repr would expose secrets).
        logger.error("Aborting: mc command exited with status %s", exc.returncode)
        sys.exit(1)
    except Exception as exc:  # noqa: BLE001 - top-level guard for a clean exit
        logger.exception("Aborting: unexpected error during initialization: %s", exc)
        sys.exit(1)
