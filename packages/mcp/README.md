# neuraldefend-mcp

Secure, stdio-only MCP tools for image and video authenticity analysis through the
NeuroVerify Python SDK.

## Install

```bash
python -m pip install neuraldefend-mcp
```

The package provides both `neuraldefend-mcp` and `python -m neuraldefend_mcp`.

## Required security configuration

Set both variables in the MCP server process:

- `NEURALDEFEND_API_KEY`: the NeuralDefend API key. It is read only from the environment
  and is never a tool argument.
- `NEURALDEFEND_MCP_ALLOWED_DIRS`: one or more absolute directories that the server may
  read. Separate directories with the platform path separator: `;` on Windows and `:` on
  macOS/Linux.

The server refuses to start when the allowlist is missing or invalid. Filesystem roots,
file paths, relative paths, empty entries, and roots containing symlinks, junctions, or
reparse points are rejected. At tool invocation time, the requested file must be a regular,
non-empty file below an allowed directory and must not traverse any link or reparse point.

Optional: `NEURALDEFEND_MCP_MAX_CONCURRENCY` is a positive integer from 1 through 32 and
defaults to `2`.

Optional: `NEURALDEFEND_MCP_ENVIRONMENT` selects the API origin. It accepts only
`production` (the default) or `staging`; arbitrary URLs are rejected. Use `staging` for
non-production integration tests.

Only configure directories containing media that users have explicitly authorized for
upload. Media may contain biometric and other sensitive personal data.

## MCP client configuration

Windows example:

```json
{
  "mcpServers": {
    "neuraldefend": {
      "command": "neuraldefend-mcp",
      "env": {
        "NEURALDEFEND_API_KEY": "${NEURALDEFEND_API_KEY}",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": "D:\\Authorized Media;E:\\Review Queue"
      }
    }
  }
}
```

macOS/Linux example:

```json
{
  "mcpServers": {
    "neuraldefend": {
      "command": "neuraldefend-mcp",
      "env": {
        "NEURALDEFEND_API_KEY": "${NEURALDEFEND_API_KEY}",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": "/srv/authorized-media:/home/user/review-queue"
      }
    }
  }
}
```

If the MCP client does not expand `${NEURALDEFEND_API_KEY}`, use its supported secret
injection mechanism. Do not place a real key in a committed configuration file.

## Tools

- `detect_image_authenticity(file_path)` analyzes an image containing one clearly visible
  face.
- `detect_video_authenticity(file_path, max_frames=12)` analyzes video and audio
  independently. `max_frames` must be from 1 through 100.

Business rejections are normal tool results. “Could not score” means the media was
unscorable, not that it was authentic, and a rejected invocation should not be retried
automatically. A high risk result should be escalated for review rather than used as an
automatic rejection. Low risk is not definitive proof of authenticity.

Each tool call can create a new, billable transaction, including some face-policy
rejections. Agents should disclose that possibility before invoking a tool and should
never repeat a call merely to obtain a different score or message.

The Python SDK owns network retry behavior; this MCP layer adds no retries. It opens each
local file once, validates the open handle, and streams that same handle to the SDK without
loading a video into memory. Tool output contains a bounded, versioned field allowlist and
never includes local paths, filenames, media bytes, response headers, or the SDK raw
payload.

## Development

```bash
python -m pip install -e ".[dev]"
pytest
ruff check .
mypy
python -m build
twine check dist/*
```
