from __future__ import annotations

import base64
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock


SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import check_generated
import generate
import scan_public_artifacts
import spec_tools
import sync_spec


class StrictYamlTests(unittest.TestCase):
    def test_duplicate_mapping_key_is_rejected(self) -> None:
        with self.assertRaisesRegex(spec_tools.SpecError, "duplicate YAML key"):
            spec_tools.load_yaml_bytes(b"openapi: 3.0.3\nopenapi: 3.0.2\n")

    def test_anchor_is_rejected(self) -> None:
        with self.assertRaisesRegex(spec_tools.SpecError, "anchors are forbidden"):
            spec_tools.load_yaml_bytes(b"value: &shared text\nother: text\n")

    def test_alias_is_rejected(self) -> None:
        with self.assertRaisesRegex(spec_tools.SpecError, "aliases are forbidden"):
            spec_tools.load_yaml_bytes(b"other: *shared\n")

    def test_line_endings_are_normalized_without_other_changes(self) -> None:
        raw = b"\xef\xbb\xbfopenapi: 3.0.3\r\ninfo:\rversion\r"
        self.assertEqual(
            spec_tools.normalize_yaml_bytes(raw),
            b"openapi: 3.0.3\ninfo:\nversion\n",
        )


class ContractTests(unittest.TestCase):
    def test_repository_yaml_and_json_are_equal_and_valid(self) -> None:
        yaml_bytes = spec_tools.SPEC_YAML.read_bytes()
        json_bytes = spec_tools.SPEC_JSON.read_bytes()
        document = spec_tools.validate_spec_bytes(yaml_bytes, json_bytes)
        self.assertEqual(spec_tools.deterministic_json(document), json_bytes)

    def test_forbidden_term_scan_covers_yaml_comments(self) -> None:
        yaml_bytes = spec_tools.SPEC_YAML.read_bytes() + b"\n# internal: deepfake\n"
        with self.assertRaisesRegex(spec_tools.SpecError, "forbidden term"):
            spec_tools.validate_spec_bytes(
                yaml_bytes,
                spec_tools.SPEC_JSON.read_bytes(),
            )

    def test_semantic_drift_is_rejected(self) -> None:
        document = json.loads(spec_tools.SPEC_JSON.read_text(encoding="utf-8"))
        document["info"]["version"] = "9.9.9"
        with self.assertRaisesRegex(spec_tools.SpecError, "semantically equal"):
            spec_tools.validate_spec_bytes(
                spec_tools.SPEC_YAML.read_bytes(),
                spec_tools.deterministic_json(document),
            )

    def test_public_artifact_scan_checks_source_and_archives(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            safe = root / "safe.txt"
            safe.write_text("public SDK content", encoding="utf-8")
            archive = root / "package.whl"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("package/module.py", "prediction_tag = 'private'\n")
                output.writestr("package/key.txt", "ghp_" + ("a" * 24))

            self.assertEqual(scan_public_artifacts.scan([safe]), [])
            findings = scan_public_artifacts.scan([archive])
            self.assertTrue(any("prediction_tag" in finding for finding in findings))
            self.assertTrue(any("GitHub token" in finding for finding in findings))


class AtomicAndManifestTests(unittest.TestCase):
    def test_unchanged_atomic_write_does_not_touch_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "value.txt"
            path.write_bytes(b"same")
            before = path.stat().st_mtime_ns
            self.assertEqual(spec_tools.atomic_write_files({path: b"same"}), [])
            self.assertEqual(path.stat().st_mtime_ns, before)

    def test_manifest_comparison_reports_add_delete_and_change(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            generated = root / "generated"
            committed = root / "committed"
            generated.mkdir()
            committed.mkdir()
            (generated / "added.txt").write_text("added", encoding="utf-8")
            (generated / "changed.txt").write_text("new", encoding="utf-8")
            (committed / "deleted.txt").write_text("deleted", encoding="utf-8")
            (committed / "changed.txt").write_text("old", encoding="utf-8")
            self.assertFalse(check_generated._compare("test", generated, committed))


class SyncTests(unittest.TestCase):
    def test_local_source_reads_bytes_from_recorded_commit(self) -> None:
        commit = "494fc8c88585e0920efe54b41f3f8d355025c475"
        blob = "d64d9d0125d186ed24a870dc92390a8140e79eb5"
        committed = b"openapi: 3.0.3\r\ninfo:\r\n  version: 1.0.0\r\n"

        def text_result(arguments: list[str], *, cwd: Path | None = None) -> str:
            del cwd
            command = " ".join(arguments)
            if "status --porcelain" in command:
                return ""
            if arguments[-1] == "HEAD":
                return commit
            if "symbolic-ref" in command:
                return "main"
            if "remote get-url" in command:
                return "git@github.com:Neural-Defend/private-api.git"
            if "--format=%cI" in command:
                return "2026-07-26T03:49:30Z"
            if arguments[-1] == f"{commit}:{sync_spec.SOURCE_PATH}":
                return blob
            self.fail(f"unexpected git command: {arguments}")

        with tempfile.TemporaryDirectory() as temporary:
            checkout = Path(temporary)
            (checkout / ".git").mkdir()
            with (
                mock.patch.object(sync_spec, "_text", side_effect=text_result),
                mock.patch.object(sync_spec, "_run", return_value=committed) as run,
            ):
                source = sync_spec.source_from_path(checkout)

        self.assertEqual(source.raw_bytes, committed)
        run.assert_called_once_with(
            ["git", "show", f"{commit}:{sync_spec.SOURCE_PATH}"],
            cwd=checkout.resolve(),
        )

    def test_provenance_distinguishes_raw_and_normalized_hashes(self) -> None:
        raw = spec_tools.SPEC_YAML.read_bytes().replace(b"\n", b"\r\n")
        source = sync_spec.Source(
            repository="Neural-Defend/private-api",
            reference="production",
            resolved_commit="494fc8c88585e0920efe54b41f3f8d355025c475",
            timestamp="2026-07-26T03:49:30Z",
            raw_bytes=raw,
            blob_sha="d64d9d0125d186ed24a870dc92390a8140e79eb5",
        )
        with tempfile.TemporaryDirectory() as temporary:
            provenance_path = Path(temporary) / "SPEC_SOURCE.json"
            with mock.patch.object(sync_spec, "SPEC_SOURCE", provenance_path):
                outputs = sync_spec.build_outputs(source)
                provenance = json.loads(outputs[provenance_path])
        self.assertNotEqual(
            provenance["source_raw_sha256"],
            provenance["local_normalized_sha256"],
        )
        self.assertEqual(
            provenance["local_normalized_sha256"],
            spec_tools.sha256_bytes(spec_tools.SPEC_YAML.read_bytes()),
        )

    def test_noop_sync_preserves_synced_at(self) -> None:
        source = sync_spec.Source(
            repository="Neural-Defend/private-api",
            reference="production",
            resolved_commit="494fc8c88585e0920efe54b41f3f8d355025c475",
            timestamp="2026-07-26T03:49:30Z",
            raw_bytes=spec_tools.SPEC_YAML.read_bytes(),
            blob_sha="d64d9d0125d186ed24a870dc92390a8140e79eb5",
        )
        with tempfile.TemporaryDirectory() as temporary:
            provenance_path = Path(temporary) / "SPEC_SOURCE.json"
            with mock.patch.object(sync_spec, "SPEC_SOURCE", provenance_path):
                first = sync_spec.build_outputs(source)[provenance_path]
                first_data = json.loads(first)
                first_data["synced_at"] = "2026-07-26T04:00:00Z"
                provenance_path.write_bytes(spec_tools.deterministic_json(first_data))
                second = sync_spec.build_outputs(source)[provenance_path]
        self.assertEqual(
            json.loads(second)["synced_at"],
            "2026-07-26T04:00:00Z",
        )

    def test_github_source_decodes_base64_without_newline_translation(self) -> None:
        raw = b"openapi: 3.0.3\r\ninfo:\r\n  version: 1.0.0\r\n"
        commit = "494fc8c88585e0920efe54b41f3f8d355025c475"
        commit_data = {
            "sha": commit,
            "commit": {"committer": {"date": "2026-07-26T03:49:30Z"}},
        }
        content_data = {
            "encoding": "base64",
            "content": base64.b64encode(raw).decode("ascii"),
            "sha": "d64d9d0125d186ed24a870dc92390a8140e79eb5",
        }
        with mock.patch.object(
            sync_spec,
            "_gh_json",
            side_effect=[commit_data, content_data],
        ):
            source = sync_spec.source_from_github(f"Neural-Defend/private-api@{commit}")
        self.assertEqual(source.raw_bytes, raw)
        self.assertEqual(source.blob_sha, content_data["sha"])


class GeneratorTests(unittest.TestCase):
    def test_generator_image_is_pinned_by_real_digest(self) -> None:
        image = generate.pinned_image()
        self.assertEqual(
            image,
            "openapitools/openapi-generator-cli@"
            "sha256:a620610d9fabf7ce05310c648417ba168125aac2f4517580030e115921ac1a52",
        )

    def test_docker_invocation_uses_an_argument_array_and_offline_network(self) -> None:
        with tempfile.TemporaryDirectory(prefix="path with spaces ") as temporary:
            output = Path(temporary)
            with (
                mock.patch.object(
                    generate,
                    "_docker_user_arguments",
                    return_value=["--user", "1000:1000"],
                ),
                mock.patch.object(generate, "_run") as run,
            ):
                generate._docker_generate(
                    image="repository@sha256:" + ("a" * 64),
                    generator="python",
                    config_path="generator/python.json",
                    output=output,
                )
        arguments = run.call_args.args[0]
        self.assertIsInstance(arguments, list)
        self.assertEqual(
            arguments[:7],
            ["docker", "run", "--rm", "--user", "1000:1000", "--network", "none"],
        )
        self.assertIn(f"type=bind,source={output},target=/output", arguments)

    def test_docker_user_mapping_is_linux_only(self) -> None:
        with (
            mock.patch.object(generate.sys, "platform", "linux"),
            mock.patch.object(generate.os, "getuid", return_value=1001, create=True),
            mock.patch.object(generate.os, "getgid", return_value=1002, create=True),
        ):
            self.assertEqual(generate._docker_user_arguments(), ["--user", "1001:1002"])

        with mock.patch.object(generate.sys, "platform", "win32"):
            self.assertEqual(generate._docker_user_arguments(), [])

    def test_generator_configs_exclude_docs_and_tests(self) -> None:
        for path in (generate.PYTHON_CONFIG, generate.TYPESCRIPT_CONFIG):
            config = json.loads(path.read_text(encoding="utf-8"))
            self.assertTrue(config["hideGenerationTimestamp"])
            self.assertEqual(
                config["globalProperties"],
                {
                    "apiDocs": False,
                    "apiTests": False,
                    "modelDocs": False,
                    "modelTests": False,
                },
            )

    def test_python_postprocess_replaces_generator_todos(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "_core"
            models = root / "models"
            models.mkdir(parents=True)
            (models / "sample.py").write_text(
                "\n".join(
                    [
                        "    def to_json(self) -> str:",
                        '        """Returns the JSON representation of the model using alias"""',
                        "        # TODO: pydantic v2: use .model_dump_json(by_alias=True, exclude_unset=True) instead",
                        "        return json.dumps(self.to_dict())",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            (root / "api_client.py").write_text(
                "        'long': int, # TODO remove as only py3 is supported?\n",
                encoding="utf-8",
            )

            generate._postprocess_python_generated(root)

            model_text = (models / "sample.py").read_text(encoding="utf-8")
            self.assertNotIn("TODO", model_text)
            self.assertIn(
                "return self.model_dump_json(by_alias=True, exclude_unset=True)",
                model_text,
            )
            api_client_text = (root / "api_client.py").read_text(encoding="utf-8")
            self.assertNotIn("TODO", api_client_text)
            self.assertIn("'long': int,", api_client_text)


if __name__ == "__main__":
    unittest.main()
