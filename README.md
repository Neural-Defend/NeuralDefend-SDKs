# NeuralDefend SDKs

Official clients for the **NeuroVerify Detection API**, which evaluates images and videos
for signs of AI generation, manipulation, spoofing, and related authenticity risks.

## Choose an integration

| Integration | Best for | Install | Guide |
|---|---|---|---|
| [Python `neuraldefend` 1.0.0](https://pypi.org/project/neuraldefend/1.0.0/) | Python services and scripts (Python 3.9+) | `pip install neuraldefend` | [Python SDK](packages/python/README.md) |
| [TypeScript `@neuraldefend/sdk` 1.0.1](https://www.npmjs.com/package/@neuraldefend/sdk/v/1.0.1) | Node.js 22+ and evergreen browsers | `npm install @neuraldefend/sdk` | [TypeScript SDK](packages/typescript/README.md) |
| [MCP `neuraldefend-mcp` 1.0.0](https://pypi.org/project/neuraldefend-mcp/1.0.0/) | MCP-compatible agents and tools (Python 3.10+) | `pip install neuraldefend-mcp` | [MCP server](packages/mcp/README.md) |

Use the Python or TypeScript SDK for application code. Use the MCP server when an agent
needs controlled access to authorized local media; it requires an explicit directory
allowlist.

## Quick start

Obtain an API key through your Neural Defend account, store it in
`NEURALDEFEND_API_KEY`, and install the client for your language. A minimal Python image
and video flow is:

```python
from neuraldefend import NeuroVerifyClient

with NeuroVerifyClient() as client:
    image = client.detect_image("selfie.jpg")
    video = client.detect_video("clip.mp4")

print(image.status, image.risk_level)
print(video.status, video.video_risk_level, video.audio_risk_level)
```

For equivalent Node.js and browser examples, input types, configuration, retries, and
result handling, see the [TypeScript guide](packages/typescript/README.md). For complete
response scenarios, see the [image API guide](docs/client/unified-face-authenticity.md)
and [video API guide](docs/client/unified-video-authenticity.md).

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
