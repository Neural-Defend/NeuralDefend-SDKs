from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


@pytest.mark.parametrize(
    "command",
    [
        [sys.executable, "-m", "neuraldefend_mcp"],
    ],
    ids=["python-module"],
)
def test_stdio_commands_startup_failure_uses_stderr_only(command: list[str]) -> None:
    package_root = Path(__file__).parents[1]
    env = os.environ.copy()
    env.pop("NEURALDEFEND_API_KEY", None)
    env.pop("NEURALDEFEND_MCP_ALLOWED_DIRS", None)
    env["PYTHONPATH"] = str(package_root / "src")
    completed = subprocess.run(
        command,
        cwd=package_root,
        env=env,
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    assert completed.returncode == 2
    assert completed.stdout == ""
    assert "NEURALDEFEND_API_KEY is required" in completed.stderr


@pytest.mark.asyncio
async def test_stdio_protocol_lists_and_calls_tools(tmp_path: Path) -> None:
    parameters = StdioServerParameters(
        command=sys.executable,
        args=["-m", "neuraldefend_mcp"],
        env={
            "NEURALDEFEND_API_KEY": "test-only-key",
            "NEURALDEFEND_MCP_ALLOWED_DIRS": str(tmp_path),
        },
    )
    async with stdio_client(parameters) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            listed = await session.list_tools()
            names = {tool.name for tool in listed.tools}
            assert names == {
                "detect_image_authenticity",
                "detect_video_authenticity",
            }
            result = await session.call_tool(
                "detect_image_authenticity",
                {"file_path": str(tmp_path / "missing.jpg")},
            )
            assert result.isError
            assert result.structuredContent is not None
            assert result.structuredContent["error"]["code"] == "local_validation"
