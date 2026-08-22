"""Stdio-only MCPServer entry point."""

from __future__ import annotations

import sys
from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager
from dataclasses import dataclass

from mcp.server.mcpserver import Context, MCPServer
from mcp.types import CallToolResult, TextContent

from .config import APIEnvironment, ConfigurationError, ServerConfig, load_config
from .results import ToolOutcome
from .sdk_adapter import NeuralDefendSDKAdapter, SDKAdapter
from .service import MediaAuthenticityService

AdapterFactory = Callable[[str, APIEnvironment], SDKAdapter]


@dataclass
class AppContext:
    service: MediaAuthenticityService
    adapter: SDKAdapter


def _call_result(outcome: ToolOutcome) -> CallToolResult:
    return CallToolResult(
        content=[TextContent(type="text", text=outcome.text())],
        structured_content=outcome.structured(),
        is_error=outcome.is_error,
    )


def create_server(
    config: ServerConfig | None = None,
    *,
    adapter_factory: AdapterFactory = NeuralDefendSDKAdapter,
) -> MCPServer:
    """Create a server; configuration and the shared client are owned by its lifespan."""

    @asynccontextmanager
    async def lifespan(_server: MCPServer) -> AsyncIterator[AppContext]:
        active_config = config or load_config()
        adapter = adapter_factory(active_config.api_key, active_config.environment)
        try:
            yield AppContext(
                service=MediaAuthenticityService(active_config, adapter),
                adapter=adapter,
            )
        finally:
            adapter.close()

    server = MCPServer(
        "NeuralDefend Media Authenticity",
        instructions=(
            "Analyze only explicitly authorized local media. Rejections are unscorable, "
            "not authentic. Keep video and audio decisions separate."
        ),
        lifespan=lifespan,
    )

    @server.tool()
    async def detect_image_authenticity(
        file_path: str,
        ctx: Context[AppContext],
    ) -> CallToolResult:
        """Assess an authorized single-face image for authenticity risk."""

        outcome = await ctx.request_context.lifespan_context.service.detect_image(file_path)
        return _call_result(outcome)

    @server.tool()
    async def detect_video_authenticity(
        file_path: str,
        ctx: Context[AppContext],
        max_frames: int = 12,
    ) -> CallToolResult:
        """Assess authorized video and audio as independent authenticity risks."""

        outcome = await ctx.request_context.lifespan_context.service.detect_video(
            file_path,
            max_frames,
        )
        return _call_result(outcome)

    return server


mcp = create_server()


def main() -> None:
    """Run the MCP server over stdio without writing non-protocol data to stdout."""

    try:
        config = load_config()
    except ConfigurationError as exc:
        print(f"neuraldefend-mcp: {exc}", file=sys.stderr)
        raise SystemExit(2) from None
    create_server(config).run(transport="stdio")
