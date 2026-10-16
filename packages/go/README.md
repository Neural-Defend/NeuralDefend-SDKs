<div align="center">

# NeuralDefend Go SDK

**Detect deepfakes, AI-generated faces, and spoofed media from Go in a few lines of code.**

[![Go](https://img.shields.io/badge/go-1.22%2B-00ADD8?style=flat-square&logo=go&logoColor=white)](https://go.dev/)
[![Go Reference](https://pkg.go.dev/badge/github.com/Neural-Defend/NeuralDefend-SDKs/packages/go.svg)](https://pkg.go.dev/github.com/Neural-Defend/NeuralDefend-SDKs/packages/go)
[![Version](https://img.shields.io/badge/version-1.0.0-00ADD8?style=flat-square&logo=go&logoColor=white)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-22863A?style=flat-square)](LICENSE)

[Quick start](#quick-start-image) · [Examples](#examples) · [Results](#result-handling) · [Errors](#errors) · [Troubleshooting](#troubleshooting)

</div>

---

## In plain words

You give the SDK a photo or a video. It sends the file to Neural Defend's **NeuroVerify**
service and gives you back an answer like this:

> "This face has a **low** / **medium** / **high** risk of being fake."

That is the whole idea. You do not need to know anything about machine learning, HTTP, or
multipart uploads; the SDK handles all of that for you.

| You want to... | Call | You get back |
|---|---|---|
| Check a photo of a face | `client.DetectImage(ctx, neuraldefend.FileMedia("photo.jpg"))` | An `ImageResult` with one risk level |
| Check a video | `client.DetectVideo(ctx, neuraldefend.FileMedia("clip.mp4"), neuraldefend.VideoOptions{})` | A `VideoResult` with a video risk and an audio risk |

Think of the risk level as a traffic light:

| Risk level | Meaning | What to do |
|---|---|---|
| `low` 🟢 | Few signs of manipulation were found | Continue, using your normal process |
| `medium` 🟡 | The result is unclear | Ask for more evidence or a human review |
| `high` 🔴 | Strong signs of spoofing or AI generation | Escalate to a human reviewer |

Sometimes the service cannot score a file, for example when there is no face in the
photo. That is a normal answer called a **rejection**: you get a result back with
`err == nil`, not an error. The [examples](#examples) show how to handle each case.

## About this SDK

The official Go client for the NeuroVerify image and video authenticity API. Version
`1.0.0` provides typed result structs, streaming multipart uploads, bounded retries,
`context.Context` support on every call, and explicit error types for operational
failures. It uses only the Go standard library.

NeuroVerify returns decision-support signals for signs of spoofing, AI generation, or
manipulation:

- Image analysis returns one face-authenticity risk score and risk level.
- Video analysis returns independent video and audio risk scores and risk levels.
- A result can be rejected without being an error, including some HTTP 200 responses.
- `Billable` is the authoritative billing indicator for each returned transaction.

Risk output is not proof of authenticity and must not be the sole basis for an automated
accept/reject decision. Use the server-provided risk level with other evidence, documented
policy, and human review where appropriate.

## Requirements

- Go 1.22 or newer
- A NeuroVerify API key with access to the image and/or video endpoint
- Network access to the configured HTTPS API origin

This guide documents module `github.com/Neural-Defend/NeuralDefend-SDKs/packages/go`
version `v1.0.0`. The package name is `neuraldefend`.

## Installation

Add the pinned release to your module:

```bash
go get github.com/Neural-Defend/NeuralDefend-SDKs/packages/go@v1.0.0
```

Because the import path ends in `/go`, the examples in this guide import the package with
an explicit name so it is obvious in your code:

```go
import neuraldefend "github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
```

Confirm the module resolved:

```bash
go list -m github.com/Neural-Defend/NeuralDefend-SDKs/packages/go
```

Output:

```text
github.com/Neural-Defend/NeuralDefend-SDKs/packages/go v1.0.0
```

You can also print `neuraldefend.Version` from a program; it is `"1.0.0"` for this release.

## Get an API key

NeuroVerify API keys are issued by **Neural Defend** after customer onboarding. There is no
self-service key — request access from the company first, then configure the SDK.

1. Visit **[neuraldefend.com](https://neuraldefend.com/)** and choose **Book a Demo** to
   talk with the Neural Defend team about deepfake detection, AI-generated media analysis,
   and API access for your use case.
2. After onboarding, Neural Defend provides an API key scoped to the image and/or video
   endpoints you need. Existing customers can also ask their account manager for a key,
   staging credential, or rate-limit details.
3. Store the key in a secret manager or the `NEURALDEFEND_API_KEY` environment variable
   (see below). Never commit it, embed it in client-side code, or paste it into logs or
   support tickets.
4. For REST endpoint reference while you wait for a key, see the
   [Neural Defend API documentation](https://neuraldefend.gitbook.io/neural-defend).

**Contact:** [support@neuraldefend.com](mailto:support@neuraldefend.com)

## API-key configuration

macOS/Linux:

```bash
# Request a key at https://neuraldefend.com/ (Book a Demo), then export it:
export NEURALDEFEND_API_KEY="replace-with-your-api-key"
```

PowerShell:

```powershell
# Request a key at https://neuraldefend.com/ (Book a Demo), then set it:
$env:NEURALDEFEND_API_KEY = "replace-with-your-api-key"
```

When `ClientOptions.APIKey` is empty, `NewClient` reads `NEURALDEFEND_API_KEY`:

```go
// Requires NEURALDEFEND_API_KEY from https://neuraldefend.com/ onboarding.
client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{})
if err != nil {
	log.Fatal(err) // a *neuraldefend.ValidationError when no key is found
}
```

You can pass `APIKey` explicitly when it comes from an application secret provider:

```go
client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{
	APIKey: secrets.Get("neuraldefend-api-key"), // your own secret provider
})
```

A non-empty `APIKey` takes precedence over `NEURALDEFEND_API_KEY`. Avoid hard-coding the
key even when using the explicit option.

## Quick start: image

Save as `main.go` in a module that has the SDK (`go mod init example.com/demo`, then the
`go get` command above), and run `go run .`:

```go
package main

import (
	"context"
	"encoding/json"
	"fmt"

	neuraldefend "github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

func main() {
	client, _ := neuraldefend.NewClient(neuraldefend.ClientOptions{}) // uses NEURALDEFEND_API_KEY
	result, _ := client.DetectImage(context.Background(), neuraldefend.FileMedia("selfie.jpg"))
	response, _ := json.MarshalIndent(result.Raw, "", "  ")
	fmt.Println(string(response))
}
```

That's it. `result.Raw` is the full response exactly as the API sent it:

```json
{
  "ai_threat_signals": [
    "Visual Safety Screening",
    "Liveness Verification"
  ],
  "billable": "Y",
  "content_type": "image/jpeg",
  "filename": "selfie.jpg",
  "message": "Not likely to be Spoof or AI-generated",
  "risk_level": "low",
  "risk_score": 2.2,
  "status": "success",
  "status_code": 1,
  "unique_trx_id": "trx_example_image_low"
}
```

The field that matters most is `risk_level`: `low`, `medium`, or `high`. In your code, read
the same values from typed fields such as `result.RiskLevel` (see [Examples](#examples)).
Errors are ignored here to keep the snippet short; always check them in real code.

## Quick start: video

```go
package main

import (
	"context"
	"encoding/json"
	"fmt"

	neuraldefend "github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

func main() {
	client, _ := neuraldefend.NewClient(neuraldefend.ClientOptions{})
	result, _ := client.DetectVideo(context.Background(), neuraldefend.FileMedia("clip.mp4"), neuraldefend.VideoOptions{})
	response, _ := json.MarshalIndent(result.Raw, "", "  ")
	fmt.Println(string(response))
}
```

You get the full response, with a separate result for the picture and for the sound:

```json
{
  "ai_threat_signals": [
    "Face Swap Detection",
    "Audio Frequency Analysis"
  ],
  "audio_message": "Likely to be AI-generated",
  "audio_risk_level": "high",
  "audio_risk_score": 8.4,
  "billable": "Y",
  "content_type": "video/mp4",
  "filename": "clip.mp4",
  "status": "success",
  "status_code": 1,
  "unique_trx_id": "trx_example_video_modalities",
  "video_message": "Not likely to be AI-generated",
  "video_risk_level": "low",
  "video_risk_score": 2.2
}
```

## Examples

> **Building for a specific industry?** See the [industry use cases](../../docs/use-cases/README.md):
> eKYC onboarding, KYC re-verification, Video KYC, HR tech, and video conferencing, with
> complete code for this SDK.

Each example is a complete `package main` program: put it in its own module (see
[Quick start](#quick-start-image)), set `NEURALDEFEND_API_KEY`, and run it with
`go run .`. The output shown under each example is representative; your scores,
transaction IDs, and messages will differ.

| # | Example | You will learn |
|:-:|---|---|
| 1 | [Check one photo](#1-check-one-photo) | The smallest useful program |
| 2 | [Check a video with sound](#2-check-a-video-with-sound) | Reading the separate video and audio results |
| 3 | [Turn a result into a decision](#3-turn-a-result-into-a-decision) | Mapping low, medium, high, and rejected to actions |
| 4 | [Upload bytes or a reader from memory](#4-upload-bytes-or-a-reader-from-memory) | Checking files that never touch the disk |
| 5 | [Check a whole folder](#5-check-a-whole-folder) | Batch processing with a summary |
| 6 | [Handle every kind of error](#6-handle-every-kind-of-error) | Telling bad input, bad keys, and outages apart |
| 7 | [Save an audit record](#7-save-an-audit-record) | Keeping transaction IDs for billing and support |
| 8 | [Add a check to an HTTP handler](#8-add-a-check-to-an-http-handler) | Using the SDK inside a `net/http` server |
| 9 | [Test against staging](#9-test-against-staging) | Using the staging environment safely |
| 10 | [Tune video sampling](#10-tune-video-sampling) | Trading speed for coverage on long videos |
| 11 | [Set a deadline or cancel a check](#11-set-a-deadline-or-cancel-a-check) | Using `context.Context` timeouts and cancellation |

### 1. Check one photo

The shortest possible program. With an empty `ClientOptions`, the client reads
`NEURALDEFEND_API_KEY` for you.

```go
package main

import (
	"context"
	"fmt"
	"log"

	neuraldefend "github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

func main() {
	client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{}) // reads NEURALDEFEND_API_KEY
	if err != nil {
		log.Fatal(err)
	}

	result, err := client.DetectImage(context.Background(), neuraldefend.FileMedia("selfie.jpg"))
	if err != nil {
		log.Fatal(err)
	}

	if result.Scored() {
		fmt.Println(result.Status, *result.RiskLevel, *result.RiskScore)
	} else {
		fmt.Println(result.Status)
	}
	fmt.Println(result.Message)
}
```

Output:

```text
success low 2.2
Not likely to be Spoof or AI-generated
```

### 2. Check a video with sound

A video gets **two** separate answers: one for the picture and one for the audio. A clip
without sound is still scored; only the audio fields are `nil`.

```go
package main

import (
	"context"
	"fmt"
	"log"

	neuraldefend "github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

func main() {
	client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{})
	if err != nil {
		log.Fatal(err)
	}

	result, err := client.DetectVideo(
		context.Background(),
		neuraldefend.FileMedia("interview.mp4"),
		neuraldefend.VideoOptions{}, // use the service defaults
	)
	if err != nil {
		log.Fatal(err)
	}

	if !result.Scored() {
		fmt.Println("Not scored:", result.VideoMessage)
		return
	}
	fmt.Printf("Video: %s (%.1f)\n", *result.VideoRiskLevel, *result.VideoRiskScore)
	if result.HasAudio() {
		fmt.Printf("Audio: %s (%.1f)\n", *result.AudioRiskLevel, *result.AudioRiskScore)
	} else if result.AudioMessage != nil {
		fmt.Printf("Audio: not scored (%s)\n", *result.AudioMessage)
	}
}
```

Output:

```text
Video: low (2.2)
Audio: high (8.4)
```

Here the face looks real but the voice is likely synthetic, which is why the two
modalities are reported separately.

### 3. Turn a result into a decision

Your application usually needs one of a few actions. Write that mapping once and reuse
it. Always branch on the **risk level**, never on your own numeric threshold, because the
service may tune its scoring bands.

```go
package main

import (
	"context"
	"fmt"
	"log"

	neuraldefend "github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

func decide(result neuraldefend.ImageResult) string {
	if result.Rejected() {
		return "ASK FOR A NEW PHOTO - " + result.Message
	}
	if !result.Scored() {
		return fmt.Sprintf("MANUAL REVIEW - unrecognized status %q", result.Status)
	}
	switch *result.RiskLevel {
	case "low":
		return "CONTINUE"
	case "medium":
		return "MANUAL REVIEW"
	case "high":
		return "ESCALATE"
	default:
		return "MANUAL REVIEW"
	}
}

func main() {
	client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{})
	if err != nil {
		log.Fatal(err)
	}

	ctx := context.Background()
	for _, path := range []string{"selfie.jpg", "printed_photo.jpg", "landscape.jpg"} {
		result, err := client.DetectImage(ctx, neuraldefend.FileMedia(path))
		if err != nil {
			fmt.Printf("%-20s -> ERROR - %v\n", path, err)
			continue
		}
		fmt.Printf("%-20s -> %s\n", path, decide(result))
	}
}
```

Output:

```text
selfie.jpg           -> CONTINUE
printed_photo.jpg    -> ESCALATE
landscape.jpg        -> ASK FOR A NEW PHOTO - No face detected in the image
```

### 4. Upload bytes or a reader from memory

When a file arrives from a web form, a queue, or object storage, you often have bytes or
an `io.Reader` instead of a path. Give the SDK a `filename` as well; its extension tells
the SDK the format.

```go
package main

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"os"

	neuraldefend "github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

func main() {
	client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{})
	if err != nil {
		log.Fatal(err)
	}
	ctx := context.Background()

	imageBytes, err := os.ReadFile("selfie.jpg") // or bytes from your storage service
	if err != nil {
		log.Fatal(err)
	}

	// Option A: a byte slice.
	result, err := client.DetectImage(ctx, neuraldefend.BytesMedia("selfie.jpg", imageBytes))
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("%d bytes checked -> %s\n", len(imageBytes), result.Status)

	// Option B: a seekable reader with a known size (rewound safely on retries).
	reader := bytes.NewReader(imageBytes)
	result, err = client.DetectImage(ctx, neuraldefend.ReaderMedia("selfie.jpg", reader, int64(len(imageBytes))))
	if err != nil {
		log.Fatal(err)
	}
	if result.Scored() {
		fmt.Println("reader checked ->", *result.RiskLevel)
	}
}
```

Output:

```text
482113 bytes checked -> success
reader checked -> low
```

A stream that cannot rewind (for example a network body) can be passed with a size of
`-1`, but then the client must be built with `MaxRetries` set to `0`, because a used-up
stream cannot be sent twice. See [Input types](#input-types-and-stream-lifecycle).

### 5. Check a whole folder

Reuse one client for many files; it keeps connections open and is much faster than
creating a client per file. `neuraldefend.ImageExtensions` lists every supported image
extension, so you do not have to maintain your own list.

```go
package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	neuraldefend "github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

func main() {
	client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{})
	if err != nil {
		log.Fatal(err)
	}

	folder := "uploads"
	entries, err := os.ReadDir(folder) // sorted by filename
	if err != nil {
		log.Fatal(err)
	}

	ctx := context.Background()
	summary := map[string]int{}
	for _, entry := range entries {
		ext := strings.ToLower(filepath.Ext(entry.Name()))
		if _, ok := neuraldefend.ImageExtensions[ext]; entry.IsDir() || !ok {
			continue
		}

		result, err := client.DetectImage(ctx, neuraldefend.FileMedia(filepath.Join(folder, entry.Name())))
		if err != nil {
			summary["error"]++
			fmt.Printf("%-24s %-9s %v\n", entry.Name(), "error", err)
			continue
		}

		outcome := "rejected"
		if result.Scored() {
			outcome = *result.RiskLevel
		}
		summary[outcome]++
		fmt.Printf("%-24s %-9s %s\n", entry.Name(), outcome, result.Message)
	}

	fmt.Println("\nSummary:", summary)
}
```

Output:

```text
anna.jpg                 low       Not likely to be Spoof or AI-generated
group_photo.jpg          rejected  Multiple faces detected in the image
id_card_scan.png         medium    Less likely to be Spoof or AI-generated
printed_photo.jpg        high      Likely to be Spoof detected

Summary: map[high:1 low:1 medium:1 rejected:1]
```

Each call is a separate transaction and may be billable. Check your rate limits before
running large batches. One `*Client` can also be shared by several goroutines if you want
to check files in parallel; keep the concurrency within your rate limit.

### 6. Handle every kind of error

There are three different situations, and each one needs a different fix:

| Situation | How it shows up | Who fixes it |
|---|---|---|
| The file was checked but could not be scored | `err == nil` and `result.Rejected() == true` | The end user sends better media |
| Your setup is wrong (missing key, bad path) | `*ValidationError`, `*AuthenticationError`, `*ScopeError` | You, the developer |
| The service or network had a problem | `*RateLimitError`, `*ServerError`, `*TimeoutError`, `*NetworkError` | Try again later |

Every SDK error is a pointer type, so use `errors.As` to find out which one you got:

```go
package main

import (
	"context"
	"errors"
	"fmt"

	neuraldefend "github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

func check(path string) {
	client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{})
	if err != nil {
		explain(err)
		return
	}

	result, err := client.DetectImage(context.Background(), neuraldefend.FileMedia(path))
	if err != nil {
		explain(err)
		return
	}

	if result.Rejected() {
		fmt.Println("Please upload a different photo:", result.Message)
	} else if result.Scored() {
		fmt.Println("Risk:", *result.RiskLevel)
	}
}

func explain(err error) {
	var (
		validation *neuraldefend.ValidationError
		auth       *neuraldefend.AuthenticationError
		scope      *neuraldefend.ScopeError
		rateLimit  *neuraldefend.RateLimitError
		server     *neuraldefend.ServerError
		timeout    *neuraldefend.TimeoutError
		network    *neuraldefend.NetworkError
	)
	switch {
	case errors.As(err, &validation):
		fmt.Println("Fix the input or configuration:", validation.Detail)
	case errors.As(err, &auth):
		fmt.Println("The API key is invalid or expired. Check NEURALDEFEND_API_KEY.")
	case errors.As(err, &scope):
		fmt.Println("This key cannot use the image endpoint. Ask Neural Defend to add it.")
	case errors.As(err, &rateLimit):
		if rateLimit.RetryAfter != nil {
			fmt.Printf("Too many requests. Try again in %.0f seconds.\n", *rateLimit.RetryAfter)
		} else {
			fmt.Println("Too many requests. Try again later.")
		}
	case errors.As(err, &server):
		fmt.Printf("Service problem (HTTP %d), request id: %s\n", server.StatusCode, server.RequestID)
	case errors.As(err, &timeout):
		fmt.Println("The request timed out:", timeout.Detail)
	case errors.As(err, &network):
		fmt.Println("Network problem:", network.Detail)
	default:
		fmt.Println("Unexpected error:", err)
	}
}

func main() {
	check("selfie.jpg")
}
```

Output when the key is missing:

```text
Fix the input or configuration: api_key is required (pass it explicitly or set NEURALDEFEND_API_KEY)
```

Output when the photo has no face:

```text
Please upload a different photo: No face detected in the image
```

The [Errors](#errors) section lists every error type, including `*ProtocolError` and
`*HttpError`, which the `default` branch above catches.

### 7. Save an audit record

Every result has a `UniqueTrxID`. Store it: it is what support and billing will ask for.
The result structs have no JSON tags, so define your own small record with exactly the
fields you want to keep.

```go
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"time"

	neuraldefend "github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

type auditRecord struct {
	CheckedAt     string  `json:"checked_at"`
	TransactionID string  `json:"transaction_id"`
	Status        string  `json:"status"`
	RiskLevel     *string `json:"risk_level"` // null when the image was not scored
	Billable      bool    `json:"billable"`
}

func main() {
	client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{})
	if err != nil {
		log.Fatal(err)
	}

	result, err := client.DetectImage(context.Background(), neuraldefend.FileMedia("selfie.jpg"))
	if err != nil {
		log.Fatal(err)
	}

	record := auditRecord{
		CheckedAt:     time.Now().UTC().Format(time.RFC3339Nano),
		TransactionID: result.UniqueTrxID,
		Status:        result.Status,
		RiskLevel:     result.RiskLevel,
		Billable:      result.Billable,
	}

	line, err := json.Marshal(record)
	if err != nil {
		log.Fatal(err)
	}
	logFile, err := os.OpenFile("audit.jsonl", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		log.Fatal(err)
	}
	defer logFile.Close()
	if _, err := logFile.Write(append(line, '\n')); err != nil {
		log.Fatal(err)
	}

	pretty, _ := json.MarshalIndent(record, "", "  ")
	fmt.Println(string(pretty))
}
```

Output:

```json
{
  "checked_at": "2026-10-16T09:41:07.51231Z",
  "transaction_id": "trx_example_image_low",
  "status": "success",
  "risk_level": "low",
  "billable": true
}
```

Store only the fields you need. Avoid logging filenames or `result.Raw`, which may contain
personal data.

### 8. Add a check to an HTTP handler

This standard-library `net/http` server accepts an upload in a form field called `photo`
and returns a small JSON answer. One client is created at startup and shared by all
requests. The handler passes `r.Context()`, so the check stops if the caller disconnects.
The `"POST /verify-selfie"` route pattern needs Go 1.22, which this SDK already requires.

```go
package main

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"

	neuraldefend "github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

type verifyResponse struct {
	TransactionID string   `json:"transaction_id"`
	Status        string   `json:"status"`
	Scored        bool     `json:"scored"`
	RiskLevel     *string  `json:"risk_level"`
	RiskScore     *float64 `json:"risk_score"`
	Message       string   `json:"message"`
	Billable      bool     `json:"billable"`
}

var client *neuraldefend.Client

func verifySelfie(w http.ResponseWriter, r *http.Request) {
	// Refuse request bodies far larger than the 10 MiB image limit.
	r.Body = http.MaxBytesReader(w, r.Body, neuraldefend.IMAGE_MAX_BYTES+1<<20)

	file, header, err := r.FormFile("photo")
	if err != nil {
		http.Error(w, "upload an image in the 'photo' form field", http.StatusBadRequest)
		return
	}
	defer file.Close()

	media := neuraldefend.ReaderMedia(header.Filename, file, header.Size)
	result, err := client.DetectImage(r.Context(), media)

	var validation *neuraldefend.ValidationError
	switch {
	case errors.As(err, &validation):
		http.Error(w, validation.Detail, http.StatusUnprocessableEntity)
		return
	case err != nil:
		log.Printf("verification failed: %v", err)
		http.Error(w, "verification is temporarily unavailable", http.StatusServiceUnavailable)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(verifyResponse{
		TransactionID: result.UniqueTrxID,
		Status:        result.Status,
		Scored:        result.Scored(),
		RiskLevel:     result.RiskLevel,
		RiskScore:     result.RiskScore,
		Message:       result.Message,
		Billable:      result.Billable,
	})
}

func main() {
	var err error
	client, err = neuraldefend.NewClient(neuraldefend.ClientOptions{})
	if err != nil {
		log.Fatal(err)
	}

	http.HandleFunc("POST /verify-selfie", verifySelfie)
	log.Println("listening on http://127.0.0.1:8000")
	log.Fatal(http.ListenAndServe("127.0.0.1:8000", nil))
}
```

Run it with `go run .`, then call it:

```bash
curl -F "photo=@selfie.jpg" http://127.0.0.1:8000/verify-selfie
```

Output:

```json
{"transaction_id":"trx_example_image_low","status":"success","scored":true,"risk_level":"low","risk_score":2.2,"message":"Not likely to be Spoof or AI-generated","billable":true}
```

The uploaded file is seekable, so the SDK can rewind it if it needs to retry. Because it
also implements `io.Closer`, the SDK closes it when `DetectImage` returns; the extra
`defer file.Close()` is harmless.

### 9. Test against staging

Neural Defend can issue a separate staging key during onboarding. `NewStagingClient`
always uses the staging server, so a test can never reach production by mistake.

```go
package main

import (
	"context"
	"fmt"
	"log"
	"os"

	neuraldefend "github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

func main() {
	maxRetries := 0 // fail fast in tests
	client, err := neuraldefend.NewStagingClient(neuraldefend.ClientOptions{
		APIKey:     os.Getenv("NEURALDEFEND_STAGING_API_KEY"),
		MaxRetries: &maxRetries,
	})
	if err != nil {
		log.Fatal(err)
	}

	result, err := client.DetectImage(context.Background(), neuraldefend.FileMedia("testdata/selfie.jpg"))
	if err != nil {
		log.Fatal(err)
	}

	level := "none"
	if result.RiskLevel != nil {
		level = *result.RiskLevel
	}
	fmt.Printf("staging (%s): %s / %s\n", client.BaseURL(), result.Status, level)
}
```

Output:

```text
staging (https://stage.deepscan.neuraldefend.com): success / low
```

If `NEURALDEFEND_STAGING_API_KEY` is empty, `APIKey` falls back to `NEURALDEFEND_API_KEY`
like any other client, so make sure the staging variable is set in your test environment.

### 10. Tune video sampling

The service looks at 12 frames by default. Long videos can use more frames for better
coverage; quick checks can use fewer for speed. `MaxFrames` accepts 1 to 100.

```go
package main

import (
	"context"
	"fmt"
	"log"
	"time"

	neuraldefend "github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

func main() {
	client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{
		Timeout: 300 * time.Second, // allow more time for large uploads
	})
	if err != nil {
		log.Fatal(err)
	}

	ctx := context.Background()
	for _, frames := range []int{6, 24, 48} {
		started := time.Now()
		result, err := client.DetectVideo(ctx, neuraldefend.FileMedia("webinar.mp4"),
			neuraldefend.VideoOptions{MaxFrames: &frames})
		if err != nil {
			log.Fatal(err)
		}

		level := "not scored"
		if result.VideoRiskLevel != nil {
			level = *result.VideoRiskLevel
		}
		fmt.Printf("%2d frames -> video %s in %.1fs\n", frames, level, time.Since(started).Seconds())
	}
}
```

Output:

```text
 6 frames -> video low in 4.8s
24 frames -> video low in 9.3s
48 frames -> video low in 15.6s
```

Each call above is a separate, billable transaction. Pick one setting for production.

### 11. Set a deadline or cancel a check

Every detection method takes a `context.Context`. Use it to put a time limit on one call,
or to stop work when the user goes away. A missed deadline comes back as a
`*TimeoutError`; a cancelled context comes back as a `*NetworkError`, so check
`ctx.Err()` to tell a cancellation apart from a real network fault.

```go
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	neuraldefend "github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

func main() {
	client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{})
	if err != nil {
		log.Fatal(err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	result, err := client.DetectVideo(ctx, neuraldefend.FileMedia("long_meeting.mp4"), neuraldefend.VideoOptions{})

	var timeout *neuraldefend.TimeoutError
	switch {
	case errors.As(err, &timeout):
		fmt.Println("Gave up after 30s. Billing is unknown; do not resubmit blindly.")
	case errors.Is(ctx.Err(), context.Canceled):
		fmt.Println("The check was cancelled.")
	case err != nil:
		log.Fatal(err)
	default:
		fmt.Println("Finished:", result.Status)
	}
}
```

Output when the upload takes too long:

```text
Gave up after 30s. Billing is unknown; do not resubmit blindly.
```

The `Timeout` client option (default 120 seconds) is a limit on each HTTP attempt; a
context deadline is a limit on the whole call. Use whichever is shorter for your use
case. The pause between automatic retries is not interrupted by cancellation, but the
next attempt stops immediately.

## Result handling

Detection methods return an `ImageResult` or `VideoResult` value with `err == nil` for
both successful scores and business rejections. Branch on `result.Status` or the
helper methods:

| Helper | On | Returns `true` when |
|---|---|---|
| `Scored()` | `ImageResult` | `Status == "success"` and a recognized risk score and level are present |
| `Scored()` | `VideoResult` | `Status == "success"`, the video modality is scored, and audio is either scored or absent |
| `Rejected()` | both | `Status == "rejected"` |
| `HighRisk()` | `ImageResult` | `RiskLevel` is `"high"` |
| `HasAudio()` | `VideoResult` | an audio risk score is present |
| `OverallRiskScore()` | `VideoResult` | returns the maximum non-nil video/audio score as `*float64`, or `nil` |

Do not infer success from HTTP 200. No-face and face-policy outcomes can be HTTP 200
rejections with `nil` risk fields and may be billable. Do not create policy from numeric
thresholds: use the API-owned `low`, `medium`, and `high` bands because thresholds may be
tuned.

### Result fields

`ImageResult`:

| Field | Type | Meaning |
|---|---|---|
| `UniqueTrxID` | `string` | Transaction ID for audit, support, and billing |
| `Filename` | `string` | Upload name echoed by the service |
| `ContentType` | `string` | Content type detected by the service |
| `Status` | `string` | `"success"` or `"rejected"` (future values are possible) |
| `StatusCode` | `int` | The API's business status code |
| `Billable` | `bool` | Whether this transaction is billable (wire `"Y"`/`"N"`) |
| `RiskScore` | `*float64` | 0.1 to 10.0, or `nil` when not scored |
| `RiskLevel` | `*string` | `"low"`, `"medium"`, `"high"`, or `nil` |
| `Message` | `string` | Human-readable explanation |
| `AIThreatSignals` | `[]string` | Analysis signals; empty (never `nil`) when none |
| `Raw` | `map[string]any` | Sanitized copy of the score envelope |

`VideoResult` has the same `UniqueTrxID`, `Filename`, `ContentType`, `Status`,
`StatusCode`, `Billable`, `AIThreatSignals`, and `Raw` fields, plus:

| Field | Type | Meaning |
|---|---|---|
| `VideoRiskScore` / `AudioRiskScore` | `*float64` | 0.1 to 10.0, or `nil` |
| `VideoRiskLevel` / `AudioRiskLevel` | `*string` | `"low"`, `"medium"`, `"high"`, or `nil` |
| `VideoMessage` | `string` | Explanation for the video modality (or the rejection) |
| `AudioMessage` | `*string` | Explanation for the audio modality, or `nil` |

### Your own JSON versus `Raw`

The result structs have no JSON tags. `json.Marshal(result)` would produce Go field names
such as `UniqueTrxID` and would include `Raw`, so for APIs, logs, and databases define a
small struct of your own with the fields you need, as in
[example 7](#7-save-an-audit-record) and [example 8](#8-add-a-check-to-an-http-handler).

`result.Raw` is the score envelope exactly as the service sent it, with any occurrence of
your API key replaced by `[REDACTED]`. It is kept for diagnostics and forward
compatibility and can contain additive fields the SDK does not yet map, including
filenames or future personal/customer fields. Do not log or persist `Raw` without
justified access, redaction, and retention controls.

## Representative normalized outputs

The values below are representative examples based on the documented API scenarios.
Scores, transaction IDs, messages, detected content types, and threat signals vary by
media and service evolution. They are shown as the Go result fields (pointer fields
dereferenced, `nil` shown as `nil`) plus the helper methods, not as raw wire envelopes.

### Image outcomes

Low, medium, and high are scored outcomes. Low means lower observed risk, not proof that
an image is authentic. Medium is inconclusive and should receive additional review. High
indicates stronger risk signals and should be escalated under your policy.

Representative low-risk result:

```text
UniqueTrxID:     trx_example_image_low
Filename:        selfie.jpg
ContentType:     image/jpeg
Status:          success
StatusCode:      1
Billable:        true
RiskScore:       2.2
RiskLevel:       low
Message:         Not likely to be Spoof or AI-generated
AIThreatSignals: [Visual Safety Screening Liveness Verification]
Scored()=true  Rejected()=false  HighRisk()=false
```

Representative medium-risk result:

```text
UniqueTrxID:     trx_example_image_medium
Filename:        portrait.jpg
ContentType:     image/jpeg
Status:          success
StatusCode:      1
Billable:        true
RiskScore:       5.5
RiskLevel:       medium
Message:         Less likely to be Spoof or AI-generated
AIThreatSignals: [Visual Safety Screening Liveness Verification]
Scored()=true  Rejected()=false  HighRisk()=false
```

Representative high-risk result:

```text
UniqueTrxID:     trx_example_image_high
Filename:        printed_photo.jpg
ContentType:     image/jpeg
Status:          success
StatusCode:      1
Billable:        true
RiskScore:       8.7
RiskLevel:       high
Message:         Likely to be Spoof detected
AIThreatSignals: [Visual Safety Screening Liveness Verification]
Scored()=true  Rejected()=false  HighRisk()=true
```

No-face and multiple-face image results are normal, billable rejections even though the
HTTP response is 200:

```text
UniqueTrxID:     trx_example_image_no_face
Filename:        landscape.jpg
ContentType:     image/jpeg
Status:          rejected
StatusCode:      6
Billable:        true
RiskScore:       nil
RiskLevel:       nil
Message:         No face detected in the image
AIThreatSignals: []
Scored()=false  Rejected()=true  HighRisk()=false
```

```text
UniqueTrxID:     trx_example_image_multiple_faces
Filename:        group_photo.jpg
ContentType:     image/jpeg
Status:          rejected
StatusCode:      7
Billable:        true
RiskScore:       nil
RiskLevel:       nil
Message:         Multiple faces detected in the image
AIThreatSignals: []
Scored()=false  Rejected()=true  HighRisk()=false
```

Input-quality and security failures are returned as non-billable business rejections,
normally over HTTP 400; they are returned as results, not as a `*ValidationError`,
because the request reached the API:

```text
UniqueTrxID:     trx_example_image_quality
Filename:        blurry.jpg
ContentType:     image/jpeg
Status:          rejected
StatusCode:      2
Billable:        false
RiskScore:       nil
RiskLevel:       nil
Message:         Image is too blurry for analysis
AIThreatSignals: []
Scored()=false  Rejected()=true  HighRisk()=false
```

For a rejection, show the message to the caller where appropriate and request corrected
media. Do not retry unchanged media.

### Video outcomes

Video and audio are separate modalities. Either modality can have a different risk level.
The API does not return a combined risk score.

Representative result with both modalities:

```text
UniqueTrxID:     trx_example_video_modalities
Filename:        voice_clone.mp4
ContentType:     video/mp4
Status:          success
StatusCode:      1
Billable:        true
VideoRiskScore:  2.2
VideoRiskLevel:  low
VideoMessage:    Not likely to be AI-generated
AudioRiskScore:  8.4
AudioRiskLevel:  high
AudioMessage:    Likely to be AI-generated
AIThreatSignals: [Face Swap Detection Audio Frequency Analysis]
Scored()=true  Rejected()=false  HasAudio()=true  OverallRiskScore()=8.4
```

A video without an audio track can still be successfully scored:

```text
UniqueTrxID:     trx_example_video_silent
Filename:        silent_clip.mp4
ContentType:     video/mp4
Status:          success
StatusCode:      1
Billable:        true
VideoRiskScore:  2.1
VideoRiskLevel:  low
VideoMessage:    Not likely to be AI-generated
AudioRiskScore:  nil
AudioRiskLevel:  nil
AudioMessage:    No audio track detected
AIThreatSignals: [Frame-Level Visual Analysis]
Scored()=true  Rejected()=false  HasAudio()=false  OverallRiskScore()=2.1
```

Multi-face sampled frames are skipped. If no sampled frame contains exactly one scorable
face, the response uses the same no-face rejection shape and audio is not scored:

```text
UniqueTrxID:     trx_example_video_no_face
Filename:        non_face_video.mp4
ContentType:     video/mp4
Status:          rejected
StatusCode:      6
Billable:        true
VideoRiskScore:  nil
VideoRiskLevel:  nil
VideoMessage:    No face detected in the video. The video could not be scored, so no risk scores are provided, including for audio.
AudioRiskScore:  nil
AudioRiskLevel:  nil
AudioMessage:    nil
AIThreatSignals: []
Scored()=false  Rejected()=true  HasAudio()=false  OverallRiskScore()=nil
```

Video format, size, and security failures are similarly returned as non-billable
`StatusCode` 2 rejections with `nil` modality fields.

## API reference

The full generated reference is on
[pkg.go.dev](https://pkg.go.dev/github.com/Neural-Defend/NeuralDefend-SDKs/packages/go).

### `NewClient(opts ClientOptions) (*Client, error)`

```go
type ClientOptions struct {
	APIKey              string
	BaseURL             string
	AllowCustomBaseURL  bool
	AllowHTTPForTesting bool
	Timeout             time.Duration
	MaxRetries          *int
	HTTPClient          *http.Client
	UserAgent           string
	Sleep               func(time.Duration)
	Random              func() float64
	Clock               func() time.Time
}
```

| Option | Default | Description |
|---|---|---|
| `APIKey` | `NEURALDEFEND_API_KEY` | API key. Surrounding whitespace is trimmed; an empty value falls back to the environment variable. A missing key returns a `*ValidationError`. |
| `BaseURL` | `NEURALDEFEND_BASE_URL`, then `https://deepscan.neuraldefend.com` | API origin only: no credentials, path, query, or fragment. Must use HTTPS. |
| `AllowCustomBaseURL` | `false` | Explicit opt-in for a non-Neural Defend origin. That origin receives the API key and uploaded media. |
| `AllowHTTPForTesting` | `false` | Permits an `http://` origin for local tests. |
| `Timeout` | `120 * time.Second` | Per-attempt HTTP timeout. Zero means the default; a negative value returns a `*ValidationError`. |
| `MaxRetries` | `3` (when `nil`) | Automatic retries for HTTP 429/500/503, from `0` through `3`. A pointer so that `0` can be set explicitly. The default allows four total HTTP attempts. |
| `HTTPClient` | SDK-built client | Custom `*http.Client`, intended for controlled testing. |
| `UserAgent` | `neuraldefend-go/1.0.0` | Custom `User-Agent` header. |
| `Sleep`, `Random`, `Clock` | `time.Sleep`, built-in jitter source, current UTC time | Hooks used by the SDK's deterministic retry tests. Leave them unset in applications. |

Notes on `HTTPClient`: the SDK uses a supplied client as-is, so the `Timeout` option and
the SDK's no-redirect policy are **not** applied to it; configure both yourself.
Supplying `HTTPClient` (or setting `AllowHTTPForTesting`) also permits `http://` origins
and lifts the custom-origin check, so only do this in tests or with an origin you trust.

Without a custom `HTTPClient`, redirects are never followed, and the API key is redacted
from SDK-generated error details and from `Raw`.

Configuration precedence:

1. `APIKey`, then `NEURALDEFEND_API_KEY`; there is no default key.
2. `BaseURL`, then `NEURALDEFEND_BASE_URL`, then the production origin.
3. All other options use only their explicit value or documented default; they have no
   environment-variable fallback.

`client.BaseURL()` returns the origin the client actually uses.

### `NewStagingClient(opts ClientOptions) (*Client, error)`

Creates a client pinned to `https://stage.deepscan.neuraldefend.com`. It overrides both
`opts.BaseURL` and `NEURALDEFEND_BASE_URL`. `APIKey` still falls back to
`NEURALDEFEND_API_KEY`; all other options work as in `NewClient`. Use staging only with a
staging credential supplied during onboarding.

### `DetectImage`

```go
func (c *Client) DetectImage(ctx context.Context, media Media) (ImageResult, error)
```

Uploads an image to `/detect/image`. Local validation failures return a
`*ValidationError` before any request is sent.

### `DetectVideo`

```go
func (c *Client) DetectVideo(ctx context.Context, media Media, opts VideoOptions) (VideoResult, error)

type VideoOptions struct {
	MaxFrames  *int
	SampleRate *int
}
```

- `MaxFrames`: optional maximum number of frames to sample, from `1` through `100`. When
  `nil`, the API default is 12.
- `SampleRate`: optional sampling override; must be at least `1`. The SDK and published
  API contract specify no upper bound.

Pass `neuraldefend.VideoOptions{}` to use the service defaults. Out-of-range values
return a `*ValidationError`.

### Building `Media`

| Constructor | Use it for |
|---|---|
| `FileMedia(path string) Media` | A file on disk. The upload name is the file's base name. |
| `BytesMedia(name string, data []byte) Media` | Bytes already in memory. `name` is required. |
| `ReaderMedia(name string, r io.Reader, size int64) Media` | Any `io.Reader`. `name` is required. Pass the size, or `-1` for a stream that cannot rewind. |

### Other exported values

| Name | Value / purpose |
|---|---|
| `Version` | `"1.0.0"` |
| `PRODUCTION_URL` | `"https://deepscan.neuraldefend.com"` |
| `STAGING_URL` | `"https://stage.deepscan.neuraldefend.com"` |
| `IMAGE_MAX_BYTES` | `10485760` (10 MiB) |
| `VIDEO_MAX_BYTES` | `1500000000` |
| `ImageExtensions`, `VideoExtensions` | `map[string]struct{}` of supported extensions, with the leading dot |
| `MIMEForFilename(filename string) string` | The MIME type the SDK sends for a filename |

There is no `Close` method: the client has no resources you must release. Create one
client at startup and reuse it.

## Input types and stream lifecycle

### Paths (`FileMedia`)

Paths are opened and streamed rather than loaded into memory. The SDK checks that the
target exists, is a regular non-empty file, and is within the endpoint limit, rewinds the
file for every retry, and closes it when the detection call returns.

### Bytes (`BytesMedia`)

```go
result, err := client.DetectImage(ctx, neuraldefend.BytesMedia("selfie.jpg", imageBytes))
```

Bytes are held in memory and replayed safely for retries. Empty or oversized values, and
a missing name, are rejected locally.

### Readers (`ReaderMedia`)

```go
result, err := client.DetectImage(ctx, neuraldefend.ReaderMedia("selfie.jpg", reader, size))
```

- **Seekable readers** (the reader implements `io.ReadSeeker` and `size` is `0` or more,
  for example `*bytes.Reader`, `*os.File`, or `multipart.File`): the SDK measures the
  real size, checks it against the limit, and rewinds to byte zero before the first
  request and every retry.
- **Non-seekable readers** (any other reader, or `size` of `-1`): the stream is read once
  and checked against the byte limit while it is uploaded. The client must be built with
  `MaxRetries` set to `0`, otherwise the call returns
  `non-seekable streams require max_retries=0`.
- **Closing:** if the reader also implements `io.Closer`, the SDK closes it when the
  detection call returns. Do not reuse such a reader afterwards.

The name controls multipart metadata and the MIME type. Known extensions receive the MIME
types below. An unknown extension is sent as `application/octet-stream` without a
warning; the server still inspects the actual content.

## Supported media and limits

Image uploads have an exact maximum of 10 MiB (`10,485,760` bytes, `IMAGE_MAX_BYTES`):

- `.jpg`, `.jpeg` — `image/jpeg`
- `.png` — `image/png`
- `.bmp` — `image/bmp`
- `.tif`, `.tiff` — `image/tiff`
- `.webp` — `image/webp`
- `.heic` — `image/heic`
- `.heif` — `image/heif`

Images must be at least 224 × 224 pixels and contain exactly one face for scoring. EXIF
orientation is handled by the service. No-face and multiple-face images are rejected as
described above.

Video uploads have an exact maximum of `1,500,000,000` bytes (`VIDEO_MAX_BYTES`):

- `.mp4` — `video/mp4`
- `.avi` — `video/vnd.avi`
- `.mov` — `video/quicktime`
- `.mkv` — `video/matroska`
- `.wmv` — `video/x-ms-wmv`
- `.flv` — `video/x-flv`
- `.webm` — `video/webm`
- `.ogg`, `.ogv` — `video/ogg`

The service samples 12 frames by default (`MaxFrames` 1–100). A sampled frame must
contain one face to be scorable; multi-face frames are skipped. If no scorable
single-face frame remains, the entire request is rejected and audio is not scored.

## Errors

Every SDK error is a pointer to one of the types below. Each has `Detail`, `StatusCode`,
and `RequestID` fields (filled where available), and `Error()` returns `Detail`. The
types are independent of each other (there is no parent type), so match each one you
care about with `errors.As` or a type switch.

| Type | When |
|---|---|
| `*ValidationError` | Invalid local configuration or input: missing key, unreadable path, missing name, empty or oversized file, out-of-range option, non-seekable stream with retries enabled. No HTTP request is made. |
| `*AuthenticationError` | HTTP 401: the key is invalid, expired, or inactive. |
| `*ScopeError` | HTTP 403: the key lacks access to the requested endpoint. |
| `*RateLimitError` | HTTP 429 after the configured retries. Also has `RetryAfter *float64` (seconds), `Limit`, `Remaining`, and `Reset` (from the `X-RateLimit-*` headers). |
| `*ServerError` | An API error envelope, including final HTTP 500/503 responses and any response whose envelope status is `"error"` (even with HTTP 200). `Envelope` holds the sanitized error envelope when available. |
| `*TimeoutError` | An HTTP timeout or a missed context deadline. Not retried automatically. |
| `*NetworkError` | A non-timeout transport failure, including a cancelled context. Not retried automatically. |
| `*ProtocolError` | The response was not valid JSON or did not match the required NeuroVerify envelope. A malformed final HTTP 500/503 is still a `*ServerError`. |
| `*HttpError` | Any other unclassified HTTP status. |

`RequestID` comes from the `X-Request-ID` response header, or from the transaction ID in
the response when the header is absent.

Do not confuse a returned business rejection with an error. HTTP 400 quality or security
rejections that have the documented score envelope return a result with `err == nil` so
your application can inspect the API's message and `Billable` value.

The SDK's error details are plain strings and do not wrap the underlying cause, so
`errors.Is(err, context.Canceled)` does not match; check `ctx.Err()` instead, as in
[example 11](#11-set-a-deadline-or-cancel-a-check).

## Retries, billability, and idempotency

The SDK retries only HTTP 429, 500, and 503:

- HTTP 429 honors a valid `Retry-After` value in seconds or as an HTTP date, capped at
  3,600 seconds. If the header is absent or invalid, waits are 1, 2, and 4 seconds.
- HTTP 500/503 waits are 1, 2, and 4 seconds plus up to 25% jitter.
- HTTP 400, 401, 403, other HTTP statuses, timeouts, and network failures are not retried.
- `MaxRetries` of `0` disables retries; `3` allows up to four total attempts.

Requests are not idempotent. Every accepted attempt receives a new `UniqueTrxID`, and
retries or manual resubmission may create separate billable transactions. A timeout or
network failure can leave billability unknown because the client may not have received
the server response. Preserve returned transaction IDs for audit, support, and billing
correlation, and avoid adding another retry layer without accounting for the SDK's own
attempts.

`Billable` describes the returned transaction only. A successful score is normally
billable; no-face and face-policy rejections can also be billable. Input validation and
security rejections are normally non-billable. Always use the actual returned value.

## Privacy and security

- Upload media only with the data owner's authorization and an appropriate legal basis.
- Treat images, video, audio, filenames, and diagnostics as potentially biometric or
  otherwise sensitive personal data.
- Apply your organization's consent, residency, encryption, retention, deletion,
  access-control, and audit requirements.
- Keep API keys in a secret manager or server-side environment. Rotate a key if exposure
  is suspected.
- Do not send a production key or customer media to an untrusted `BaseURL`.
  `AllowCustomBaseURL: true` is a deliberate trust decision.
- The SDK's own HTTP client does not follow redirects, so credentials and media are not
  forwarded to another origin. If you supply `HTTPClient`, set its `CheckRedirect` to
  keep that protection.
- Minimize production logging. Prefer transaction IDs and status fields over filenames,
  `Raw`, media bytes, headers, or keys.
- Do not disguise content with a different extension; the server performs format and
  security validation.

Report suspected vulnerabilities privately to `support@neuraldefend.com`; do not include
real credentials or customer media in the report.

## Troubleshooting

**`api_key is required (pass it explicitly or set NEURALDEFEND_API_KEY)`**

Set `NEURALDEFEND_API_KEY` in the same environment that starts your program, or pass a
non-empty `APIKey` from a secret provider.

**HTTP 401 / `*AuthenticationError`**

Verify that the selected key is current and belongs to the intended environment. A
non-empty `APIKey` option overrides the environment variable.

**HTTP 403 / `*ScopeError`**

The key does not have access to the endpoint. Request the required image or video scope
during onboarding.

**`filename is required when uploading bytes` / `filename is required for a nameless file-like object`**

Pass a non-empty name such as `"photo.jpg"` or `"clip.mp4"` to `BytesMedia` or
`ReaderMedia`.

**`non-seekable streams require max_retries=0`**

Build the client with `MaxRetries` pointing to `0`, pass a seekable reader with a size of
`0` or more, or upload from a path. A non-seekable stream cannot be replayed safely.

**`file path does not exist or is not readable` / `file must not be empty` / `file exceeds the endpoint size limit`**

Check the path, the file's contents, and the [size limits](#supported-media-and-limits).

**`a non-Neural Defend base_url requires allow_custom_base_url=true ...`**

`BaseURL` or `NEURALDEFEND_BASE_URL` points somewhere other than the production or
staging origin. Unset it, or set `AllowCustomBaseURL: true` only for an origin you trust.

**`max_frames must be at most 100` / `... must be an integer of at least 1`**

Keep `MaxFrames` within 1–100 and `SampleRate` at 1 or more, or leave them `nil`.

**Unsupported extension**

Use a documented extension matching the real content. The request is still sent as
`application/octet-stream`, and the API may reject it after content inspection.

**HTTP 200 but no score**

Inspect `Status`, `StatusCode`, and the result message. No-face and face-policy outcomes
are expected business rejections, not transport success indicators.

**No audio score**

Check `HasAudio()` and `AudioMessage`. `"No audio track detected"` means video scoring
succeeded without an audio modality. A no-face video rejection suppresses both modalities.

**Repeated 429**

Inspect the `*RateLimitError` fields, reduce concurrency, and confirm tenant limits with
your account manager. The SDK has already exhausted its configured retries when the
error is returned.

**Timeout or network failure**

Confirm egress, DNS, TLS interception, proxy behavior, the `Timeout` option, and any
context deadline. These failures are not retried automatically because the server may
already have accepted a billable request.

**Nil pointer panic when printing a score**

`RiskScore`, `RiskLevel`, and the video/audio equivalents are `nil` when that value was
not scored. Check `Scored()` (or the pointer itself) before dereferencing.

**Security or quality rejection**

Do not retry the same media. Correct the format, dimensions, quality, face count, or
security issue indicated by the result message, then submit only if a new request is
appropriate.

## Wire-level API documentation

For the exhaustive HTTP envelopes, status codes, risk-band descriptions, messages,
billability scenarios, and request examples, see:

- [Unified Face Authenticity Score](../../docs/client/unified-face-authenticity.md)
- [Unified Video Authenticity Score](../../docs/client/unified-video-authenticity.md)

The wire API uses an outer endpoint-specific envelope and `"Y"`/`"N"` billing strings.
The Go SDK intentionally maps those details onto `ImageResult` and `VideoResult`.

## Support

Technical support: `support@neuraldefend.com`

When requesting help, provide the SDK version (`neuraldefend.Version`), endpoint,
`RequestID` or `UniqueTrxID`, and a sanitized reproduction. Do not send API keys, raw
customer media, or biometric/personal data.

## License

MIT — see [LICENSE](LICENSE).
