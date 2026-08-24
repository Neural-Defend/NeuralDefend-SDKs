package neuraldefend_test

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

func testClient(t *testing.T, handler http.HandlerFunc, opts neuraldefend.ClientOptions) *neuraldefend.Client {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)

	opts.APIKey = "secret-test-key"
	opts.BaseURL = server.URL
	opts.AllowCustomBaseURL = true
	opts.AllowHTTPForTesting = true
	if opts.HTTPClient == nil {
		opts.HTTPClient = server.Client()
	}
	client, err := neuraldefend.NewClient(opts)
	if err != nil {
		t.Fatalf("new client: %v", err)
	}
	return client
}

func TestRetries500ThreeTimesWithBackoffAndRewinds(t *testing.T) {
	failure := loadCase(t, "image/documented/internal-error-500.json")
	success := loadCase(t, "image/documented/low-risk.json")
	calls := 0
	sleeps := []time.Duration{}

	handler := func(w http.ResponseWriter, r *http.Request) {
		calls++
		_, _ = io.ReadAll(r.Body)
		caseData := failure
		if calls > 3 {
			caseData = success
		}
		status, headers, body := responseFromCase(caseData)
		for key, values := range headers {
			for _, value := range values {
				w.Header().Add(key, value)
			}
		}
		w.WriteHeader(status)
		_, _ = w.Write(body)
	}

	maxRetries := 3
	client := testClient(t, handler, neuraldefend.ClientOptions{
		MaxRetries: &maxRetries,
		Sleep:      func(d time.Duration) { sleeps = append(sleeps, d) },
		Random:     func() float64 { return 0 },
	})

	stream := bytes.NewReader([]byte("streamed-payload"))
	result, err := client.DetectImage(context.Background(), neuraldefend.ReaderMedia("retry.jpg", stream, int64(stream.Len())))
	if err != nil {
		t.Fatalf("detect image: %v", err)
	}
	if !result.Scored() {
		t.Fatalf("expected scored result")
	}
	if calls != 4 {
		t.Fatalf("calls=%d want 4", calls)
	}
	if len(sleeps) != 3 || sleeps[0] != time.Second || sleeps[1] != 2*time.Second || sleeps[2] != 4*time.Second {
		t.Fatalf("unexpected sleeps: %v", sleeps)
	}
}

func Test429HonorsRetryAfterThenSucceeds(t *testing.T) {
	limited := loadCase(t, "image/synthetic/rate-limited-429.json")
	success := loadCase(t, "image/documented/low-risk.json")
	calls := 0
	sleeps := []time.Duration{}

	handler := func(w http.ResponseWriter, r *http.Request) {
		calls++
		_, _ = io.ReadAll(r.Body)
		caseData := limited
		if calls > 1 {
			caseData = success
		}
		status, headers, body := responseFromCase(caseData)
		for key, values := range headers {
			for _, value := range values {
				w.Header().Add(key, value)
			}
		}
		w.WriteHeader(status)
		_, _ = w.Write(body)
	}

	maxRetries := 1
	client := testClient(t, handler, neuraldefend.ClientOptions{
		MaxRetries: &maxRetries,
		Sleep:      func(d time.Duration) { sleeps = append(sleeps, d) },
	})

	result, err := client.DetectImage(context.Background(), neuraldefend.BytesMedia("x.jpg", []byte("x")))
	if err != nil {
		t.Fatalf("detect image: %v", err)
	}
	if !result.Scored() {
		t.Fatalf("expected scored result")
	}
	if calls != 2 {
		t.Fatalf("calls=%d want 2", calls)
	}
	if len(sleeps) != 1 || sleeps[0] != 60*time.Second {
		t.Fatalf("unexpected sleeps: %v", sleeps)
	}
}

func TestEnvironmentFallback(t *testing.T) {
	t.Setenv("NEURALDEFEND_API_KEY", "environment-key")
	t.Setenv("NEURALDEFEND_BASE_URL", "https://environment.local")

	client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{
		AllowCustomBaseURL: true,
		MaxRetries:         intPtr(0),
	})
	if err != nil {
		t.Fatalf("new client: %v", err)
	}
	if !strings.Contains(client.BaseURL(), "environment.local") {
		t.Fatalf("expected environment base url")
	}
}

func TestStagingIsDeterministic(t *testing.T) {
	t.Setenv("NEURALDEFEND_BASE_URL", "https://wrong.local")
	client, err := neuraldefend.NewStagingClient(neuraldefend.ClientOptions{APIKey: "key", MaxRetries: intPtr(0)})
	if err != nil {
		t.Fatalf("new staging client: %v", err)
	}
	if client.BaseURL() != neuraldefend.STAGING_URL {
		t.Fatalf("expected staging url")
	}
}

func TestCustomBaseURLRequiresExplicitOptIn(t *testing.T) {
	_, err := neuraldefend.NewClient(neuraldefend.ClientOptions{APIKey: "key", BaseURL: "https://api.example.com"})
	if _, ok := err.(*neuraldefend.ValidationError); !ok {
		t.Fatalf("expected ValidationError, got %v", err)
	}

	client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{
		APIKey:             "key",
		BaseURL:            "https://api.example.com",
		AllowCustomBaseURL: true,
		MaxRetries:         intPtr(0),
	})
	if err != nil {
		t.Fatalf("new client: %v", err)
	}
	if !strings.Contains(client.BaseURL(), "api.example.com") {
		t.Fatalf("expected custom base url")
	}
}

func TestConstructorValidation(t *testing.T) {
	cases := []struct {
		opts neuraldefend.ClientOptions
		want string
	}{
		{neuraldefend.ClientOptions{APIKey: ""}, "api_key"},
		{neuraldefend.ClientOptions{APIKey: "key", Timeout: -time.Second}, "timeout"},
		{neuraldefend.ClientOptions{APIKey: "key", MaxRetries: intPtr(-1)}, "max_retries"},
		{neuraldefend.ClientOptions{APIKey: "key", MaxRetries: intPtr(4)}, "max_retries"},
		{neuraldefend.ClientOptions{APIKey: "key", BaseURL: "https://example.com/api"}, "origin"},
	}
	for _, tc := range cases {
		_, err := neuraldefend.NewClient(tc.opts)
		if err == nil {
			t.Fatalf("expected error containing %q", tc.want)
		}
		if !strings.Contains(err.Error(), tc.want) {
			t.Fatalf("expected %q in %v", tc.want, err)
		}
	}
}

func TestVideoQueryParameters(t *testing.T) {
	success := loadCase(t, "video/documented/both-low.json")
	handler := func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.ReadAll(r.Body)
		if r.URL.Query().Get("max_frames") != "100" || r.URL.Query().Get("sample_rate") != "1" {
			t.Fatalf("unexpected query: %s", r.URL.RawQuery)
		}
		status, headers, body := responseFromCase(success)
		for key, values := range headers {
			for _, value := range values {
				w.Header().Add(key, value)
			}
		}
		w.WriteHeader(status)
		_, _ = w.Write(body)
	}

	maxRetries := 0
	client := testClient(t, handler, neuraldefend.ClientOptions{MaxRetries: &maxRetries})
	maxFrames := 100
	sampleRate := 1
	result, err := client.DetectVideo(context.Background(), neuraldefend.BytesMedia("x.mp4", []byte("x")), neuraldefend.VideoOptions{
		MaxFrames:  &maxFrames,
		SampleRate: &sampleRate,
	})
	if err != nil {
		t.Fatalf("detect video: %v", err)
	}
	if !result.Scored() {
		t.Fatalf("expected scored result")
	}
}

func TestPathValidationAndStreaming(t *testing.T) {
	dir := t.TempDir()
	empty := filepath.Join(dir, "empty.jpg")
	if err := os.WriteFile(empty, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	folder := filepath.Join(dir, "folder.jpg")
	if err := os.Mkdir(folder, 0o755); err != nil {
		t.Fatal(err)
	}
	valid := filepath.Join(dir, "valid.jpg")
	if err := os.WriteFile(valid, []byte("path-content"), 0o644); err != nil {
		t.Fatal(err)
	}

	success := loadCase(t, "image/documented/low-risk.json")
	var bodies [][]byte
	handler := func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		bodies = append(bodies, body)
		status, headers, payload := responseFromCase(success)
		for key, values := range headers {
			for _, value := range values {
				w.Header().Add(key, value)
			}
		}
		w.WriteHeader(status)
		_, _ = w.Write(payload)
	}

	maxRetries := 0
	client := testClient(t, handler, neuraldefend.ClientOptions{MaxRetries: &maxRetries})
	for _, invalid := range []string{empty, folder, filepath.Join(dir, "missing.jpg")} {
		if _, err := client.DetectImage(context.Background(), neuraldefend.FileMedia(invalid)); err == nil {
			t.Fatalf("expected validation error for %s", invalid)
		}
	}
	result, err := client.DetectImage(context.Background(), neuraldefend.FileMedia(valid))
	if err != nil {
		t.Fatalf("detect image: %v", err)
	}
	if !result.Scored() {
		t.Fatalf("expected scored result")
	}
	if len(bodies) == 0 || !bytes.Contains(bodies[0], []byte("path-content")) {
		t.Fatalf("expected uploaded path content")
	}
}

func TestNonSeekableRequiresRetriesDisabled(t *testing.T) {
	maxRetries := 3
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}, neuraldefend.ClientOptions{MaxRetries: &maxRetries})

	reader := &nonSeekable{value: []byte("x")}
	if _, err := client.DetectImage(context.Background(), neuraldefend.ReaderMedia("x.jpg", reader, -1)); err == nil {
		t.Fatalf("expected validation error")
	} else if !strings.Contains(err.Error(), "max_retries=0") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestDeterministicMIMEForDocumentedFormats(t *testing.T) {
	cases := map[string]string{
		"photo.jpg":   "image/jpeg",
		"photo.heif":  "image/heif",
		"clip.mp4":    "video/mp4",
		"unknown.xyz": "application/octet-stream",
	}
	for filename, expected := range cases {
		if got := neuraldefend.MIMEForFilename(filename); got != expected {
			t.Fatalf("%s: got %q want %q", filename, got, expected)
		}
	}
}

func TestErrorEnvelopeOnHTTP200RaisesServerError(t *testing.T) {
	caseData := loadCase(t, "image/documented/internal-error-500.json")
	raw, _ := json.Marshal(caseData)
	var decoded map[string]any
	_ = json.Unmarshal(raw, &decoded)
	decoded["http_status"] = float64(200)
	body := decoded["body"].(map[string]any)
	score := body["unified_face_authenticity_score"].(map[string]any)
	score["message"] = "failed for secret-test-key"
	score["future"] = map[string]any{"echo": "secret-test-key"}

	handler := func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.ReadAll(r.Body)
		status, headers, payload := responseFromCase(decoded)
		for key, values := range headers {
			for _, value := range values {
				w.Header().Add(key, value)
			}
		}
		w.WriteHeader(status)
		_, _ = w.Write(payload)
	}

	maxRetries := 0
	client := testClient(t, handler, neuraldefend.ClientOptions{MaxRetries: &maxRetries})
	_, err := client.DetectImage(context.Background(), neuraldefend.BytesMedia("x.jpg", []byte("x")))
	serverErr, ok := err.(*neuraldefend.ServerError)
	if !ok {
		t.Fatalf("expected ServerError, got %T", err)
	}
	if strings.Contains(serverErr.Error(), "secret-test-key") {
		t.Fatalf("api key was not redacted")
	}
}

type nonSeekable struct {
	value  []byte
	offset int
}

func (n *nonSeekable) Read(p []byte) (int, error) {
	if n.offset >= len(n.value) {
		return 0, io.EOF
	}
	nCopied := copy(p, n.value[n.offset:])
	n.offset += nCopied
	return nCopied, nil
}

func intPtr(v int) *int { return &v }
