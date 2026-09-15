from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
RETRY_SMOKE = SCRIPTS / "retry-smoke.sh"


class RetrySmokeTests(unittest.TestCase):
    def _run(
        self, *args: str, env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        merged = os.environ.copy()
        if env:
            merged.update(env)
        return subprocess.run(
            ["bash", str(RETRY_SMOKE), *args],
            capture_output=True,
            text=True,
            env=merged,
            check=False,
        )

    def test_succeeds_on_first_attempt(self) -> None:
        result = self._run("2", "0", "--", "true")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stderr, "")

    def test_retries_then_succeeds(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            counter = Path(temporary) / "attempts"
            counter.write_text("0", encoding="utf-8")
            result = self._run(
                "3",
                "0",
                "--",
                sys.executable,
                "-c",
                (
                    "from pathlib import Path\n"
                    f"path = Path({str(counter)!r})\n"
                    "n = int(path.read_text()) + 1\n"
                    "path.write_text(str(n))\n"
                    "raise SystemExit(1 if n < 2 else 0)\n"
                ),
            )
            self.assertEqual(result.returncode, 0)
            self.assertEqual(counter.read_text(encoding="utf-8"), "2")
            self.assertIn("retrying in 0s", result.stderr)

    def test_exhausts_attempts(self) -> None:
        result = self._run("2", "0", "--", "false", env={"GITHUB_ACTIONS": ""})
        self.assertEqual(result.returncode, 1)
        self.assertIn("failed after 2 attempt(s)", result.stderr)

    def test_rejects_invalid_usage(self) -> None:
        result = self._run("0", "1", "--", "true")
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage:", result.stderr)
