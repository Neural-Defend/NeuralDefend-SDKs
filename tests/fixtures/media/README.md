# Live test media fixtures

Permanent binary fixtures for **live and staging smoke tests** across the Python, TypeScript, MCP, and Go SDKs. These files are checked into the repository so local developers and CI can point smoke tests at stable paths.

## Files

| File | Kind | Ground truth | Notes |
| --- | --- | --- | --- |
| `ai-generated.png` | image | AI-generated image | Synthetic face image for `/detect/image` smoke tests |
| `fake-video.mp4` | video | Fake / manipulated video | Short clip for `/detect/video` smoke tests |

Machine-readable metadata lives in [`manifest.json`](manifest.json).

## Usage

### Staging smoke tests (recommended in CI)

Set fixture paths and a staging API key:

```powershell
$env:NEURALDEFEND_STAGING_API_KEY = "your-staging-key"
$env:NEURALDEFEND_STAGING_IMAGE = "tests/fixtures/media/ai-generated.png"
$env:NEURALDEFEND_STAGING_VIDEO = "tests/fixtures/media/fake-video.mp4"
```

Then run the SDK staging smoke suites (for example `pytest -m staging` in `packages/python`).

### Local production API checks (optional)

If you intentionally test against production, set the API key in the environment only:

```powershell
$env:NEURALDEFEND_API_KEY = "your-prod-key"
```

Do **not** commit API keys, `.env` files, or other secrets. The SDK redacts keys in error messages, but scripts and logs must never print credentials.

## Scope

- Use these fixtures for **connectivity and response-shape** smoke tests, not as a frozen benchmark dataset.
- Ground-truth labels describe the source media; they are not a guarantee of any particular API score or risk band on every run.
- Do not add customer media, credentials, or personally identifiable content to this directory.
