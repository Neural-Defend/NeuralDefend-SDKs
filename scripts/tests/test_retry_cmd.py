from __future__ import annotations

import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RETRY_CMD = ROOT / "scripts" / "retry_cmd.sh"


class RetryCmdTests(unittest.TestCase):
    def _run(
        self,
        *args: str,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        merged = os.environ.copy()
        if env:
            merged.update(env)
        return subprocess.run(
            ["bash", str(RETRY_CMD), *args],
            check=False,
            capture_output=True,
            text=True,
            env=merged,
        )

    def test_succeeds_on_first_attempt(self) -> None:
        result = self._run("true")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stderr, "")

    def test_retries_until_success(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            counter = Path(tmp) / "counter"
            script = Path(tmp) / "flaky.sh"
            script.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "count_file=$1\n"
                "count=$(cat \"$count_file\" 2>/dev/null || echo 0)\n"
                "count=$((count + 1))\n"
                "echo \"$count\" > \"$count_file\"\n"
                "test \"$count\" -ge 2\n",
                encoding="utf-8",
            )
            script.chmod(script.stat().st_mode | stat.S_IEXEC)
            result = self._run(
                "bash",
                str(script),
                str(counter),
                env={"RETRY_ATTEMPTS": "3", "RETRY_DELAY_SECONDS": "0"},
            )
            self.assertEqual(result.returncode, 0)
            self.assertIn("attempt 1/3", result.stderr)
            self.assertEqual(counter.read_text(encoding="utf-8").strip(), "2")

    def test_fails_after_configured_attempts(self) -> None:
        result = self._run(
            "false",
            env={"RETRY_ATTEMPTS": "2", "RETRY_DELAY_SECONDS": "0"},
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("attempt 1/2", result.stderr)

    def test_requires_a_command(self) -> None:
        result = self._run()
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage:", result.stderr)


if __name__ == "__main__":
    unittest.main()
