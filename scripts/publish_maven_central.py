#!/usr/bin/env python3
"""Verify a Maven Central Portal bundle and optionally upload it and wait for publication.

The bundle is the zip produced by ``./gradlew centralBundle`` in ``packages/kotlin``: a
Maven repository layout holding every published file with checksums and signatures.
Credentials are a Central Portal user token, read from ``MAVEN_CENTRAL_USERNAME`` and
``MAVEN_CENTRAL_PASSWORD``.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile
from collections.abc import Callable
from pathlib import Path, PurePosixPath
from typing import Any

API = "https://central.sonatype.com/api/v1/publisher"
PRIMARY_SUFFIXES = (".jar", ".aar", ".pom", ".module")
CHECKSUM_SUFFIXES = (".md5", ".sha1")
TERMINAL_FAILURE = "FAILED"
PUBLISHED = "PUBLISHED"
MAX_RESPONSE_BYTES = 1024 * 1024

Opener = Callable[..., Any]


class PublishError(Exception):
    """A bundle or Central Portal failure that should stop the release."""


def verify_bundle(bundle: Path, version: str, require_signatures: bool) -> list[str]:
    """Return the artifact coordinates in ``bundle`` or raise when Central would reject it."""

    with zipfile.ZipFile(bundle) as archive:
        names = {name for name in archive.namelist() if not name.endswith("/")}
    if not names:
        raise PublishError(f"{bundle} is empty")
    problems: list[str] = []
    artifacts: dict[str, set[str]] = {}
    for name in sorted(names):
        path = PurePosixPath(name)
        if path.name.startswith("maven-metadata.xml"):
            problems.append(f"{name}: Central generates maven-metadata.xml itself")
            continue
        if not name.endswith(PRIMARY_SUFFIXES):
            continue
        if len(path.parts) < 4 or path.parts[-2] != version:
            problems.append(f"{name}: not in a <group>/<artifact>/{version}/ directory")
            continue
        artifact = path.parts[-3]
        artifacts.setdefault(str(path.parent), set()).add(path.name.removeprefix(f"{artifact}-{version}"))
        required = [name + suffix for suffix in CHECKSUM_SUFFIXES]
        if require_signatures:
            required.append(name + ".asc")
        problems.extend(f"{name}: missing {PurePosixPath(item).name}" for item in required if item not in names)
    if not artifacts:
        problems.append("no publishable artifacts were found")
    for directory, files in sorted(artifacts.items()):
        if ".pom" not in files:
            problems.append(f"{directory}: missing POM")
        if not ({".jar", ".aar"} & files):
            problems.append(f"{directory}: missing the main .jar or .aar")
        for classifier in ("-sources.jar", "-javadoc.jar"):
            if classifier not in files:
                problems.append(f"{directory}: missing {classifier} (required by Maven Central)")
    if problems:
        raise PublishError("bundle is not publishable:\n  " + "\n  ".join(problems))
    return [_coordinates(directory) for directory in sorted(artifacts)]


def _coordinates(directory: str) -> str:
    *group, artifact, version = PurePosixPath(directory).parts
    return f"{'.'.join(group)}:{artifact}:{version}"


def bearer_token(username: str, password: str) -> str:
    if not username or not password:
        raise PublishError("MAVEN_CENTRAL_USERNAME and MAVEN_CENTRAL_PASSWORD are required")
    return base64.b64encode(f"{username}:{password}".encode()).decode("ascii")


def _multipart(field: str, filename: str, payload: bytes) -> tuple[bytes, str]:
    boundary = f"neuraldefend-{uuid.uuid4().hex}"
    head = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="{field}"; filename="{filename}"\r\n'
        "Content-Type: application/octet-stream\r\n\r\n"
    ).encode()
    tail = f"\r\n--{boundary}--\r\n".encode()
    return head + payload + tail, f"multipart/form-data; boundary={boundary}"


def _request(opener: Opener, request: urllib.request.Request) -> bytes:
    try:
        with opener(request, timeout=120) as response:
            return response.read(MAX_RESPONSE_BYTES)
    except urllib.error.HTTPError as error:
        detail = error.read(4096).decode("utf-8", "replace").strip()
        raise PublishError(f"Central Portal returned HTTP {error.code}: {detail}") from None
    except urllib.error.URLError as error:
        raise PublishError(f"could not reach the Central Portal: {error.reason}") from None


def upload(bundle: Path, token: str, name: str, publishing_type: str, opener: Opener) -> str:
    query = urllib.parse.urlencode({"name": name, "publishingType": publishing_type})
    body, content_type = _multipart("bundle", bundle.name, bundle.read_bytes())
    request = urllib.request.Request(
        f"{API}/upload?{query}",
        data=body,
        method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": content_type},
    )
    deployment = _request(opener, request).decode("utf-8").strip()
    if not deployment:
        raise PublishError("Central Portal returned an empty deployment id")
    return deployment


def status(deployment: str, token: str, opener: Opener) -> dict[str, Any]:
    request = urllib.request.Request(
        f"{API}/status?{urllib.parse.urlencode({'id': deployment})}",
        data=b"",
        method="POST",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
    )
    try:
        document = json.loads(_request(opener, request))
    except json.JSONDecodeError as error:
        raise PublishError(f"Central Portal returned invalid status JSON: {error}") from None
    if not isinstance(document, dict) or not isinstance(document.get("deploymentState"), str):
        raise PublishError("Central Portal status response has no deploymentState")
    return document


def wait(
    deployment: str,
    token: str,
    *,
    publishing_type: str,
    timeout: float,
    interval: float,
    opener: Opener,
    sleep: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
) -> str:
    """Poll until the deployment publishes (or validates, for USER_MANAGED) or fails."""

    goal = PUBLISHED if publishing_type == "AUTOMATIC" else "VALIDATED"
    deadline = clock() + timeout
    last = ""
    while True:
        document = status(deployment, token, opener)
        state = document["deploymentState"]
        if state != last:
            print(f"deployment {deployment}: {state}", flush=True)
            last = state
        if state == TERMINAL_FAILURE:
            errors = json.dumps(document.get("errors", {}), indent=2, sort_keys=True)
            raise PublishError(f"Central Portal rejected deployment {deployment}:\n{errors}")
        if state == goal or state == PUBLISHED:
            return state
        if clock() >= deadline:
            if state == "PUBLISHING":
                print(
                    f"::warning::deployment {deployment} is still PUBLISHING; Central finishes it "
                    "without further action. Check https://central.sonatype.com/publishing/deployments.",
                    flush=True,
                )
                return state
            raise PublishError(f"deployment {deployment} is still {state} after {timeout:.0f}s")
        sleep(interval)


def main(argv: list[str] | None = None, opener: Opener = urllib.request.urlopen) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--version", required=True, help="expected artifact version")
    parser.add_argument("--unsigned", action="store_true", help="verify an unsigned dry-run bundle")
    parser.add_argument("--upload", action="store_true", help="upload after verification")
    parser.add_argument("--name", help="deployment name shown in the Central Portal")
    parser.add_argument("--publishing-type", choices=("AUTOMATIC", "USER_MANAGED"), default="AUTOMATIC")
    parser.add_argument("--timeout", type=float, default=3600)
    parser.add_argument("--interval", type=float, default=20)
    args = parser.parse_args(argv)
    if args.upload and args.unsigned:
        parser.error("--upload requires a signed bundle")
    try:
        artifacts = verify_bundle(args.bundle, args.version, require_signatures=not args.unsigned)
        print(f"bundle verified: {', '.join(artifacts)}")
        if not args.upload:
            return 0
        token = bearer_token(os.environ.get("MAVEN_CENTRAL_USERNAME", ""), os.environ.get("MAVEN_CENTRAL_PASSWORD", ""))
        deployment = upload(args.bundle, token, args.name or args.bundle.stem, args.publishing_type, opener)
        print(f"uploaded deployment {deployment}", flush=True)
        wait(
            deployment,
            token,
            publishing_type=args.publishing_type,
            timeout=args.timeout,
            interval=args.interval,
            opener=opener,
        )
    except (OSError, zipfile.BadZipFile, PublishError) as error:
        print(f"Maven Central publish failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
