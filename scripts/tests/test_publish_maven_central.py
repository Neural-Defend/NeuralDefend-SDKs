from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
import urllib.error
import urllib.request
import zipfile
from pathlib import Path
from typing import Any
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import publish_maven_central as central

ARTIFACT_DIR = "com/neuraldefend/neuraldefend/1.0.0"
FILES = (
    "neuraldefend-1.0.0.jar",
    "neuraldefend-1.0.0-sources.jar",
    "neuraldefend-1.0.0-javadoc.jar",
    "neuraldefend-1.0.0.pom",
    "neuraldefend-1.0.0.module",
)


def write_bundle(path: Path, *, signed: bool = True, skip: tuple[str, ...] = (), extra: tuple[str, ...] = ()) -> Path:
    with zipfile.ZipFile(path, "w") as archive:
        for name in FILES:
            for suffix in ("", ".md5", ".sha1") + ((".asc",) if signed else ()):
                member = f"{ARTIFACT_DIR}/{name}{suffix}"
                if member not in {f"{ARTIFACT_DIR}/{item}" for item in skip}:
                    archive.writestr(member, b"x")
        for member in extra:
            archive.writestr(member, b"x")
    return path


class FakeResponse(io.BytesIO):
    def __enter__(self) -> FakeResponse:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()


class FakePortal:
    def __init__(self, states: list[str], errors: dict[str, Any] | None = None) -> None:
        self.states = states
        self.errors = errors or {}
        self.requests: list[urllib.request.Request] = []

    def __call__(self, request: urllib.request.Request, timeout: float) -> FakeResponse:
        self.requests.append(request)
        if "/upload?" in request.full_url:
            return FakeResponse(b"deployment-123\n")
        state = self.states.pop(0) if len(self.states) > 1 else self.states[0]
        return FakeResponse(json.dumps({"deploymentState": state, "errors": self.errors}).encode())


class VerifyBundleTests(unittest.TestCase):
    def test_complete_signed_bundle_lists_coordinates(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            bundle = write_bundle(Path(temporary) / "bundle.zip")
            self.assertEqual(
                central.verify_bundle(bundle, "1.0.0", require_signatures=True),
                ["com.neuraldefend:neuraldefend:1.0.0"],
            )

    def test_unsigned_bundle_passes_only_in_dry_run_mode(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            bundle = write_bundle(Path(temporary) / "bundle.zip", signed=False)
            central.verify_bundle(bundle, "1.0.0", require_signatures=False)
            with self.assertRaisesRegex(central.PublishError, r"neuraldefend-1\.0\.0\.jar\.asc"):
                central.verify_bundle(bundle, "1.0.0", require_signatures=True)

    def test_missing_javadoc_checksum_and_metadata_are_reported(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            bundle = write_bundle(
                Path(temporary) / "bundle.zip",
                skip=("neuraldefend-1.0.0-javadoc.jar", "neuraldefend-1.0.0.pom.sha1"),
                extra=("com/neuraldefend/neuraldefend/maven-metadata.xml",),
            )
            with self.assertRaises(central.PublishError) as raised:
                central.verify_bundle(bundle, "1.0.0", require_signatures=True)
            message = str(raised.exception)
            self.assertIn("-javadoc.jar (required by Maven Central)", message)
            self.assertIn("missing neuraldefend-1.0.0.pom.sha1", message)
            self.assertIn("maven-metadata.xml", message)

    def test_version_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            bundle = write_bundle(Path(temporary) / "bundle.zip")
            with self.assertRaisesRegex(central.PublishError, "1.0.1"):
                central.verify_bundle(bundle, "1.0.1", require_signatures=True)


class PortalTests(unittest.TestCase):
    def test_upload_sends_bearer_token_and_multipart_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            bundle = write_bundle(Path(temporary) / "bundle.zip")
            portal = FakePortal(["PUBLISHED"])
            token = central.bearer_token("user", "secret")

            deployment = central.upload(bundle, token, "neuraldefend 1.0.0", "AUTOMATIC", portal)

            self.assertEqual(deployment, "deployment-123")
            request = portal.requests[0]
            self.assertIn("publishingType=AUTOMATIC", request.full_url)
            self.assertEqual(request.get_header("Authorization"), "Bearer dXNlcjpzZWNyZXQ=")
            self.assertTrue(request.get_header("Content-type").startswith("multipart/form-data; boundary="))
            assert isinstance(request.data, bytes)
            self.assertIn(b'name="bundle"; filename="bundle.zip"', request.data)
            self.assertIn(bundle.read_bytes(), request.data)

    def test_wait_follows_states_until_published(self) -> None:
        portal = FakePortal(["PENDING", "VALIDATING", "PUBLISHING", "PUBLISHED"])
        sleeps: list[float] = []

        state = central.wait(
            "deployment-123", "token", publishing_type="AUTOMATIC", timeout=600, interval=5,
            opener=portal, sleep=sleeps.append, clock=lambda: 0.0,
        )

        self.assertEqual(state, "PUBLISHED")
        self.assertEqual(sleeps, [5, 5, 5])
        self.assertIn("id=deployment-123", portal.requests[0].full_url)

    def test_failed_deployment_reports_portal_errors(self) -> None:
        portal = FakePortal(["FAILED"], errors={"pkg": ["Invalid signature"]})
        with self.assertRaisesRegex(central.PublishError, "Invalid signature"):
            central.wait("d", "token", publishing_type="AUTOMATIC", timeout=60, interval=1,
                         opener=portal, sleep=lambda _: None, clock=lambda: 0.0)

    def test_timeout_while_publishing_warns_but_succeeds(self) -> None:
        times = iter([0.0, 100.0])
        state = central.wait("d", "token", publishing_type="AUTOMATIC", timeout=50, interval=1,
                             opener=FakePortal(["PUBLISHING"]), sleep=lambda _: None, clock=lambda: next(times))
        self.assertEqual(state, "PUBLISHING")

    def test_timeout_before_validation_fails(self) -> None:
        times = iter([0.0, 100.0])
        with self.assertRaisesRegex(central.PublishError, "still VALIDATING"):
            central.wait("d", "token", publishing_type="AUTOMATIC", timeout=50, interval=1,
                         opener=FakePortal(["VALIDATING"]), sleep=lambda _: None, clock=lambda: next(times))

    def test_user_managed_stops_at_validated(self) -> None:
        state = central.wait("d", "token", publishing_type="USER_MANAGED", timeout=60, interval=1,
                             opener=FakePortal(["VALIDATED"]), sleep=lambda _: None, clock=lambda: 0.0)
        self.assertEqual(state, "VALIDATED")

    def test_http_errors_include_the_portal_detail(self) -> None:
        def reject(request: urllib.request.Request, timeout: float) -> FakeResponse:
            raise urllib.error.HTTPError(request.full_url, 401, "Unauthorized", {}, io.BytesIO(b"bad token"))  # type: ignore[arg-type]

        with self.assertRaisesRegex(central.PublishError, "HTTP 401: bad token"):
            central.status("d", "token", reject)

    def test_missing_credentials_are_rejected(self) -> None:
        with self.assertRaisesRegex(central.PublishError, "MAVEN_CENTRAL_USERNAME"):
            central.bearer_token("", "secret")


class MainTests(unittest.TestCase):
    def test_upload_flow_end_to_end(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            bundle = write_bundle(Path(temporary) / "bundle.zip")
            portal = FakePortal(["PUBLISHED"])
            environment = {"MAVEN_CENTRAL_USERNAME": "user", "MAVEN_CENTRAL_PASSWORD": "secret"}
            with mock.patch.dict(central.os.environ, environment):
                code = central.main([str(bundle), "--version", "1.0.0", "--upload", "--interval", "0"], opener=portal)
            self.assertEqual(code, 0)
            self.assertEqual(len(portal.requests), 2)

    def test_unsigned_upload_is_refused(self) -> None:
        with self.assertRaises(SystemExit):
            central.main(["bundle.zip", "--version", "1.0.0", "--unsigned", "--upload"])

    def test_verification_failure_returns_one_without_network(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            bundle = write_bundle(Path(temporary) / "bundle.zip", signed=False)
            portal = FakePortal(["PUBLISHED"])
            self.assertEqual(central.main([str(bundle), "--version", "1.0.0", "--upload"], opener=portal), 1)
            self.assertEqual(portal.requests, [])


if __name__ == "__main__":
    unittest.main()
