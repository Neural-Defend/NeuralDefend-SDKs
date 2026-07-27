---
name: media-authenticity
description: Verifies whether an image, face photo, video, or audio track may be AI-generated, deepfaked, face-swapped, spoofed, or manipulated. Use when a user asks to authenticate media, investigate suspected synthetic media, assess liveness or impersonation risk, or interpret a NeuralDefend authenticity result.
---

# Media Authenticity

## API key (required before any call)

NeuroVerify requires a Neural Defend API key. Keys are **not** on PyPI, npm, or MCP tool
arguments — the user must obtain one from the company website first.

1. Tell the user to visit **[neuraldefend.com](https://neuraldefend.com/)** and choose
   **Book a Demo** (or email [support@neuraldefend.com](mailto:support@neuraldefend.com)).
2. After Neural Defend onboarding, the user stores the key in `NEURALDEFEND_API_KEY` for the
   Python/TypeScript SDK, or in the environment of the process that launches
   `neuraldefend-mcp`.
3. **Never** ask the user to paste an API key into chat, a tool argument, a prompt, or a
   committed config file. If MCP is configured, assume the key is already injected
   server-side.
4. If no key is configured, stop and explain the onboarding steps above before uploading
   media.

## Authorization gate

Before uploading any media, explain that it will be sent to NeuralDefend for analysis and
may contain biometric or other sensitive personal data. Obtain explicit user authorization
for the specific file. Explain that the call can create a billable transaction, including
some unscorable face-policy rejections. Do not infer consent from the request or from
filesystem access. Stop if authorization is absent or ambiguous.

## Analyze

1. Prefer the NeuralDefend MCP tools:
   - Image: `detect_image_authenticity(file_path)`
   - Video: `detect_video_authenticity(file_path, max_frames=12)`
   Standalone audio files are not supported in v1; audio is analyzed only when it is part
   of an uploaded video.
2. Pass only the authorized absolute path. Never request or pass an API key as a tool
   argument.
3. If MCP is unavailable, use the installed `neuraldefend` Python SDK with
   `NeuroVerifyClient`, reading `NEURALDEFEND_API_KEY` from the environment (obtain the key
   from [neuraldefend.com](https://neuraldefend.com/) after onboarding). Open the authorized
   file in binary mode and call `detect_image` or `detect_video`; do not read the whole file
   into memory. Let the SDK own retries.
4. Never retry a rejected result automatically. Ask for a different authorized input only
   when the user wants to continue.

## Interpret

- Branch on `status` or `scored`, never HTTP success alone.
- `rejected` means unscorable input, not authentic media.
- Treat `high` as a reason to escalate for human review, not automatic rejection.
- Treat `medium` as inconclusive and review with additional evidence.
- Treat `low` as non-definitive; it is not proof of authenticity.
- For video, report video and audio independently. Do not invent a combined risk level.
- A silent video can be successfully scored with no audio score; preserve that distinction.
- Include the transaction ID for audit correlation, but never expose local paths, local
  filenames, API keys, media bytes, raw payloads, or headers.

## Installation

This repository's `skills/` directory is a distribution artifact and is not automatically
discovered by an agent. Copy this entire `media-authenticity` directory to either:

- `.cursor/skills/media-authenticity/` in a project, or
- `~/.cursor/skills/media-authenticity/` for the current user.

Install and configure `neuraldefend-mcp` separately when MCP tools are desired. Request an
API key from [neuraldefend.com](https://neuraldefend.com/) and set `NEURALDEFEND_API_KEY`
in the MCP server environment. Its required `NEURALDEFEND_MCP_ALLOWED_DIRS` allowlist must
contain only explicitly authorized media directories.
