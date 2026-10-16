<div align="center">

# NeuralDefend MCP Server

**Let your AI assistant check photos and videos for deepfakes, safely, from folders you choose.**

[![PyPI](https://img.shields.io/pypi/v/neuraldefend-mcp?style=flat-square&logo=pypi&logoColor=white&label=PyPI&color=3775A9)](https://pypi.org/project/neuraldefend-mcp/)
[![Python](https://img.shields.io/badge/python-3.10%2B-3776AB?style=flat-square&logo=python&logoColor=white)](https://www.python.org/)
[![MCP](https://img.shields.io/badge/MCP-stdio%20server-000000?style=flat-square&logo=modelcontextprotocol&logoColor=white)](https://modelcontextprotocol.io/)
[![License: MIT](https://img.shields.io/badge/license-MIT-22863A?style=flat-square)](LICENSE)

[Quick start](#quick-start) · [Examples](#examples) · [Tools](#tool-reference) · [Security](#secure-configuration) · [Troubleshooting](#troubleshooting)

</div>

---

## In plain words

**MCP** (Model Context Protocol) is a standard way to give an AI assistant new abilities.
This package is a small program, called an MCP *server*, that gives assistants such as
**Claude Desktop**, **Claude Code**, **Cursor**, or **VS Code** the ability to send a photo
or video to Neural Defend's **NeuroVerify** service and ask:

> "Does this face look real, or is it likely spoofed or AI-generated?"

You type a normal request like *"Check `D:\Review\selfie.jpg` for deepfakes"*. The
assistant calls the right tool, and the server answers with a risk level. The server can
only read files inside the folders **you** allow, and your API key never appears in the
chat.

| The assistant wants to... | Tool it calls | It gets back |
|---|---|---|
| Check a photo of a face | `detect_image_authenticity` | One risk level for the image |
| Check a video | `detect_video_authenticity` | Separate risk levels for the video and the audio |

Think of the risk level as a traffic light:

| Risk level | Meaning | What to do |
|---|---|---|
| `low` 🟢 | Few signs of manipulation were found | Continue, using your normal process |
| `medium` 🟡 | The result is unclear | Ask for more evidence or a human review |
| `high` 🔴 | Strong signs of spoofing or AI generation | Escalate to a human reviewer |

Sometimes the service cannot score a file, for example when there is no face in the
photo. That is a normal answer called a **rejection**, not a crash. A rejection is never
proof that the media is real. The [examples](#examples) show what each case looks like.

## About this server

`neuraldefend-mcp` 2.0.0 is a secure, local MCP server for NeuroVerify image and video
authenticity analysis. It gives an MCP client two tools while keeping API credentials out
of tool arguments, restricting which local media can be read, and returning a bounded
integration contract instead of the Python SDK's raw response.

Use the results as decision-support signals. A low-risk result is not proof that media is
authentic, and a high-risk result should trigger human review rather than automatic
rejection.

### How it works

The MCP client starts `neuraldefend-mcp` as a child process and communicates with it over
standard input and standard output:

```text
MCP client (Claude Desktop, Claude Code, Cursor, VS Code, ...)
  └─ local stdio (MCP JSON-RPC)
      └─ neuraldefend-mcp
          ├─ validates and opens an allowlisted local file once
          └─ streams that open handle over TLS through the NeuroVerify Python SDK
              └─ NeuroVerify Detection API
```

There is no local HTTP listener. Standard output is reserved for the MCP protocol; safe
startup errors are written to standard error. The server does not return media bytes to the
MCP client and does not load an entire video into memory. It validates the opened file
handle and uploads that same bounded handle, reducing path substitution and
time-of-check/time-of-use risk.

## Requirements

- Python 3.10 or newer.
- A NeuralDefend API key authorized for the requested image or video analysis.
- An MCP client that can launch a local stdio server.
- Network access to the selected NeuroVerify API environment.
- Read access to dedicated local directories containing only media authorized for upload.

This guide documents `neuraldefend-mcp==2.0.0`.

## Installation

Pick one of the three options. All of them provide the same `neuraldefend-mcp` command.

**pip** (inside a virtual environment or your user environment):

```bash
python -m pip install "neuraldefend-mcp==2.0.0"
```

**pipx** (installs the command in its own isolated environment and puts it on `PATH`):

```bash
pipx install "neuraldefend-mcp==2.0.0"
```

**uvx** (no separate install step; [uv](https://docs.astral.sh/uv/) downloads and runs the
package on demand, which suits MCP client configuration):

```bash
uvx "neuraldefend-mcp==2.0.0"
```

When installed with pip, the equivalent module entry point is:

```bash
python -m neuraldefend_mcp
```

Every entry point runs the same stdio-only server. Starting one directly is normally useful
only for diagnosing configuration (see [Example 10](#10-run-the-server-by-hand-for-debugging)):
after a successful startup the process silently waits for MCP messages on standard input.

## Get an API key

NeuroVerify API keys are issued by **Neural Defend** after customer onboarding. There is no
self-service key on PyPI — request access from the company first, then inject the key into
the MCP server environment.

1. Visit **[neuraldefend.com](https://neuraldefend.com/)** and choose **Book a Demo** to
   discuss deepfake detection, AI-generated media analysis, and API access for agents or
   applications.
2. After onboarding, Neural Defend provides an API key scoped to the image and/or video
   endpoints you need. Existing customers can also ask their account manager for a key or
   staging credential.
3. Set `NEURALDEFEND_API_KEY` in the process that launches `neuraldefend-mcp` (see
   [Secure configuration](#secure-configuration)). Never pass the key as an MCP tool
   argument or commit it to configuration files.
4. For REST endpoint reference, see the
   [Neural Defend API documentation](https://neuraldefend.gitbook.io/neural-defend).

**Contact:** [support@neuraldefend.com](mailto:support@neuraldefend.com)

## Quick start

Five steps, about five minutes once you have a key.

1. **Install** the server (any option from [Installation](#installation)):

   ```bash
   pipx install "neuraldefend-mcp==2.0.0"
   ```

2. **Make a review folder** that will hold only media you are allowed to check, for
   example `/Users/alice/NeuroVerify Review` on macOS or `D:\NeuroVerify Review` on
   Windows. The folder must already exist.

3. **Tell your assistant about the server.** Every client needs the same four facts: the
   command (`neuraldefend-mcp`), your API key, the allowed folder, and (optionally) the
   environment. In the common `mcpServers` format:

   ```json
   {
     "mcpServers": {
       "neuraldefend": {
         "command": "neuraldefend-mcp",
         "args": [],
         "env": {
           "NEURALDEFEND_API_KEY": "replace-with-your-api-key",
           "NEURALDEFEND_MCP_ALLOWED_DIRS": "/Users/alice/NeuroVerify Review"
         }
       }
     }
   }
   ```

   Examples [1](#1-connect-claude-desktop), [2](#2-connect-claude-code), and
   [3](#3-connect-cursor-or-vs-code) show where this goes for each client.

4. **Restart the client** so it starts the server with the new settings.

5. **Ask in plain language:**

   > Check /Users/alice/NeuroVerify Review/selfie.jpg for deepfakes.

   The assistant calls `detect_image_authenticity` and replies with the risk level. Each
   analysis may create a billable transaction, so a well-behaved assistant confirms before
   calling the tool.

## Examples

Each example is self-contained. The output blocks are **representative**: your scores,
transaction IDs, messages, signals, and the assistant's exact wording will differ. Tool
outputs are shown as the two parts every tool result contains: the short `content` text
for people and the `structuredContent` object for automations (explained in
[Reading tool results](#reading-tool-results)).

| # | Example | You will learn |
|:-:|---|---|
| 1 | [Connect Claude Desktop](#1-connect-claude-desktop) | Where the config file lives on macOS and Windows |
| 2 | [Connect Claude Code](#2-connect-claude-code) | Adding the server with one terminal command |
| 3 | [Connect Cursor or VS Code](#3-connect-cursor-or-vs-code) | The config shape each editor expects |
| 4 | [Check one photo](#4-check-one-photo) | The simplest request and its result |
| 5 | [Check a video with sound](#5-check-a-video-with-sound) | Reading the separate video and audio results |
| 6 | [Check every image in a folder](#6-check-every-image-in-a-folder) | Batch checks and their cost |
| 7 | [Ask about a file outside the allowed folders](#7-ask-about-a-file-outside-the-allowed-folders) | How the path guard refuses unsafe requests |
| 8 | [Handle a rejection](#8-handle-a-rejection) | Why "no face" is an answer, not an error |
| 9 | [Test against staging](#9-test-against-staging) | Using a staging key without touching production |
| 10 | [Run the server by hand for debugging](#10-run-the-server-by-hand-for-debugging) | Seeing startup errors directly |

### 1. Connect Claude Desktop

Claude Desktop reads MCP servers from a JSON file. Open it from **Settings → Developer →
Edit Config**, or open it directly:

| System | Config file |
|---|---|
| macOS | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Windows | `%APPDATA%\Claude\claude_desktop_config.json` |

macOS:

```json
{
  "mcpServers": {
    "neuraldefend": {
      "command": "neuraldefend-mcp",
      "args": [],
      "env": {
        "NEURALDEFEND_API_KEY": "replace-with-your-api-key",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": "/Users/alice/NeuroVerify Review"
      }
    }
  }
}
```

Windows (backslashes are doubled inside JSON strings, and several folders are separated
with `;`):

```json
{
  "mcpServers": {
    "neuraldefend": {
      "command": "neuraldefend-mcp",
      "args": [],
      "env": {
        "NEURALDEFEND_API_KEY": "replace-with-your-api-key",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": "D:\\NeuroVerify Review;E:\\Review Queue"
      }
    }
  }
}
```

Quit Claude Desktop completely and reopen it. Desktop apps often start with a shorter
`PATH` than your terminal, so if the server does not appear, replace `"neuraldefend-mcp"`
with its absolute path (find it with `which neuraldefend-mcp` on macOS or
`where neuraldefend-mcp` on Windows).

Output (the assistant, after you ask *"Which NeuralDefend tools can you use?"*):

```text
I can use two tools from the "neuraldefend" server:
- detect_image_authenticity: assesses a single-face image for authenticity risk.
- detect_video_authenticity: assesses video and audio as independent authenticity risks.
Both can only read files inside the folders configured for the server.
```

This file stays on your computer, but it holds your key in plain text: do not commit,
sync, or share it.

### 2. Connect Claude Code

Claude Code adds MCP servers with `claude mcp add`. Options come first, then the server
name, then `--` and the command to run. `--scope user` makes the server available in all
your projects.

macOS/Linux:

```bash
claude mcp add --transport stdio --scope user \
  --env NEURALDEFEND_API_KEY="$NEURALDEFEND_API_KEY" \
  --env NEURALDEFEND_MCP_ALLOWED_DIRS="/Users/alice/NeuroVerify Review" \
  neuraldefend -- neuraldefend-mcp
```

PowerShell:

```powershell
claude mcp add --transport stdio --scope user `
  --env "NEURALDEFEND_API_KEY=$env:NEURALDEFEND_API_KEY" `
  --env "NEURALDEFEND_MCP_ALLOWED_DIRS=D:\NeuroVerify Review" `
  neuraldefend -- neuraldefend-mcp
```

Your shell fills in the key from your own environment, so it never appears in your command
history; Claude Code then stores it in its local, per-user configuration. Check the
connection:

```bash
claude mcp list
```

Output:

```text
neuraldefend: neuraldefend-mcp  - ✓ Connected
```

Inside a Claude Code session, `/mcp` shows the same status and the two tools.

### 3. Connect Cursor or VS Code

**Cursor** uses the `mcpServers` shape. Put it in `~/.cursor/mcp.json` (all projects) so
the key stays out of your repositories:

```json
{
  "mcpServers": {
    "neuraldefend": {
      "command": "neuraldefend-mcp",
      "args": [],
      "env": {
        "NEURALDEFEND_API_KEY": "replace-with-your-api-key",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": "/Users/alice/NeuroVerify Review"
      }
    }
  }
}
```

**VS Code** uses a top-level `servers` key in `.vscode/mcp.json` (or the user-level MCP
configuration). Its `inputs` feature asks for the key once and stores it securely, so the
file itself contains no secret and is safe to commit:

```json
{
  "inputs": [
    {
      "type": "promptString",
      "id": "neuraldefend-api-key",
      "description": "NeuralDefend API key",
      "password": true
    }
  ],
  "servers": {
    "neuraldefend": {
      "type": "stdio",
      "command": "neuraldefend-mcp",
      "args": [],
      "env": {
        "NEURALDEFEND_API_KEY": "${input:neuraldefend-api-key}",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": "/Users/alice/NeuroVerify Review"
      }
    }
  }
}
```

Output: after you start the server, both editors list `detect_image_authenticity` and
`detect_video_authenticity` as available tools in agent mode.

### 4. Check one photo

Ask in plain words, and always give the **full (absolute) path**. The server does not
guess which folder you mean.

```text
Check /Users/alice/NeuroVerify Review/selfie.jpg for deepfakes.
```

The assistant calls the tool with one argument:

```json
{ "file_path": "/Users/alice/NeuroVerify Review/selfie.jpg" }
```

Output (tool result):

```text
Image scored: low risk (2.2/10). Not likely to be Spoof or AI-generated Low risk is not definitive proof of authenticity.
```

```json
{
  "schemaVersion": "1.0",
  "mediaType": "image",
  "status": "success",
  "statusCode": 1,
  "scored": true,
  "billable": true,
  "transactionId": "trx_example_image_low",
  "risk": {
    "image": {
      "score": 2.2,
      "level": "low",
      "message": "Not likely to be Spoof or AI-generated"
    }
  },
  "signals": ["Visual Safety Screening", "Liveness Verification"]
}
```

Output (assistant reply):

```text
selfie.jpg came back LOW risk (2.2 out of 10): "Not likely to be Spoof or AI-generated".
Low risk is not proof the photo is genuine, so continue with your normal checks.
Transaction ID: trx_example_image_low.
```

### 5. Check a video with sound

A video gets **two** separate answers: one for the picture and one for the audio. You can
ask for more sampled frames (1 to 100, default 12) for better coverage of long clips.

```text
Check /Users/alice/NeuroVerify Review/interview.mp4. Use 24 frames.
```

Tool arguments:

```json
{ "file_path": "/Users/alice/NeuroVerify Review/interview.mp4", "max_frames": 24 }
```

Output (tool result):

```text
Video scored independently. Video: high risk (8.7/10). Likely to be AI-generated Audio: low risk (2.2/10). Not likely to be AI-generated Escalate for human review; do not auto-reject from this result alone.
```

```json
{
  "schemaVersion": "1.0",
  "mediaType": "video",
  "status": "success",
  "statusCode": 1,
  "scored": true,
  "billable": true,
  "transactionId": "trx_example_video_modalities",
  "risk": {
    "video": {
      "score": 8.7,
      "level": "high",
      "message": "Likely to be AI-generated"
    },
    "audio": {
      "score": 2.2,
      "level": "low",
      "message": "Not likely to be AI-generated"
    }
  },
  "signals": ["Face Swap Detection", "Audio Frequency Analysis", "Frame-Level Visual Analysis"]
}
```

The face looks manipulated but the voice does not. The low audio result does **not**
cancel out the high video result: there is no combined score, and each modality is judged
on its own. A silent clip is still scored; its audio `score` and `level` are `null` with
the message `No audio track detected`.

### 6. Check every image in a folder

The server has no "list folder" tool; it only analyzes the files it is given. An assistant
that can see your files (Claude Code, Cursor, or VS Code agent mode) can list the folder
itself and then call `detect_image_authenticity` once per file. In Claude Desktop, name
the files in your request.

```text
List the images in /Users/alice/NeuroVerify Review/batch-07, tell me how many
analyses that will be, and after I confirm, check each one and summarize the results
in a table.
```

Output (assistant reply):

```text
There are 4 images, so this is 4 separate analyses, and each may be billable. Proceed?

> yes

| File              | Result   | Level  | Message                                 |
|-------------------|----------|--------|-----------------------------------------|
| anna.jpg          | scored   | low    | Not likely to be Spoof or AI-generated  |
| group_photo.jpg   | rejected | —      | Multiple faces detected in the image    |
| id_card_scan.png  | scored   | medium | Less likely to be Spoof or AI-generated |
| printed_photo.jpg | scored   | high   | Likely to be Spoof detected             |

Summary: 1 low, 1 medium, 1 high, 1 rejected. printed_photo.jpg should go to a human
reviewer; group_photo.jpg needs a new photo with one face.
```

At most `NEURALDEFEND_MCP_MAX_CONCURRENCY` analyses (default `2`) run at the same time;
extra calls wait their turn. Check your account rate limits before large batches.

### 7. Ask about a file outside the allowed folders

The server checks every path **before** anything is uploaded. Here the allowed folder is
`/Users/alice/NeuroVerify Review`, but the request points at the Downloads folder:

```text
Check /Users/alice/Downloads/passport.jpg for deepfakes.
```

Output (tool result, marked `isError: true`):

```text
The media file is outside allowed directories.
```

```json
{
  "schemaVersion": "1.0",
  "mediaType": "image",
  "status": "error",
  "statusCode": null,
  "scored": false,
  "billable": false,
  "transactionId": null,
  "risk": {
    "image": null
  },
  "signals": [],
  "error": {
    "code": "local_validation",
    "message": "The media file is outside allowed directories.",
    "retryable": false
  }
}
```

Output (assistant reply):

```text
I can't check that file: it is outside the folders this server is allowed to read.
Nothing was uploaded and nothing was billed. If you are authorized to check it, move it
into /Users/alice/NeuroVerify Review and ask again.
```

The same guard refuses relative paths (`The media path must be absolute.`), missing files
(`The media file does not exist.`), empty files, oversized files, and paths that go
through symlinks or junctions. The error never echoes the path back.

### 8. Handle a rejection

When the service receives a file but cannot score it, the result has
`status: "rejected"`. This is a normal answer, **not** an MCP error (`isError` is
`false`), and it can still be billable.

```text
Check /Users/alice/NeuroVerify Review/landscape.jpg.
```

Output (tool result):

```text
Could not score image: No face detected in the image An unscorable result is not evidence that the media is authentic.
```

```json
{
  "schemaVersion": "1.0",
  "mediaType": "image",
  "status": "rejected",
  "statusCode": 6,
  "scored": false,
  "billable": true,
  "transactionId": "trx_example_image_no_face",
  "risk": {
    "image": {
      "score": null,
      "level": null,
      "message": "No face detected in the image"
    }
  },
  "signals": []
}
```

Output (assistant reply):

```text
NeuroVerify could not score landscape.jpg because no face was detected. That does not
mean the image is genuine. Please provide a clear, front-facing photo of exactly one
person. (This rejection was billable; transaction trx_example_image_no_face.)
```

Do not retry the same file: the answer will not change, and each attempt is a new
transaction. Fix the media instead.

### 9. Test against staging

Neural Defend can issue a separate **staging** key during onboarding for integration
tests. Set `NEURALDEFEND_MCP_ENVIRONMENT` to `staging`, and use a separate folder of
approved test media:

```json
{
  "mcpServers": {
    "neuraldefend-staging": {
      "command": "neuraldefend-mcp",
      "args": [],
      "env": {
        "NEURALDEFEND_API_KEY": "replace-with-your-staging-api-key",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": "/Users/alice/NeuroVerify Test Media",
        "NEURALDEFEND_MCP_ENVIRONMENT": "staging",
        "NEURALDEFEND_MCP_MAX_CONCURRENCY": "1"
      }
    }
  }
}
```

Output (tool result for a test image):

```text
Image scored: low risk (2.2/10). Not likely to be Spoof or AI-generated Low risk is not definitive proof of authenticity.
```

Only `production` and `staging` are accepted. The server cannot be pointed at any other
URL, so a staging setup can never leak a key or media to an unknown host.

### 10. Run the server by hand for debugging

The server has no command-line flags; every setting comes from the environment variables
in [Secure configuration](#secure-configuration). Running it directly in a terminal is the
fastest way to see a startup problem that your MCP client may hide.

macOS/Linux:

```bash
export NEURALDEFEND_API_KEY="replace-with-your-api-key"
export NEURALDEFEND_MCP_ALLOWED_DIRS="/Users/alice/NeuroVerify Review"
neuraldefend-mcp
```

PowerShell:

```powershell
$env:NEURALDEFEND_API_KEY = "replace-with-your-api-key"
$env:NEURALDEFEND_MCP_ALLOWED_DIRS = "D:\NeuroVerify Review"
neuraldefend-mcp
```

Output when the configuration is valid: nothing. The server is waiting for MCP messages
on standard input. Press `Ctrl+C` to stop it.

Output when something is wrong (written to standard error; exit code `2`):

```text
neuraldefend-mcp: NEURALDEFEND_MCP_ALLOWED_DIRS is required.
```

```text
neuraldefend-mcp: Every allowed directory must exist.
```

To call the tools interactively without an AI assistant, the open-source
[MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector) can launch the
server for you:

```bash
npx @modelcontextprotocol/inspector \
  -e NEURALDEFEND_API_KEY="$NEURALDEFEND_API_KEY" \
  -e NEURALDEFEND_MCP_ALLOWED_DIRS="/Users/alice/NeuroVerify Review" \
  neuraldefend-mcp
```

## Secure configuration

Configuration is read from the server process environment at startup. The server refuses
to start if a required value is missing or unsafe. There are no command-line options.

| Variable | Required | Default | Accepted value | Why it is restricted |
|---|---:|---|---|---|
| `NEURALDEFEND_API_KEY` | Yes | — | Non-empty API key | Credentials never become tool arguments and are not exposed in results. |
| `NEURALDEFEND_MCP_ALLOWED_DIRS` | Yes | — | One or more existing absolute directories, separated by the platform path separator | Limits the local files an MCP client or agent can cause the server to read and upload. |
| `NEURALDEFEND_MCP_ENVIRONMENT` | No | `production` | `production` or `staging` | Pins credentials and media to a known NeuralDefend TLS origin; arbitrary URLs are rejected. |
| `NEURALDEFEND_MCP_MAX_CONCURRENCY` | No | `2` | Integer from `1` through `32` | Bounds simultaneous SDK calls, local file handles, network load, and accidental billing bursts. |

### API key

`NEURALDEFEND_API_KEY` is stripped of surrounding whitespace and passed to the Python SDK
when the server starts. It is never accepted as an MCP tool argument. Inject it through the
MCP client's secret store, an operating-system credential facility, or the environment of
the process that launches the MCP client.

Do not put a real key in:

- a committed MCP configuration;
- a prompt or tool argument;
- a shell-history example;
- application logs or issue reports.

Startup validates only that the key is a non-empty string; the NeuroVerify API then
validates the credential and its endpoint scope on each request.

### Allowed directories

`NEURALDEFEND_MCP_ALLOWED_DIRS` is mandatory. Use the platform path separator between
entries:

- Windows (`;`):

  ```text
  D:\Authorized Media;E:\Review Queue
  ```

- macOS (`:`):

  ```text
  /Users/alice/Authorized Media:/Volumes/ReviewQueue
  ```

- Linux (`:`):

  ```text
  /srv/authorized-media:/home/alice/review-queue
  ```

Configure the narrowest dedicated directories practical. Do not allow a home directory,
shared download directory, repository root, or other broad location merely for
convenience.

At startup, every allowlist entry must:

- be a non-empty absolute path;
- already exist and be a directory, not a file;
- not be a filesystem root such as `C:\` or `/`;
- contain no symlink, Windows junction, or other reparse-point component.

Duplicate roots are removed. Relative paths, empty entries, unsafe Windows device paths,
and alternate data stream forms are rejected.

For every tool invocation, `file_path` must:

- be an absolute path to an existing regular file below an allowed directory;
- contain no symlink, junction, or reparse-point component;
- identify a non-empty file within the media size limit;
- still resolve inside an allowed directory after the file has been opened.

These checks prevent path traversal, prefix-sibling mistakes, link escapes, device access,
alternate data stream access, and file-swap races. The server exposes only the validated
prefix if another process appends data after validation.

### API environment

Omit `NEURALDEFEND_MCP_ENVIRONMENT` for production. Set it to `staging` only for
non-production integration testing with staging credentials and approved test media.
Values are case-insensitive after trimming, but only `production` and `staging` are
accepted.

The MCP adapter deliberately ignores the Python SDK's general
`NEURALDEFEND_BASE_URL` override. This prevents an inherited environment variable from
redirecting the API key and uploaded media to an arbitrary origin.

### Maximum concurrency

`NEURALDEFEND_MCP_MAX_CONCURRENCY` limits active analyses across both tools. It must be a
base-10 integer from `1` through `32`; booleans, decimals, zero, negatives, and larger values are
rejected. Start with the default `2`. Raise it only after considering account rate limits,
host resources, expected media sizes, latency, and billing controls.

## Other MCP clients

The outer configuration key varies by client, but clients that use the common
`mcpServers` shape can use the entries below. Use a secret reference such as
`${NEURALDEFEND_API_KEY}` only if your client documents that it expands that syntax.
Otherwise, omit the key from the `env` object and launch the client from a securely
populated environment, or use the client's secret-store reference. Never put a real key in
a file that may be committed, synchronized, backed up without encryption, or shared.

Installed command on `PATH`:

```json
{
  "mcpServers": {
    "neuraldefend": {
      "command": "neuraldefend-mcp",
      "args": [],
      "env": {
        "NEURALDEFEND_API_KEY": "${NEURALDEFEND_API_KEY}",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": "/srv/authorized-media:/home/alice/review-queue",
        "NEURALDEFEND_MCP_ENVIRONMENT": "production",
        "NEURALDEFEND_MCP_MAX_CONCURRENCY": "2"
      }
    }
  }
}
```

Run through `uvx` without a separate install:

```json
{
  "mcpServers": {
    "neuraldefend": {
      "command": "uvx",
      "args": ["neuraldefend-mcp==2.0.0"],
      "env": {
        "NEURALDEFEND_API_KEY": "${NEURALDEFEND_API_KEY}",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": "/srv/authorized-media"
      }
    }
  }
}
```

If the console command is not on the client's `PATH`, use the interpreter from the
environment where the package was installed:

```json
{
  "mcpServers": {
    "neuraldefend": {
      "command": "/absolute/path/to/python",
      "args": ["-m", "neuraldefend_mcp"],
      "env": {
        "NEURALDEFEND_API_KEY": "${NEURALDEFEND_API_KEY}",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": "/absolute/path/to/authorized-media"
      }
    }
  }
}
```

On Windows, `command` may instead be an absolute path such as
`C:\\path\\to\\venv\\Scripts\\python.exe`, and allowed directories must use Windows
absolute paths separated by `;`.

Restart the MCP server after changing its environment or allowlist. Configuration is
loaded once for the process lifespan.

## Authorization and billing gate

Before invoking either tool, the client or agent should:

1. Confirm that the data owner has authorized this media to be uploaded and analyzed.
2. Confirm that the file is in a purpose-specific allowed directory.
3. Tell the user that the call may create a billable transaction.
4. Confirm the requested tool and, for video, the requested frame count.
5. Avoid invoking the same analysis again merely to obtain a different score or message.

A local validation failure happens before upload and is reported as non-billable.
Service-side business rejections are normal results and can be billable. In particular,
no-face and face-policy rejections can return `billable: true`. For failures where it is
not safe to know whether the service accepted the request, `billable` is `null`.

## Tool reference

The server registers itself as **NeuralDefend Media Authenticity** and exposes exactly two
tools.

### `detect_image_authenticity(file_path)`

Assesses an authorized image containing exactly one clearly visible face.

| Argument | Type | Required | Constraints |
|---|---|---:|---|
| `file_path` | string | Yes | Absolute path to an allowlisted, regular, non-empty image file. |

Supported extensions are `.jpg`, `.jpeg`, `.png`, `.bmp`, `.tif`, `.tiff`, `.webp`,
`.heic`, and `.heif`. The maximum size is 10 MiB (10,485,760 bytes), the minimum
resolution is 224 × 224 pixels, and exactly one face is required. EXIF rotation is handled
by the service. Use a clear, frontal, well-lit image for the most useful result.

The server performs path, regular-file, non-empty, and size validation locally. Media
format, dimensions, quality, safety, and face-policy checks can produce a service business
rejection.

### `detect_video_authenticity(file_path, max_frames=12)`

Assesses authorized video and audio as independent modalities. The API deliberately
provides no combined MCP risk field.

| Argument | Type | Required | Default | Constraints |
|---|---|---:|---:|---|
| `file_path` | string | Yes | — | Absolute path to an allowlisted, regular, non-empty video file. |
| `max_frames` | integer | No | `12` | Integer from `1` through `100`; booleans are not accepted. |

Supported extensions are `.mp4`, `.avi`, `.mov`, `.mkv`, `.wmv`, `.flv`, `.webm`,
`.ogg`, and `.ogv`. The maximum size is 1,500,000,000 bytes. Frames are sampled uniformly.
Frames with several faces are skipped; if no sampled frame has one scorable face, the
result is a billable business rejection. A silent video can still be a successful result:
the video modality is scored while the audio score and level are `null` and the audio
message is `No audio track detected`.

Increasing `max_frames` can improve temporal coverage but also increases processing work
and latency. It does not make repeated invocations idempotent.

## Reading tool results

Every MCP call result has two synchronized channels derived from the same internal
outcome:

- `content[0].text` is concise presentation text for a person or conversational agent. Its
  wording may evolve and must not be parsed as an API.
- `structuredContent` is the versioned integration contract. Automations should branch on
  its fields.

`isError` is `true` only when `structuredContent.status` is `error`. A service business
rejection uses `status: "rejected"` and `isError: false` because it is a valid, unscorable
business result.

The examples below are representative `structuredContent` values.

### Image success: low risk

```json
{
  "schemaVersion": "1.0",
  "mediaType": "image",
  "status": "success",
  "statusCode": 1,
  "scored": true,
  "billable": true,
  "transactionId": "trx_example_image_low",
  "risk": {
    "image": {
      "score": 2.2,
      "level": "low",
      "message": "Not likely to be Spoof or AI-generated"
    }
  },
  "signals": [
    "Visual Safety Screening",
    "Liveness Verification",
    "Face Swap Detection",
    "AI Generative Model Analysis",
    "AI Content Compliance"
  ]
}
```

Low risk is not definitive proof of authenticity.

### Image success: medium risk

```json
{
  "schemaVersion": "1.0",
  "mediaType": "image",
  "status": "success",
  "statusCode": 1,
  "scored": true,
  "billable": true,
  "transactionId": "trx_example_image_medium",
  "risk": {
    "image": {
      "score": 5.5,
      "level": "medium",
      "message": "Less likely to be Spoof or AI-generated"
    }
  },
  "signals": [
    "Visual Safety Screening",
    "Liveness Verification",
    "Face Swap Detection",
    "AI Generative Model Analysis",
    "AI Content Compliance"
  ]
}
```

Medium risk should be reviewed with additional evidence.

### Image success: high risk

```json
{
  "schemaVersion": "1.0",
  "mediaType": "image",
  "status": "success",
  "statusCode": 1,
  "scored": true,
  "billable": true,
  "transactionId": "trx_example_image_high",
  "risk": {
    "image": {
      "score": 8.7,
      "level": "high",
      "message": "Likely to be Spoof detected"
    }
  },
  "signals": [
    "Visual Safety Screening",
    "Liveness Verification",
    "Face Swap Detection",
    "AI Generative Model Analysis",
    "AI Content Compliance"
  ]
}
```

High risk should be escalated for human review and must not be used as an automatic
rejection by itself.

### Image business rejection

This is a valid, potentially billable result, not an MCP error:

```json
{
  "schemaVersion": "1.0",
  "mediaType": "image",
  "status": "rejected",
  "statusCode": 6,
  "scored": false,
  "billable": true,
  "transactionId": "trx_example_image_no_face",
  "risk": {
    "image": {
      "score": null,
      "level": null,
      "message": "No face detected in the image"
    }
  },
  "signals": []
}
```

“Could not score” means unscorable. It is not evidence that the image is authentic.

### Video success: both modalities scored

```json
{
  "schemaVersion": "1.0",
  "mediaType": "video",
  "status": "success",
  "statusCode": 1,
  "scored": true,
  "billable": true,
  "transactionId": "trx_example_video_high",
  "risk": {
    "video": {
      "score": 9.0,
      "level": "high",
      "message": "Likely to be AI-generated"
    },
    "audio": {
      "score": 2.2,
      "level": "low",
      "message": "Not likely to be AI-generated"
    }
  },
  "signals": [
    "Photometric Liveness Signal",
    "Identity Consistency Analysis",
    "Face Swap Detection",
    "AI Generative Model Analysis",
    "Audio Frequency Analysis",
    "AI Pixel-Level Manipulation",
    "Digital Content Provenance",
    "Frame-Level Visual Analysis"
  ]
}
```

Keep the video and audio decisions separate. In this example the low-risk audio result
does not offset the high-risk video result.

### Video success: no audio track

```json
{
  "schemaVersion": "1.0",
  "mediaType": "video",
  "status": "success",
  "statusCode": 1,
  "scored": true,
  "billable": true,
  "transactionId": "trx_example_video_silent",
  "risk": {
    "video": {
      "score": 2.1,
      "level": "low",
      "message": "Not likely to be AI-generated"
    },
    "audio": {
      "score": null,
      "level": null,
      "message": "No audio track detected"
    }
  },
  "signals": [
    "Photometric Liveness Signal",
    "Identity Consistency Analysis",
    "Face Swap Detection",
    "AI Generative Model Analysis",
    "Audio Frequency Analysis",
    "AI Pixel-Level Manipulation",
    "Digital Content Provenance",
    "Frame-Level Visual Analysis"
  ]
}
```

The call is successful because the video modality was scored. Null audio fields do not
mean low audio risk.

### Video business rejection: no scorable face

```json
{
  "schemaVersion": "1.0",
  "mediaType": "video",
  "status": "rejected",
  "statusCode": 6,
  "scored": false,
  "billable": true,
  "transactionId": "trx_example_video_no_face",
  "risk": {
    "video": {
      "score": null,
      "level": null,
      "message": "No face detected in the video. The video could not be scored, so no risk scores are provided, including for audio."
    },
    "audio": {
      "score": null,
      "level": null,
      "message": null
    }
  },
  "signals": []
}
```

Audio is not scored when the sampled frames do not provide a scorable single face.

### Error object

Errors add an `error` object and set MCP `isError` to `true`. For example, a final
rate-limit failure is:

```json
{
  "schemaVersion": "1.0",
  "mediaType": "image",
  "status": "error",
  "statusCode": 429,
  "scored": false,
  "billable": false,
  "transactionId": null,
  "risk": {
    "image": null
  },
  "signals": [],
  "error": {
    "code": "rate_limit",
    "message": "The service rate limit was reached. Try again later.",
    "retryable": true
  }
}
```

## `structuredContent` contract

`schemaVersion` is currently `"1.0"`. Consumers should require a supported major schema
version and ignore additive fields they do not understand. Do not parse the presentation
text to reconstruct these fields.

| Field | Type | Meaning |
|---|---|---|
| `schemaVersion` | string | Version of this bounded MCP projection, not the upstream wire schema. |
| `mediaType` | `"image"` or `"video"` | Tool result media kind. |
| `status` | `"success"`, `"rejected"`, or `"error"` | Primary branch for result handling. |
| `statusCode` | integer or `null` | Sanitized service/business status when available; not sufficient by itself to determine whether media was scored. |
| `scored` | boolean | `true` only for a contract-valid successful score. |
| `billable` | boolean or `null` | Authoritative boolean when known; `null` means billing could not be determined safely. |
| `transactionId` | string or `null` | Safe service transaction identifier for audit correlation. |
| `risk` | object | `{ "image": ... }` for images; `{ "video": ..., "audio": ... }` for videos. |
| `risk.*.score` | number or `null` | Opaque score from 0.1 through 10.0. Do not create local thresholds. |
| `risk.*.level` | `"low"`, `"medium"`, `"high"`, or `null` | Service risk band to use for business decision rules. |
| `risk.*.message` | string or `null` | Sanitized service explanation or modality status. |
| `signals` | array of strings | Sanitized informational checks/signals; do not depend on a fixed list. |
| `error` | object, errors only | Sanitized `code`, `message`, and `retryable` fields. |

The output is intentionally bounded:

- only explicitly allowlisted fields are emitted;
- messages are limited to 500 characters;
- at most 32 signals are emitted, each limited to 120 characters;
- scores outside 0.1–10.0, unknown success risk levels, and inconsistent success shapes
  become a `protocol` error;
- transaction identifiers must match a conservative character and length allowlist.

Local paths, filenames, media bytes, response headers, API keys, SDK exception details,
future unknown response fields, and the SDK `raw` payload are never included. Known
sensitive values and absolute-path patterns are redacted from returned messages and
signals.

## Error codes and retryability

| `error.code` | Typical cause | `statusCode` | `billable` | `retryable` |
|---|---|---:|---:|---:|
| `local_validation` | Unsafe path, missing/empty/oversized file, invalid `max_frames`, or Python SDK input validation | `null` | `false` | `false` |
| `authentication` | Invalid or missing service credential | `401` | `false` | `false` |
| `scope` | API key lacks permission for the requested analysis | `403` | `false` | `false` |
| `rate_limit` | Final service rate-limit response | `429` | `false` | `true` |
| `server` | Final service failure | Usually `500` or `503` | `false` | `true` |
| `transport` | Timeout, network, or unclassified transport failure | Usually `null` | `null` | `false` |
| `protocol` | Unsupported or malformed service/SDK result | Usually `null` | `null` | `false` |

`retryable` is deliberately conservative. Only final rate-limit and server errors are
marked `true`. A timeout or transport failure is not marked retryable because the request
may already have been accepted and billing may be ambiguous.

The Python SDK owns network retry behavior; this MCP layer adds no retries. By default the
SDK retries only HTTP 429, 500, and 503, up to three retries after the initial attempt.
Receiving an MCP error therefore means the SDK's policy has already completed. Any later
manual retry is a new, non-idempotent invocation and should pass through the authorization
and billing gate again.

## Decision guidance

Branch on `status`, not `statusCode` alone:

1. `error`: no score is available. Inspect `error.code`, `retryable`, and `billable`.
2. `rejected`: the service processed the request but could not score it. Do not interpret
   null risk fields as low risk, and do not retry unchanged media automatically.
3. `success`: use the service-provided `level` for policy. Treat the numeric score as
   opaque because band thresholds can change.

For successful risk levels:

- `low`: not definitive proof of authenticity;
- `medium`: review with additional evidence;
- `high`: escalate for human review; do not auto-reject from this result alone.

For video, assess `risk.video` and `risk.audio` independently. The MCP contract has no
overall risk field. If one modality is unscored, do not silently treat it as low risk.

## Billing, transactions, and idempotency

Every accepted API attempt receives a new transaction identifier. Requests are not
idempotent: analyzing the same file again creates a separate transaction and may be
billable again. The Python SDK may also make multiple HTTP attempts under its narrow retry
policy, with separate transaction and billing implications.

- Use `billable` from the result; do not infer billing from MCP `isError`, HTTP status, or
  whether a score exists.
- Preserve `transactionId` under your organization's audit and access-control policy when
  correlation or dispute resolution is required.
- Do not loop until a preferred risk result appears.
- Do not automatically repeat a business rejection.
- Treat `billable: null` as unknown, not false.

## Privacy and data handling

Uploaded media can contain biometric and other sensitive personal data. Before enabling
the server:

- establish authorization and an appropriate legal basis for every upload;
- limit the allowlist to purpose-specific directories with controlled write access;
- apply organizational retention, deletion, residency, access-control, and incident
  response requirements;
- avoid placing sensitive media, local paths, or API keys in prompts, logs, screenshots,
  tickets, or telemetry;
- remove media from the review directory according to your retention policy.

The bounded MCP result reduces accidental leakage but does not replace governance for the
media uploaded to the service or for transaction and risk data retained by the MCP client.

Report suspected vulnerabilities privately to `support@neuraldefend.com`; do not include
real credentials or customer media in the report.

## Troubleshooting

### Server does not start

Startup errors are printed to standard error as `neuraldefend-mcp: <message>` and the
process exits with code `2`. Run the server by hand ([Example 10](#10-run-the-server-by-hand-for-debugging))
to see them directly.

- `NEURALDEFEND_API_KEY is required.`: inject a non-empty key into the server process.
- `NEURALDEFEND_MCP_ALLOWED_DIRS is required.`: configure at least one existing absolute
  directory.
- `contains an empty entry`: remove a leading, trailing, or doubled path separator.
- `Every allowed directory must exist.` / `must be an absolute path.`: create the folder
  first and use its full path.
- `Filesystem roots cannot be allowed directories.`: choose a dedicated subfolder instead
  of `C:\` or `/`.
- `must be between 1 and 32` or `must be a positive integer`: correct
  `NEURALDEFEND_MCP_MAX_CONCURRENCY`.
- `must be either 'production' or 'staging'`: remove a custom URL or unsupported
  environment name.
- The client reports that the process exited but shows no protocol output: inspect the MCP
  client's captured standard error. Startup errors intentionally never use standard
  output.
- `neuraldefend-mcp` is not found: use the command's absolute path, use `uvx`, or use the
  absolute Python interpreter path with `-m neuraldefend_mcp`.

### Path is rejected

- `The media path must be absolute.`: pass a full path. The MCP client's working directory
  is not used to resolve relative paths.
- `The media file is outside allowed directories.`: confirm the file is below an allowed
  directory, not merely in a path with the same text prefix.
- `The media file does not exist.`, `The media file is empty.`, or
  `The media file exceeds the allowed size.`: confirm the file exists, is regular,
  non-empty, and within the applicable size limit.
- `The media path cannot contain symlinks, junctions, or reparse points.`: remove linked
  components. Both allowed roots and invocation paths are checked component by component.
- On Windows, do not use device namespaces, reserved device names, or alternate data
  streams.
- `The media file changed while it was opened.`: another process replaced or moved the
  file. Retry only after stabilizing the file; the server rejects changed handles rather
  than uploading uncertain content.
- Restart the server after changing `NEURALDEFEND_MCP_ALLOWED_DIRS`.

Path failures return `local_validation` without echoing the sensitive path.

### Media is rejected

A `status: "rejected"` result is not a startup or transport problem. Read the modality
message, correct the media, and obtain authorization before a new invocation. Common
causes include no face, several faces, unsupported format, dimensions or quality outside
accepted limits, safety screening, and excessive file size. A no-face or face-policy
rejection may still be billable.

For video, multi-face frames are skipped. If no sampled frame contains one scorable face,
both modalities remain unscored and the business result is rejected.

### API error

- `authentication` / 401: replace or correctly inject the API key, then restart the MCP
  server.
- `scope` / 403: request the required image or video analysis permission for the key.
- `rate_limit` / 429: respect account limits and delay before a separately authorized new
  invocation.
- `server` / 500 or 503: the SDK has already applied its retry policy. Retry later only
  after considering non-idempotency and billing.
- `transport`: check DNS, TLS, proxy, firewall, and service reachability. Do not assume the
  failed call was non-billable.
- `protocol`: update compatible `neuraldefend-mcp` and `neuraldefend` packages together or
  contact support; do not use partial fields from an unsupported result.

## Related documentation

- [NeuralDefend Python SDK](../python/README.md)
- [Wire-level image client documentation](../../docs/client/unified-face-authenticity.md)
- [Wire-level video client documentation](../../docs/client/unified-video-authenticity.md)

The wire-level documents describe the complete service response scenarios. Integrations
using this MCP server should depend on the bounded `structuredContent` contract documented
here, not on upstream-only fields.

## Support

Technical support: `support@neuraldefend.com`

When requesting help, provide the `neuraldefend-mcp` version, the MCP client you use, the
`error.code` or `transactionId`, and a sanitized description of the problem. Do not send
API keys, raw customer media, or biometric/personal data.

## Development

For repository maintainers:

```bash
python -m pip install -e ".[dev]"
pytest
ruff check .
mypy
python -m build
twine check dist/*
```
