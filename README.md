# NeuralDefend SDKs

Client libraries for the **NeuroVerify Detection API** — AI-generated and manipulated media
detection for images and video.

> **Pre-release.** Nothing in this repository is published yet and the public surface is
> still subject to change. Keep the repository private until all package names are
> reserved on their registries. Follow `CONTRIBUTING.md` and `docs/releasing.md`.

## Packages

| Deliverable | Package | Registry | Status |
|---|---|---|---|
| Python SDK | `neuraldefend` | PyPI | Not yet published |
| TypeScript SDK (browser + Node) | `@neuraldefend/sdk` | npm | Not yet published |
| MCP server | `neuraldefend-mcp` | PyPI | Not yet published |
| Agent skills | — | distributed as files | Included |

## What the API does

Two endpoints. `POST /detect/image` scores a single-face image for signs of spoofing or AI
generation and returns one risk score. `POST /detect/video` returns separate video and
audio risk scores; the API deliberately provides no combined score. Every score is from
0.1 to 10.0 with a `low` / `medium` / `high` band. Treat those bands as decision-support
signals: low is not proof of authenticity, and high should trigger human review rather
than automatic rejection. Authentication is an `x-api-key` header on every request.

One behaviour is easy to get wrong and worth knowing before you read any code: **HTTP 200
does not mean the media was scored.** An image with no face, or several faces, comes back
as HTTP 200 with `status: "rejected"` and null risk fields. Branch on `status`, never on
the HTTP status code alone. See `docs/client/` for every response scenario with worked
examples.

Uploads may contain biometric or other sensitive personal data, and each request can
create a billable transaction. Send only authorized media, minimize retention and
logging, and follow your organization's privacy, residency, deletion, and access-control
requirements.

## Layout

```
spec/       OpenAPI contract and immutable provenance. Never edited by hand.
scripts/    Spec synchronization, validation, generation, and drift checks.
packages/
  python/   Python SDK published as neuraldefend.
  typescript/ TypeScript SDK published as @neuraldefend/sdk.
  mcp/      Secure MCP server built on the Python SDK.
tests/      Shared language-neutral response fixtures.
skills/     Agent guidance distributed as files.
docs/
  client/   Endpoint documentation, copied from the API repo.
  adr/      Architecture decision records.
```

Each package has its own README and changelog. Generated cores are committed for
reproducible releases but are private implementation details.

## Building

Read `CONTRIBUTING.md` and the endpoint contracts in `docs/client/` before changing SDK
behavior.

| Tool | Version |
|---|---|
| Python | 3.10+ for repository tooling; the Python SDK supports 3.9+ |
| Node.js | 22+ |
| Docker | Current maintained release, for pinned code generation and security tooling |
| git | any |

See `CONTRIBUTING.md` for contract and verification rules and `SECURITY.md` for private
vulnerability reporting.

## The spec

`spec/public.yaml` is the source of truth for the API contract and is copied from the API
repository. Do not edit it here, and do not edit `spec/public.json`, which is derived from
it — see `docs/adr/0001-derive-spec-json-from-yaml.md`.

## Support

Technical support: support@neuraldefend.com

## License

MIT — see `LICENSE`.
