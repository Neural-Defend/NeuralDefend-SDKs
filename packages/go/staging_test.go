package neuraldefend_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

func TestStagingImageContract(t *testing.T) {
	apiKey := os.Getenv("NEURALDEFEND_STAGING_API_KEY")
	if apiKey == "" {
		t.Skip("NEURALDEFEND_STAGING_API_KEY is not configured")
	}
	path := stagingFixture(t, "NEURALDEFEND_STAGING_IMAGE")

	maxRetries := 0
	client, err := neuraldefend.NewStagingClient(neuraldefend.ClientOptions{
		APIKey:     apiKey,
		MaxRetries: &maxRetries,
	})
	if err != nil {
		t.Fatalf("new staging client: %v", err)
	}

	result, err := client.DetectImage(context.Background(), neuraldefend.FileMedia(path))
	if err != nil {
		t.Fatalf("detect image: %v", err)
	}
	assertConsistentResult(t, result.Status, result.UniqueTrxID, result.Billable, result.Scored(), result.Rejected())
}

func TestStagingVideoContract(t *testing.T) {
	apiKey := os.Getenv("NEURALDEFEND_STAGING_API_KEY")
	if apiKey == "" {
		t.Skip("NEURALDEFEND_STAGING_API_KEY is not configured")
	}
	path := stagingFixture(t, "NEURALDEFEND_STAGING_VIDEO")

	maxRetries := 0
	client, err := neuraldefend.NewStagingClient(neuraldefend.ClientOptions{
		APIKey:     apiKey,
		MaxRetries: &maxRetries,
	})
	if err != nil {
		t.Fatalf("new staging client: %v", err)
	}

	maxFrames := 2
	result, err := client.DetectVideo(context.Background(), neuraldefend.FileMedia(path), neuraldefend.VideoOptions{
		MaxFrames: &maxFrames,
	})
	if err != nil {
		t.Fatalf("detect video: %v", err)
	}
	assertConsistentResult(t, result.Status, result.UniqueTrxID, result.Billable, result.Scored(), result.Rejected())
	if result.Scored() {
		if result.VideoRiskScore == nil || result.VideoRiskLevel == nil {
			t.Fatalf("expected video score fields")
		}
		switch *result.VideoRiskLevel {
		case "low", "medium", "high":
		default:
			t.Fatalf("unexpected video risk level %q", *result.VideoRiskLevel)
		}
	}
}

func stagingFixture(t *testing.T, envName string) string {
	t.Helper()
	value := os.Getenv(envName)
	if value == "" {
		t.Fatalf("%s is not configured", envName)
	}
	info, err := os.Stat(value)
	if err != nil || info.IsDir() {
		t.Fatalf("%s does not identify a staging fixture", envName)
	}
	return filepath.Clean(value)
}

func assertConsistentResult(t *testing.T, status, trxID string, billable, scored, rejected bool) {
	t.Helper()
	switch status {
	case "success", "rejected":
	default:
		t.Fatalf("unexpected status %q", status)
	}
	if trxID == "" {
		t.Fatalf("expected transaction id")
	}
	if scored != (status == "success") {
		t.Fatalf("scored mismatch")
	}
	if rejected != (status == "rejected") {
		t.Fatalf("rejected mismatch")
	}
	_ = billable
}
