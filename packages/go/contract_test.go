package neuraldefend_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

var fixturesRoot = filepath.Clean(filepath.Join("..", "..", "tests", "fixtures"))

func loadCase(t *testing.T, relativePath string) map[string]any {
	t.Helper()
	path := filepath.Join(fixturesRoot, relativePath)
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read fixture %s: %v", relativePath, err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(raw, &decoded); err != nil {
		t.Fatalf("decode fixture %s: %v", relativePath, err)
	}
	return decoded
}

func responseFromCase(caseData map[string]any) (int, http.Header, []byte) {
	status := int(caseData["http_status"].(float64))
	headers := http.Header{}
	if rawHeaders, ok := caseData["headers"].(map[string]any); ok {
		for key, value := range rawHeaders {
			headers.Set(key, value.(string))
		}
	}
	if caseData["body_kind"] == "raw" {
		switch body := caseData["body"].(type) {
		case string:
			return status, headers, []byte(body)
		default:
			encoded, _ := json.Marshal(body)
			return status, headers, encoded
		}
	}
	body, _ := json.Marshal(caseData["body"])
	return status, headers, body
}

func clientForCase(t *testing.T, caseData map[string]any) *neuraldefend.Client {
	t.Helper()
	status, headers, body := responseFromCase(caseData)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ioReadAll(r.Body)
		for key, values := range headers {
			for _, value := range values {
				w.Header().Add(key, value)
			}
		}
		w.WriteHeader(status)
		_, _ = w.Write(body)
	}))
	t.Cleanup(server.Close)

	maxRetries := 0
	client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{
		APIKey:              "test-key",
		BaseURL:             server.URL,
		AllowCustomBaseURL:  true,
		AllowHTTPForTesting: true,
		MaxRetries:          &maxRetries,
		HTTPClient:          server.Client(),
	})
	if err != nil {
		t.Fatalf("new client: %v", err)
	}
	return client
}

func ioReadAll(r interface{ Read([]byte) (int, error) }) []byte {
	buf := make([]byte, 0, 512)
	tmp := make([]byte, 1024)
	for {
		n, err := r.Read(tmp)
		if n > 0 {
			buf = append(buf, tmp[:n]...)
		}
		if err != nil {
			break
		}
	}
	return buf
}

var imageResults = []string{
	"image/documented/low-risk.json",
	"image/documented/medium-risk.json",
	"image/documented/high-risk-spoof.json",
	"image/documented/no-face.json",
	"image/documented/multiple-faces.json",
	"image/documented/nsfw.json",
	"image/documented/blurry.json",
	"image/documented/unsupported-format.json",
	"image/documented/security-rejection.json",
	"image/documented/too-large.json",
}

var videoResults = []string{
	"video/documented/both-low.json",
	"video/documented/video-high-audio-low.json",
	"video/documented/both-high.json",
	"video/documented/video-low-audio-high.json",
	"video/documented/medium-no-audio.json",
	"video/documented/silent-no-audio.json",
	"video/documented/no-face.json",
	"video/documented/multiple-faces.json",
	"video/documented/unsupported-format.json",
	"video/documented/security-rejection.json",
	"video/documented/too-large.json",
}

func TestAllDocumentedImageResults(t *testing.T) {
	for _, fixturePath := range imageResults {
		t.Run(fixturePath, func(t *testing.T) {
			caseData := loadCase(t, fixturePath)
			client := clientForCase(t, caseData)
			result, err := client.DetectImage(context.Background(), neuraldefend.BytesMedia("sample.jpg", []byte("image")))
			if err != nil {
				t.Fatalf("detect image: %v", err)
			}
			body := caseData["body"].(map[string]any)
			wire := body["unified_face_authenticity_score"].(map[string]any)

			assertEqual(t, "status", result.Status, wire["status"])
			assertEqual(t, "status_code", float64(result.StatusCode), wire["status_code"])
			assertEqual(t, "billable", result.Billable, wire["billable"] == "Y")
			if !floatPtrEqual(result.RiskScore, wire["risk_score"]) {
				t.Fatalf("risk_score mismatch")
			}
			if !stringPtrEqual(result.RiskLevel, wire["risk_level"]) {
				t.Fatalf("risk_level mismatch")
			}
			if result.Message == "" {
				t.Fatalf("expected message")
			}
			assertEqual(t, "scored", result.Scored(), wire["status"] == "success")
			assertEqual(t, "rejected", result.Rejected(), wire["status"] == "rejected")
			assertEqual(t, "high_risk", result.HighRisk(), wire["risk_level"] == "high")
		})
	}
}

func TestAllDocumentedVideoResults(t *testing.T) {
	for _, fixturePath := range videoResults {
		t.Run(fixturePath, func(t *testing.T) {
			caseData := loadCase(t, fixturePath)
			client := clientForCase(t, caseData)
			result, err := client.DetectVideo(context.Background(), neuraldefend.BytesMedia("sample.mp4", []byte("video")), neuraldefend.VideoOptions{})
			if err != nil {
				t.Fatalf("detect video: %v", err)
			}
			body := caseData["body"].(map[string]any)
			wire := body["unified_video_authenticity_score"].(map[string]any)

			assertEqual(t, "status", result.Status, wire["status"])
			assertEqual(t, "status_code", float64(result.StatusCode), wire["status_code"])
			assertEqual(t, "billable", result.Billable, wire["billable"] == "Y")
			if !floatPtrEqual(result.VideoRiskScore, wire["video_risk_score"]) {
				t.Fatalf("video_risk_score mismatch")
			}
			if !stringPtrEqual(result.VideoRiskLevel, wire["video_risk_level"]) {
				t.Fatalf("video_risk_level mismatch")
			}
			if !floatPtrEqual(result.AudioRiskScore, wire["audio_risk_score"]) {
				t.Fatalf("audio_risk_score mismatch")
			}
			if !stringPtrEqual(result.AudioRiskLevel, wire["audio_risk_level"]) {
				t.Fatalf("audio_risk_level mismatch")
			}
			assertEqual(t, "has_audio", result.HasAudio(), wire["audio_risk_score"] != nil)

			var expectedScores []float64
			if value, ok := wire["video_risk_score"].(float64); ok {
				expectedScores = append(expectedScores, value)
			}
			if value, ok := wire["audio_risk_score"].(float64); ok {
				expectedScores = append(expectedScores, value)
			}
			var expected *float64
			if len(expectedScores) > 0 {
				max := expectedScores[0]
				for _, score := range expectedScores[1:] {
					if score > max {
						max = score
					}
				}
				expected = &max
			}
			var want any
			if expected != nil {
				want = *expected
			}
			if !floatPtrEqual(result.OverallRiskScore(), want) {
				t.Fatalf("overall_risk_score mismatch: got %v want %v", result.OverallRiskScore(), want)
			}
		})
	}
}

func TestServerErrorEnvelopes(t *testing.T) {
	cases := []struct {
		fixture string
		image   bool
	}{
		{"image/documented/internal-error-500.json", true},
		{"image/documented/service-unavailable-503.json", true},
		{"video/documented/internal-error-500.json", false},
		{"video/documented/service-unavailable-503.json", false},
	}
	for _, tc := range cases {
		t.Run(tc.fixture, func(t *testing.T) {
			caseData := loadCase(t, tc.fixture)
			client := clientForCase(t, caseData)
			var err error
			if tc.image {
				_, err = client.DetectImage(context.Background(), neuraldefend.BytesMedia("x.jpg", []byte("x")))
			} else {
				_, err = client.DetectVideo(context.Background(), neuraldefend.BytesMedia("x.mp4", []byte("x")), neuraldefend.VideoOptions{})
			}
			serverErr, ok := err.(*neuraldefend.ServerError)
			if !ok {
				t.Fatalf("expected ServerError, got %T (%v)", err, err)
			}
			if serverErr.StatusCode != int(caseData["http_status"].(float64)) {
				t.Fatalf("status code mismatch")
			}
			if serverErr.Envelope == nil {
				t.Fatalf("expected envelope")
			}
			if serverErr.RequestID == "" {
				t.Fatalf("expected request id")
			}
		})
	}
}

func TestAuthAndScopeErrors(t *testing.T) {
	cases := []struct {
		fixture  string
		wantType string
	}{
		{"image/synthetic/unauthorized-401.json", "auth"},
		{"video/synthetic/unauthorized-401.json", "auth"},
		{"image/synthetic/forbidden-403.json", "scope"},
		{"video/synthetic/forbidden-403.json", "scope"},
	}
	for _, tc := range cases {
		t.Run(tc.fixture, func(t *testing.T) {
			caseData := loadCase(t, tc.fixture)
			client := clientForCase(t, caseData)
			var err error
			if strings.HasPrefix(tc.fixture, "image/") {
				_, err = client.DetectImage(context.Background(), neuraldefend.BytesMedia("x.jpg", []byte("x")))
			} else {
				_, err = client.DetectVideo(context.Background(), neuraldefend.BytesMedia("x.mp4", []byte("x")), neuraldefend.VideoOptions{})
			}
			body := caseData["body"].(map[string]any)
			switch tc.wantType {
			case "auth":
				authErr, ok := err.(*neuraldefend.AuthenticationError)
				if !ok {
					t.Fatalf("expected AuthenticationError, got %T", err)
				}
				if authErr.Detail != body["detail"] {
					t.Fatalf("detail mismatch")
				}
				if authErr.StatusCode != int(caseData["http_status"].(float64)) {
					t.Fatalf("status code mismatch")
				}
			case "scope":
				scopeErr, ok := err.(*neuraldefend.ScopeError)
				if !ok {
					t.Fatalf("expected ScopeError, got %T", err)
				}
				if scopeErr.Detail != body["detail"] {
					t.Fatalf("detail mismatch")
				}
			}
		})
	}
}

func TestRateLimitErrorHeaders(t *testing.T) {
	for _, fixturePath := range []string{
		"image/synthetic/rate-limited-429.json",
		"video/synthetic/rate-limited-429.json",
	} {
		t.Run(fixturePath, func(t *testing.T) {
			caseData := loadCase(t, fixturePath)
			client := clientForCase(t, caseData)
			var err error
			if strings.HasPrefix(fixturePath, "image/") {
				_, err = client.DetectImage(context.Background(), neuraldefend.BytesMedia("x.jpg", []byte("x")))
			} else {
				_, err = client.DetectVideo(context.Background(), neuraldefend.BytesMedia("x.mp4", []byte("x")), neuraldefend.VideoOptions{})
			}
			rateErr, ok := err.(*neuraldefend.RateLimitError)
			if !ok {
				t.Fatalf("expected RateLimitError, got %T", err)
			}
			if rateErr.RetryAfter == nil || *rateErr.RetryAfter != 60 {
				t.Fatalf("retry_after mismatch")
			}
			if rateErr.Limit != "1000" || rateErr.Remaining != "0" || rateErr.Reset != "2026-07-27T00:00:00Z" {
				t.Fatalf("rate limit headers mismatch")
			}
		})
	}
}

func TestMalformedResponsesRaiseProtocolError(t *testing.T) {
	cases := []struct {
		fixture string
		image   bool
	}{
		{"image/robustness/missing-envelope.json", true},
		{"image/robustness/malformed-json.json", true},
		{"video/robustness/missing-envelope.json", false},
		{"video/robustness/malformed-json.json", false},
	}
	for _, tc := range cases {
		t.Run(tc.fixture, func(t *testing.T) {
			client := clientForCase(t, loadCase(t, tc.fixture))
			var err error
			if tc.image {
				_, err = client.DetectImage(context.Background(), neuraldefend.BytesMedia("x.jpg", []byte("x")))
			} else {
				_, err = client.DetectVideo(context.Background(), neuraldefend.BytesMedia("x.mp4", []byte("x")), neuraldefend.VideoOptions{})
			}
			if _, ok := err.(*neuraldefend.ProtocolError); !ok {
				t.Fatalf("expected ProtocolError, got %T (%v)", err, err)
			}
		})
	}
}

func TestUnknownResponseValuesArePreserved(t *testing.T) {
	cases := []string{
		"image/robustness/unknown-status-code.json",
		"image/robustness/unknown-status.json",
		"image/robustness/unknown-risk-level.json",
		"video/robustness/unknown-status-code.json",
		"video/robustness/unknown-status.json",
		"video/robustness/unknown-risk-level.json",
	}
	for _, fixturePath := range cases {
		t.Run(fixturePath, func(t *testing.T) {
			caseData := loadCase(t, fixturePath)
			client := clientForCase(t, caseData)
			if strings.HasPrefix(fixturePath, "image/") {
				result, err := client.DetectImage(context.Background(), neuraldefend.BytesMedia("x.jpg", []byte("x")))
				if err != nil {
					t.Fatalf("detect image: %v", err)
				}
				wire := caseData["body"].(map[string]any)["unified_face_authenticity_score"].(map[string]any)
				assertEqual(t, "status", result.Status, wire["status"])
				assertEqual(t, "status_code", float64(result.StatusCode), wire["status_code"])
				assertEqual(t, "risk_level", derefString(result.RiskLevel), wire["risk_level"])
				if strings.HasSuffix(fixturePath, "unknown-risk-level.json") && result.Scored() {
					t.Fatalf("expected scored=false")
				}
			} else {
				result, err := client.DetectVideo(context.Background(), neuraldefend.BytesMedia("x.mp4", []byte("x")), neuraldefend.VideoOptions{})
				if err != nil {
					t.Fatalf("detect video: %v", err)
				}
				wire := caseData["body"].(map[string]any)["unified_video_authenticity_score"].(map[string]any)
				assertEqual(t, "status", result.Status, wire["status"])
				assertEqual(t, "status_code", float64(result.StatusCode), wire["status_code"])
				assertEqual(t, "video_risk_level", derefString(result.VideoRiskLevel), wire["video_risk_level"])
				if strings.HasSuffix(fixturePath, "unknown-risk-level.json") && result.Scored() {
					t.Fatalf("expected scored=false")
				}
			}
		})
	}
}

func TestUnknownFieldsArePreservedInRaw(t *testing.T) {
	cases := []struct {
		fixture string
		image   bool
	}{
		{"image/robustness/unknown-extra-field.json", true},
		{"video/robustness/unknown-extra-field.json", false},
	}
	for _, tc := range cases {
		t.Run(tc.fixture, func(t *testing.T) {
			client := clientForCase(t, loadCase(t, tc.fixture))
			var raw map[string]any
			if tc.image {
				result, err := client.DetectImage(context.Background(), neuraldefend.BytesMedia("x.jpg", []byte("x")))
				if err != nil {
					t.Fatalf("detect image: %v", err)
				}
				raw = result.Raw
			} else {
				result, err := client.DetectVideo(context.Background(), neuraldefend.BytesMedia("x.mp4", []byte("x")), neuraldefend.VideoOptions{})
				if err != nil {
					t.Fatalf("detect video: %v", err)
				}
				raw = result.Raw
			}
			future, ok := raw["future_signal"].(map[string]any)
			if !ok {
				t.Fatalf("expected future_signal map")
			}
			if future["confidence"] != 0.42 {
				t.Fatalf("unexpected confidence")
			}
		})
	}
}

func assertEqual(t *testing.T, name string, got, want any) {
	t.Helper()
	if got != want {
		t.Fatalf("%s: got %v want %v", name, got, want)
	}
}

func floatPtrEqual(got *float64, want any) bool {
	if want == nil {
		return got == nil
	}
	if got == nil {
		return false
	}
	value, ok := want.(float64)
	return ok && *got == value
}

func stringPtrEqual(got *string, want any) bool {
	if want == nil {
		return got == nil
	}
	if got == nil {
		return false
	}
	value, ok := want.(string)
	return ok && *got == value
}

func derefString(value *string) any {
	if value == nil {
		return nil
	}
	return *value
}
