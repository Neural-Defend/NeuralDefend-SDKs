# NeuralDefend SDKs

[![Python SDK on PyPI](https://img.shields.io/pypi/v/neuraldefend?label=Python%20SDK%20on%20PyPI)](https://pypi.org/project/neuraldefend/)
[![TypeScript SDK on npm](https://img.shields.io/npm/v/%40neuraldefend%2Fsdk?label=TypeScript%20SDK%20on%20npm)](https://www.npmjs.com/package/@neuraldefend/sdk)
[![MCP server on PyPI](https://img.shields.io/pypi/v/neuraldefend-mcp?label=MCP%20server%20on%20PyPI)](https://pypi.org/project/neuraldefend-mcp/)
[![Go SDK module](https://img.shields.io/github/v/tag/Neural-Defend/NeuralDefend-SDKs/packages/go/v1.0.0?label=Go%20SDK)](https://github.com/Neural-Defend/NeuralDefend-SDKs/tags)

Official clients for the **NeuroVerify Detection API**, which evaluates images and videos
for signs of AI generation, manipulation, spoofing, and related authenticity risks.

## Choose an integration

| Integration | Best for | Install | Guide |
|---|---|---|---|
| [Python `neuraldefend` 1.0.3](https://pypi.org/project/neuraldefend/1.0.3/) | Python services and scripts (Python 3.9+) | `pip install neuraldefend` | [Python SDK](packages/python/README.md) |
| [TypeScript `@neuraldefend/sdk` 1.0.4](https://www.npmjs.com/package/@neuraldefend/sdk/v/1.0.4) | Node.js 22+ and evergreen browsers | `npm install @neuraldefend/sdk` | [TypeScript SDK](packages/typescript/README.md) |
| [MCP `neuraldefend-mcp` 2.0.0](https://pypi.org/project/neuraldefend-mcp/2.0.0/) | MCP-compatible agents and tools (Python 3.10+) | `pip install neuraldefend-mcp` | [MCP server](packages/mcp/README.md) |
| [Go `neuraldefend` 1.0.0](https://github.com/Neural-Defend/NeuralDefend-SDKs/tree/main/packages/go) | Go services and CLIs (Go 1.22+) | `go get github.com/Neural-Defend/NeuralDefend-SDKs/packages/go@v1.0.0` | [Go SDK](packages/go/README.md) |

Use the Python, TypeScript, or Go SDK for application code. Use the MCP server when an agent
needs controlled access to authorized local media; it requires an explicit directory
allowlist.

## Get an API key

NeuroVerify API keys are issued by **Neural Defend** after customer onboarding:

1. Visit **[neuraldefend.com](https://neuraldefend.com/)** and choose **Book a Demo**.
2. After onboarding, store your key in `NEURALDEFEND_API_KEY` (Python, Node.js, MCP) or
   pass it explicitly to the client constructor.
3. Contact [support@neuraldefend.com](mailto:support@neuraldefend.com) for existing
   accounts, staging keys, or endpoint scope questions.
4. API reference: [Neural Defend documentation](https://neuraldefend.gitbook.io/neural-defend).

## Quick start

Obtain an API key through Neural Defend onboarding (see [Get an API key](#get-an-api-key)),
store it in `NEURALDEFEND_API_KEY`, and install the client you need. Each snippet creates
a client and runs image plus video detection.

### Python

```bash
pip install neuraldefend
```

```python
from neuraldefend import NeuroVerifyClient

with NeuroVerifyClient() as client:
    image = client.detect_image("selfie.jpg")
    video = client.detect_video("clip.mp4")
```

### Node.js

```bash
npm install @neuraldefend/sdk
```

```js
import { NeuroVerifyClient } from "@neuraldefend/sdk";

const client = new NeuroVerifyClient();
const image = await client.detectImage("selfie.jpg");
const video = await client.detectVideo("clip.mp4");
```

### Go

```bash
go get github.com/Neural-Defend/NeuralDefend-SDKs/packages/go@v1.0.0
```

```go
client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{
    APIKey: os.Getenv("NEURALDEFEND_API_KEY"),
})
if err != nil {
    log.Fatal(err)
}
image, err := client.DetectImage(context.Background(), neuraldefend.FileMedia("selfie.jpg"))
video, err := client.DetectVideo(context.Background(), neuraldefend.FileMedia("clip.mp4"), neuraldefend.VideoOptions{})
```

### Browser

The same `@neuraldefend/sdk` package is used; bundlers select the browser build. Pass a
short-lived credential from your backend — never a long-lived production key.

```js
import { NeuroVerifyClient } from "@neuraldefend/sdk";

const client = new NeuroVerifyClient({ apiKey });
const image = await client.detectImage(file);
```

### MCP

```bash
pip install neuraldefend-mcp
```

```json
{
  "mcpServers": {
    "neuraldefend": {
      "command": "neuraldefend-mcp",
      "env": {
        "NEURALDEFEND_API_KEY": "${NEURALDEFEND_API_KEY}",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": "/absolute/path/to/authorized-media"
      }
    }
  }
}
```

The server exposes `detect_image_authenticity` and `detect_video_authenticity` for
allowlisted local files.

For input types, configuration, retries, and result handling, see the
[Python](packages/python/README.md), [TypeScript](packages/typescript/README.md),
[Go](packages/go/README.md), and [MCP](packages/mcp/README.md) guides. For complete
response scenarios, see the
[image API guide](docs/client/unified-face-authenticity.md) and
[video API guide](docs/client/unified-video-authenticity.md).

> **Use results as decision support.** Branch on the response `status`, not HTTP 200
> alone: rejected media may return HTTP 200 and no score. Low risk is not proof of
> authenticity, and high risk should trigger human review rather than automatic
> rejection. Requests and retries may create billable transactions. Upload only
> authorized media, protect API keys, and apply appropriate privacy, residency,
> retention, deletion, logging, and access controls to biometric or other sensitive
> data. Never embed a long-lived production API key in browser code.

## Documentation

- [Python SDK guide](packages/python/README.md) and [changelog](packages/python/CHANGELOG.md)
- [TypeScript SDK guide](packages/typescript/README.md) and [changelog](packages/typescript/CHANGELOG.md)
- [MCP server guide](packages/mcp/README.md) and [changelog](packages/mcp/CHANGELOG.md)
- [Go SDK guide](packages/go/README.md) and [changelog](packages/go/CHANGELOG.md)
- [Image endpoint and response scenarios](docs/client/unified-face-authenticity.md)
- [Video endpoint and response scenarios](docs/client/unified-video-authenticity.md)
- [OpenAPI contract](spec/public.yaml) and [architecture decisions](docs/adr/README.md)
- [Contributing](CONTRIBUTING.md), [release process](docs/releasing.md), and
  [security policy](SECURITY.md)

## Support and releases

- Technical support and private vulnerability reports: support@neuraldefend.com
- Issues: [GitHub Issues](https://github.com/Neural-Defend/NeuralDefend-SDKs/issues)
- Releases: [GitHub Releases](https://github.com/Neural-Defend/NeuralDefend-SDKs/releases)
- Repository changes: [CHANGELOG.md](CHANGELOG.md)

## License

MIT — see [LICENSE](LICENSE).
