# NeuralDefend Go SDK

The official Go client for the NeuroVerify image and video authenticity API. Version
`1.0.0` provides typed result objects, streaming multipart uploads, bounded retries, and
explicit errors for operational failures.

NeuroVerify returns decision-support signals for signs of spoofing, AI generation, or
manipulation:

- Image analysis returns one face-authenticity risk score and risk level.
- Video analysis returns independent video and audio risk scores and risk levels.
- A result can be rejected without being an exception, including some HTTP 200 responses.
- `Billable` is the authoritative billing indicator for each returned transaction.

## Requirements

- Go 1.22 or newer
- A NeuroVerify API key
- Network access to the configured HTTPS API origin

## Installation

```bash
go get github.com/Neural-Defend/NeuralDefend-SDKs/packages/go@v1.0.0
```

## Quick start

```go
package main

import (
	"context"
	"log"
	"os"

	"github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

func main() {
	client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{
		APIKey: os.Getenv("NEURALDEFEND_API_KEY"),
	})
	if err != nil {
		log.Fatal(err)
	}

	result, err := client.DetectImage(
		context.Background(),
		neuraldefend.FileMedia("selfie.jpg"),
	)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("status=%s scored=%t risk=%v", result.Status, result.Scored(), result.RiskScore)
}
```

See [`examples/detect_media/main.go`](examples/detect_media/main.go) for image and video
usage.

## Configuration

| Option | Description |
| --- | --- |
| `APIKey` | API key; falls back to `NEURALDEFEND_API_KEY` |
| `BaseURL` | API origin; defaults to production or `NEURALDEFEND_BASE_URL` |
| `AllowCustomBaseURL` | Required for non-Neural Defend origins |
| `Timeout` | Request timeout (default 120s) |
| `MaxRetries` | Retries for 429/500/503 (default 3) |
| `HTTPClient` | Custom `*http.Client` |
| `UserAgent` | Custom user agent |

Use `NewStagingClient` to pin the client to staging regardless of environment variables.

## License

MIT — see [LICENSE](LICENSE).
