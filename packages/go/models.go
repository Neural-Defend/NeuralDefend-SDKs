package neuraldefend

var riskLevels = map[string]struct{}{
	"low":    {},
	"medium": {},
	"high":   {},
}

func isRiskLevel(value string) bool {
	_, ok := riskLevels[value]
	return ok
}

// ImageResult is an image scoring or business-rejection result.
type ImageResult struct {
	UniqueTrxID     string
	Filename        string
	ContentType     string
	Status          string
	StatusCode      int
	Billable        bool
	RiskScore       *float64
	RiskLevel       *string
	Message         string
	AIThreatSignals []string
	Raw             map[string]any
}

// Scored reports whether the result contains a successful risk score.
func (r ImageResult) Scored() bool {
	return r.Status == "success" &&
		r.RiskScore != nil &&
		r.RiskLevel != nil &&
		isRiskLevel(*r.RiskLevel)
}

// Rejected reports whether the API rejected the media without throwing.
func (r ImageResult) Rejected() bool {
	return r.Status == "rejected"
}

// HighRisk reports whether the risk level is high.
func (r ImageResult) HighRisk() bool {
	return r.RiskLevel != nil && *r.RiskLevel == "high"
}

// VideoResult is a video scoring or business-rejection result.
type VideoResult struct {
	UniqueTrxID     string
	Filename        string
	ContentType     string
	Status          string
	StatusCode      int
	Billable        bool
	VideoRiskScore  *float64
	VideoRiskLevel  *string
	VideoMessage    string
	AudioRiskScore  *float64
	AudioRiskLevel  *string
	AudioMessage    *string
	AIThreatSignals []string
	Raw             map[string]any
}

// Scored reports whether both video and audio modalities scored successfully.
func (r VideoResult) Scored() bool {
	videoScored := r.VideoRiskScore != nil && r.VideoRiskLevel != nil && isRiskLevel(*r.VideoRiskLevel)
	audioScored := (r.AudioRiskScore == nil && r.AudioRiskLevel == nil) ||
		(r.AudioRiskScore != nil && r.AudioRiskLevel != nil && isRiskLevel(*r.AudioRiskLevel))
	return r.Status == "success" && videoScored && audioScored
}

// Rejected reports whether the API rejected the media without throwing.
func (r VideoResult) Rejected() bool {
	return r.Status == "rejected"
}

// HasAudio reports whether an audio risk score was returned.
func (r VideoResult) HasAudio() bool {
	return r.AudioRiskScore != nil
}

// OverallRiskScore returns the client-side maximum score; the API has no combined score.
func (r VideoResult) OverallRiskScore() *float64 {
	var scores []float64
	if r.VideoRiskScore != nil {
		scores = append(scores, *r.VideoRiskScore)
	}
	if r.AudioRiskScore != nil {
		scores = append(scores, *r.AudioRiskScore)
	}
	if len(scores) == 0 {
		return nil
	}
	max := scores[0]
	for _, score := range scores[1:] {
		if score > max {
			max = score
		}
	}
	return &max
}
