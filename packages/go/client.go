package neuraldefend

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	// PRODUCTION_URL is the default NeuroVerify API origin.
	PRODUCTION_URL = "https://deepscan.neuraldefend.com"
	// STAGING_URL is the staging NeuroVerify API origin.
	STAGING_URL = "https://stage.deepscan.neuraldefend.com"

	defaultTimeout    = 120 * time.Second
	defaultMaxRetries = 3
	maxRetryAfter     = 3600.0
)

// ClientOptions configures a NeuroVerify client.
type ClientOptions struct {
	APIKey              string
	BaseURL             string
	AllowCustomBaseURL  bool
	AllowHTTPForTesting bool
	Timeout             time.Duration
	// MaxRetries configures automatic retries for 429/500/503 (0-3). Defaults to 3 when nil.
	MaxRetries *int
	HTTPClient *http.Client
	UserAgent  string
	Sleep      func(time.Duration)
	Random     func() float64
	Clock      func() time.Time
}

// Client is the public NeuroVerify API client.
type Client struct {
	baseURL    string
	apiKey     string
	timeout    time.Duration
	maxRetries int
	userAgent  string
	httpClient *http.Client
	sleep      func(time.Duration)
	random     func() float64
	clock      func() time.Time
}

// VideoOptions configures optional video detection query parameters.
type VideoOptions struct {
	MaxFrames  *int
	SampleRate *int
}

// NewClient constructs a client using options and environment fallbacks.
func NewClient(opts ClientOptions) (*Client, error) {
	apiKey := strings.TrimSpace(opts.APIKey)
	if apiKey == "" {
		apiKey = strings.TrimSpace(os.Getenv("NEURALDEFEND_API_KEY"))
	}
	if apiKey == "" {
		return nil, &ValidationError{Detail: "api_key is required (pass it explicitly or set NEURALDEFEND_API_KEY)"}
	}

	timeout := opts.Timeout
	if timeout == 0 {
		timeout = defaultTimeout
	}
	if timeout <= 0 {
		return nil, &ValidationError{Detail: "timeout must be a positive number"}
	}

	maxRetries := defaultMaxRetries
	if opts.MaxRetries != nil {
		maxRetries = *opts.MaxRetries
	}
	if maxRetries < 0 || maxRetries > defaultMaxRetries {
		return nil, &ValidationError{Detail: "max_retries must be an integer from 0 through 3"}
	}

	baseURL := opts.BaseURL
	if baseURL == "" {
		baseURL = os.Getenv("NEURALDEFEND_BASE_URL")
	}
	if baseURL == "" {
		baseURL = PRODUCTION_URL
	}

	allowHTTP := opts.AllowHTTPForTesting || opts.HTTPClient != nil
	baseURL, err := validateBaseURL(baseURL, allowHTTP, opts.AllowCustomBaseURL)
	if err != nil {
		return nil, err
	}

	userAgent := opts.UserAgent
	if userAgent == "" {
		userAgent = fmt.Sprintf("neuraldefend-go/%s", Version)
	}

	httpClient := opts.HTTPClient
	if httpClient == nil {
		httpClient = &http.Client{
			Timeout: timeout,
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				return http.ErrUseLastResponse
			},
		}
	}

	sleep := opts.Sleep
	if sleep == nil {
		sleep = time.Sleep
	}
	random := opts.Random
	if random == nil {
		random = defaultRandom
	}
	clock := opts.Clock
	if clock == nil {
		clock = func() time.Time { return time.Now().UTC() }
	}

	return &Client{
		baseURL:    baseURL,
		apiKey:     apiKey,
		timeout:    timeout,
		maxRetries: maxRetries,
		userAgent:  userAgent,
		httpClient: httpClient,
		sleep:      sleep,
		random:     random,
		clock:      clock,
	}, nil
}

// BaseURL returns the configured API origin.
func (c *Client) BaseURL() string {
	return c.baseURL
}

// NewStagingClient constructs a client pinned to [STAGING_URL].
func NewStagingClient(opts ClientOptions) (*Client, error) {
	opts.BaseURL = STAGING_URL
	return NewClient(opts)
}

// DetectImage analyzes an image upload.
func (c *Client) DetectImage(ctx context.Context, media Media) (ImageResult, error) {
	upload, err := media.withKind(mediaKindImage, IMAGE_MAX_BYTES, imageExtensions())
	if err != nil {
		return ImageResult{}, err
	}
	defer upload.close()

	if upload.unsupported {
		// Unsupported extensions are accepted; the server inspects content.
	}

	resp, err := c.send(ctx, "/detect/image", upload, nil)
	if err != nil {
		return ImageResult{}, err
	}
	defer resp.Body.Close()
	return c.classifyImage(resp)
}

// DetectVideo analyzes a video upload.
func (c *Client) DetectVideo(ctx context.Context, media Media, opts VideoOptions) (VideoResult, error) {
	if err := validateVideoParameter("max_frames", opts.MaxFrames, 100); err != nil {
		return VideoResult{}, err
	}
	if err := validateVideoParameter("sample_rate", opts.SampleRate, 0); err != nil {
		return VideoResult{}, err
	}

	upload, err := media.withKind(mediaKindVideo, VIDEO_MAX_BYTES, videoExtensions())
	if err != nil {
		return VideoResult{}, err
	}
	defer upload.close()

	if upload.seeker == nil && upload.data == nil && c.maxRetries != 0 {
		return VideoResult{}, &ValidationError{Detail: "non-seekable streams require max_retries=0"}
	}

	params := url.Values{}
	if opts.MaxFrames != nil {
		params.Set("max_frames", strconv.Itoa(*opts.MaxFrames))
	}
	if opts.SampleRate != nil {
		params.Set("sample_rate", strconv.Itoa(*opts.SampleRate))
	}

	resp, err := c.send(ctx, "/detect/video", upload, params)
	if err != nil {
		return VideoResult{}, err
	}
	defer resp.Body.Close()
	return c.classifyVideo(resp)
}

func validateBaseURL(value string, allowHTTP, allowCustomBaseURL bool) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", &ValidationError{Detail: "base_url must be a non-empty URL"}
	}
	parsed, err := url.Parse(value)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return "", &ValidationError{Detail: "base_url is invalid"}
	}
	if parsed.RawQuery != "" || parsed.Fragment != "" || parsed.User != nil {
		return "", &ValidationError{Detail: "base_url must be an origin URL without credentials, path, query, or fragment"}
	}
	if parsed.Path != "" && parsed.Path != "/" {
		return "", &ValidationError{Detail: "base_url must be an origin URL without credentials, path, query, or fragment"}
	}
	if parsed.Scheme != "https" && !(allowHTTP && parsed.Scheme == "http") {
		return "", &ValidationError{Detail: "base_url must use HTTPS"}
	}
	origin := strings.TrimRight(parsed.Scheme+"://"+parsed.Host, "/")
	if origin != PRODUCTION_URL && origin != STAGING_URL && !allowCustomBaseURL && !allowHTTP {
		return "", &ValidationError{
			Detail: "a non-Neural Defend base_url requires allow_custom_base_url=true because it receives the API key and uploaded media",
		}
	}
	return origin, nil
}

func validateVideoParameter(name string, value *int, upper int) error {
	if value == nil {
		return nil
	}
	if *value < 1 {
		return &ValidationError{Detail: fmt.Sprintf("%s must be an integer of at least 1", name)}
	}
	if upper > 0 && *value > upper {
		return &ValidationError{Detail: fmt.Sprintf("%s must be at most %d", name, upper)}
	}
	return nil
}

func (c *Client) send(ctx context.Context, path string, upload *preparedUpload, params url.Values) (*http.Response, error) {
	if upload.seeker == nil && upload.data == nil && c.maxRetries != 0 {
		return nil, &ValidationError{Detail: "non-seekable streams require max_retries=0"}
	}

	target, err := url.Parse(c.baseURL + path)
	if err != nil {
		return nil, newNetworkError("invalid request URL")
	}
	if len(params) > 0 {
		target.RawQuery = params.Encode()
	}

	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		body, contentType, err := c.buildMultipart(upload)
		if err != nil {
			return nil, err
		}

		req, err := http.NewRequestWithContext(ctx, http.MethodPost, target.String(), body)
		if err != nil {
			return nil, newNetworkError(c.redact(err.Error()))
		}
		req.Header.Set("Accept", "application/json")
		req.Header.Set("User-Agent", c.userAgent)
		req.Header.Set("x-api-key", c.apiKey)
		req.Header.Set("Content-Type", contentType)

		resp, err := c.httpClient.Do(req)
		if err != nil {
			if isTimeout(err) {
				return nil, newTimeoutError(c.redact(err.Error()))
			}
			return nil, newNetworkError(c.redact(err.Error()))
		}

		if resp.StatusCode != 429 && resp.StatusCode != 500 && resp.StatusCode != 503 || attempt >= c.maxRetries {
			return resp, nil
		}
		_ = resp.Body.Close()
		c.sleep(c.retryDelay(resp, attempt))
	}
	return nil, &ValidationError{Detail: "unreachable retry state"}
}

func (c *Client) buildMultipart(upload *preparedUpload) (io.ReadCloser, string, error) {
	pr, pw := io.Pipe()
	writer := multipart.NewWriter(pw)

	go func() {
		defer pw.Close()
		defer writer.Close()

		reader, err := upload.openAttempt()
		if err != nil {
			_ = pw.CloseWithError(err)
			return
		}

		header := textproto.MIMEHeader{}
		header.Set("Content-Disposition", fmt.Sprintf(`form-data; name="file"; filename="%s"`, upload.filename))
		header.Set("Content-Type", MIMEForFilename(upload.filename))
		part, err := writer.CreatePart(header)
		if err != nil {
			_ = pw.CloseWithError(err)
			return
		}
		if _, err := io.Copy(part, reader); err != nil {
			_ = pw.CloseWithError(err)
			return
		}
	}()

	return pr, writer.FormDataContentType(), nil
}

func (c *Client) retryDelay(resp *http.Response, attempt int) time.Duration {
	if resp.StatusCode == 429 {
		if parsed := c.parseRetryAfter(resp.Header.Get("Retry-After")); parsed != nil {
			return time.Duration(*parsed * float64(time.Second))
		}
		backoff := math.Min(math.Pow(2, float64(attempt)), 4)
		return time.Duration(backoff * float64(time.Second))
	}
	base := math.Min(math.Pow(2, float64(attempt)), 4)
	jitter := math.Max(0, math.Min(1, c.random())) * base * 0.25
	return time.Duration((base + jitter) * float64(time.Second))
}

func (c *Client) parseRetryAfter(value string) *float64 {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	if seconds, err := strconv.ParseFloat(value, 64); err == nil {
		if !math.IsInf(seconds, 0) && !math.IsNaN(seconds) {
			clamped := math.Max(0, math.Min(maxRetryAfter, seconds))
			return &clamped
		}
		return nil
	}
	if when, err := http.ParseTime(value); err == nil {
		seconds := when.Sub(c.clock()).Seconds()
		if math.IsInf(seconds, 0) || math.IsNaN(seconds) {
			return nil
		}
		clamped := math.Max(0, math.Min(maxRetryAfter, seconds))
		return &clamped
	}
	return nil
}

func (c *Client) classifyImage(resp *http.Response) (ImageResult, error) {
	if err := c.raiseSimpleHTTPErrors(resp); err != nil {
		return ImageResult{}, err
	}
	if resp.StatusCode != 200 && resp.StatusCode != 400 && resp.StatusCode != 500 && resp.StatusCode != 503 {
		return ImageResult{}, c.unknownHTTPError(resp)
	}

	body, score, err := c.parseEnvelope(resp, "unified_face_authenticity_score")
	if err != nil {
		if resp.StatusCode == 500 || resp.StatusCode == 503 {
			return ImageResult{}, newServerError(
				fmt.Sprintf("HTTP %d", resp.StatusCode),
				resp.StatusCode,
				c.requestID(resp, nil),
				nil,
			)
		}
		return ImageResult{}, err
	}

	result, err := c.parseImageResult(score, resp.StatusCode)
	if err != nil {
		if resp.StatusCode == 500 || resp.StatusCode == 503 {
			return ImageResult{}, newServerError(
				fmt.Sprintf("HTTP %d", resp.StatusCode),
				resp.StatusCode,
				c.requestID(resp, nil),
				nil,
			)
		}
		return ImageResult{}, err
	}

	if err := c.raiseForEnvelopeStatus(resp, score, result.Status, result.Message); err != nil {
		return ImageResult{}, err
	}
	if resp.StatusCode == 500 || resp.StatusCode == 503 {
		return ImageResult{}, newServerError(
			c.redact(result.Message),
			resp.StatusCode,
			c.requestID(resp, score),
			c.sanitizedEnvelope(score),
		)
	}
	if resp.StatusCode == 400 && result.Status != "rejected" {
		return ImageResult{}, &HttpError{
			Detail:     "HTTP 400 response was not a rejection",
			StatusCode: 400,
			RequestID:  c.requestID(resp, score),
		}
	}
	_ = body
	return result, nil
}

func (c *Client) classifyVideo(resp *http.Response) (VideoResult, error) {
	if err := c.raiseSimpleHTTPErrors(resp); err != nil {
		return VideoResult{}, err
	}
	if resp.StatusCode != 200 && resp.StatusCode != 400 && resp.StatusCode != 500 && resp.StatusCode != 503 {
		return VideoResult{}, c.unknownHTTPError(resp)
	}

	body, score, err := c.parseEnvelope(resp, "unified_video_authenticity_score")
	if err != nil {
		if resp.StatusCode == 500 || resp.StatusCode == 503 {
			return VideoResult{}, newServerError(
				fmt.Sprintf("HTTP %d", resp.StatusCode),
				resp.StatusCode,
				c.requestID(resp, nil),
				nil,
			)
		}
		return VideoResult{}, err
	}

	result, err := c.parseVideoResult(score, resp.StatusCode)
	if err != nil {
		if resp.StatusCode == 500 || resp.StatusCode == 503 {
			return VideoResult{}, newServerError(
				fmt.Sprintf("HTTP %d", resp.StatusCode),
				resp.StatusCode,
				c.requestID(resp, nil),
				nil,
			)
		}
		return VideoResult{}, err
	}

	if err := c.raiseForEnvelopeStatus(resp, score, result.Status, result.VideoMessage); err != nil {
		return VideoResult{}, err
	}
	if resp.StatusCode == 500 || resp.StatusCode == 503 {
		return VideoResult{}, newServerError(
			c.redact(result.VideoMessage),
			resp.StatusCode,
			c.requestID(resp, score),
			c.sanitizedEnvelope(score),
		)
	}
	if resp.StatusCode == 400 && result.Status != "rejected" {
		return VideoResult{}, &HttpError{
			Detail:     "HTTP 400 response was not a rejection",
			StatusCode: 400,
			RequestID:  c.requestID(resp, score),
		}
	}
	_ = body
	return result, nil
}

func (c *Client) raiseSimpleHTTPErrors(resp *http.Response) error {
	switch resp.StatusCode {
	case 401:
		return newAuthenticationError(c.responseDetail(resp), c.requestID(resp, nil))
	case 403:
		return newScopeError(c.responseDetail(resp), c.requestID(resp, nil))
	case 429:
		retryAfter := c.parseRetryAfter(resp.Header.Get("Retry-After"))
		return newRateLimitError(
			c.responseDetail(resp),
			c.requestID(resp, nil),
			retryAfter,
			resp.Header.Get("X-RateLimit-Limit"),
			resp.Header.Get("X-RateLimit-Remaining"),
			resp.Header.Get("X-RateLimit-Reset"),
		)
	default:
		return nil
	}
}

func (c *Client) parseEnvelope(resp *http.Response, envelopeName string) (map[string]any, map[string]any, error) {
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, nil, newProtocolError("response body is not valid JSON", resp.StatusCode, c.requestID(resp, nil))
	}
	var decoded map[string]any
	if err := json.Unmarshal(raw, &decoded); err != nil {
		return nil, nil, newProtocolError("response body is not valid JSON", resp.StatusCode, c.requestID(resp, nil))
	}
	scoreValue, ok := decoded[envelopeName]
	if !ok {
		return nil, nil, newProtocolError(
			fmt.Sprintf("response is missing the %q envelope", envelopeName),
			resp.StatusCode,
			c.requestID(resp, nil),
		)
	}
	score, ok := scoreValue.(map[string]any)
	if !ok {
		return nil, nil, newProtocolError(
			fmt.Sprintf("response is missing the %q envelope", envelopeName),
			resp.StatusCode,
			c.requestID(resp, nil),
		)
	}
	return decoded, score, nil
}

func (c *Client) parseImageResult(score map[string]any, httpStatus int) (ImageResult, error) {
	uniqueTrxID, err := requiredString(score, "unique_trx_id", httpStatus)
	if err != nil {
		return ImageResult{}, err
	}
	filename, err := requiredString(score, "filename", httpStatus)
	if err != nil {
		return ImageResult{}, err
	}
	contentType, err := requiredString(score, "content_type", httpStatus)
	if err != nil {
		return ImageResult{}, err
	}
	status, err := requiredString(score, "status", httpStatus)
	if err != nil {
		return ImageResult{}, err
	}
	statusCode, err := requiredInt(score, "status_code", httpStatus)
	if err != nil {
		return ImageResult{}, err
	}
	billable, err := parseBillable(score, httpStatus)
	if err != nil {
		return ImageResult{}, err
	}
	message, err := requiredString(score, "message", httpStatus)
	if err != nil {
		return ImageResult{}, err
	}
	riskScore, err := optionalFloat(score, "risk_score", httpStatus)
	if err != nil {
		return ImageResult{}, err
	}
	riskLevel, err := optionalString(score, "risk_level", httpStatus)
	if err != nil {
		return ImageResult{}, err
	}
	signals, err := parseSignals(score, httpStatus)
	if err != nil {
		return ImageResult{}, err
	}
	return ImageResult{
		UniqueTrxID:     uniqueTrxID,
		Filename:        filename,
		ContentType:     contentType,
		Status:          status,
		StatusCode:      statusCode,
		Billable:        billable,
		RiskScore:       riskScore,
		RiskLevel:       riskLevel,
		Message:         message,
		AIThreatSignals: signals,
		Raw:             c.sanitizedEnvelope(score),
	}, nil
}

func (c *Client) parseVideoResult(score map[string]any, httpStatus int) (VideoResult, error) {
	uniqueTrxID, err := requiredString(score, "unique_trx_id", httpStatus)
	if err != nil {
		return VideoResult{}, err
	}
	filename, err := requiredString(score, "filename", httpStatus)
	if err != nil {
		return VideoResult{}, err
	}
	contentType, err := requiredString(score, "content_type", httpStatus)
	if err != nil {
		return VideoResult{}, err
	}
	status, err := requiredString(score, "status", httpStatus)
	if err != nil {
		return VideoResult{}, err
	}
	statusCode, err := requiredInt(score, "status_code", httpStatus)
	if err != nil {
		return VideoResult{}, err
	}
	billable, err := parseBillable(score, httpStatus)
	if err != nil {
		return VideoResult{}, err
	}
	videoMessage, err := requiredString(score, "video_message", httpStatus)
	if err != nil {
		return VideoResult{}, err
	}
	videoScore, err := optionalFloat(score, "video_risk_score", httpStatus)
	if err != nil {
		return VideoResult{}, err
	}
	videoLevel, err := optionalString(score, "video_risk_level", httpStatus)
	if err != nil {
		return VideoResult{}, err
	}
	audioScore, err := optionalFloat(score, "audio_risk_score", httpStatus)
	if err != nil {
		return VideoResult{}, err
	}
	audioLevel, err := optionalString(score, "audio_risk_level", httpStatus)
	if err != nil {
		return VideoResult{}, err
	}
	audioMessage, err := optionalString(score, "audio_message", httpStatus)
	if err != nil {
		return VideoResult{}, err
	}
	signals, err := parseSignals(score, httpStatus)
	if err != nil {
		return VideoResult{}, err
	}
	return VideoResult{
		UniqueTrxID:     uniqueTrxID,
		Filename:        filename,
		ContentType:     contentType,
		Status:          status,
		StatusCode:      statusCode,
		Billable:        billable,
		VideoRiskScore:  videoScore,
		VideoRiskLevel:  videoLevel,
		VideoMessage:    videoMessage,
		AudioRiskScore:  audioScore,
		AudioRiskLevel:  audioLevel,
		AudioMessage:    audioMessage,
		AIThreatSignals: signals,
		Raw:             c.sanitizedEnvelope(score),
	}, nil
}

func (c *Client) raiseForEnvelopeStatus(resp *http.Response, score map[string]any, status, message string) error {
	if status == "error" {
		return newServerError(
			c.redact(message),
			resp.StatusCode,
			c.requestID(resp, score),
			c.sanitizedEnvelope(score),
		)
	}
	return nil
}

func requiredString(score map[string]any, name string, httpStatus int) (string, error) {
	value, ok := score[name].(string)
	if !ok {
		return "", newProtocolError(fmt.Sprintf("response field %q must be a string", name), httpStatus, "")
	}
	return value, nil
}

func requiredInt(score map[string]any, name string, httpStatus int) (int, error) {
	value, ok := score[name].(float64)
	if !ok {
		if intValue, intOK := score[name].(int); intOK {
			return intValue, nil
		}
		return 0, newProtocolError(fmt.Sprintf("response field %q must be an integer", name), httpStatus, "")
	}
	if value != math.Trunc(value) {
		return 0, newProtocolError(fmt.Sprintf("response field %q must be an integer", name), httpStatus, "")
	}
	return int(value), nil
}

func optionalString(score map[string]any, name string, httpStatus int) (*string, error) {
	if _, ok := score[name]; !ok {
		return nil, newProtocolError(
			fmt.Sprintf("response is missing required field %q", name),
			httpStatus,
			"",
		)
	}
	if score[name] == nil {
		return nil, nil
	}
	value, ok := score[name].(string)
	if !ok {
		return nil, newProtocolError(
			fmt.Sprintf("response field %q must be a string or null", name),
			httpStatus,
			"",
		)
	}
	return &value, nil
}

func optionalFloat(score map[string]any, name string, httpStatus int) (*float64, error) {
	if _, ok := score[name]; !ok {
		return nil, newProtocolError(
			fmt.Sprintf("response is missing required field %q", name),
			httpStatus,
			"",
		)
	}
	if score[name] == nil {
		return nil, nil
	}
	var numeric float64
	switch value := score[name].(type) {
	case float64:
		numeric = value
	case int:
		numeric = float64(value)
	case json.Number:
		parsed, err := value.Float64()
		if err != nil {
			return nil, newProtocolError(
				fmt.Sprintf("response field %q must be numeric or null", name),
				httpStatus,
				"",
			)
		}
		numeric = parsed
	default:
		return nil, newProtocolError(
			fmt.Sprintf("response field %q must be numeric or null", name),
			httpStatus,
			"",
		)
	}
	if !isFinite(numeric) || numeric < 0.1 || numeric > 10.0 {
		return nil, newProtocolError(
			fmt.Sprintf("response field %q must be from 0.1 through 10.0 or null", name),
			httpStatus,
			"",
		)
	}
	return &numeric, nil
}

func parseBillable(score map[string]any, httpStatus int) (bool, error) {
	value, ok := score["billable"].(string)
	if !ok || (value != "Y" && value != "N") {
		return false, newProtocolError("response field 'billable' must be exactly 'Y' or 'N'", httpStatus, "")
	}
	return value == "Y", nil
}

func parseSignals(score map[string]any, httpStatus int) ([]string, error) {
	raw, ok := score["ai_threat_signals"]
	if !ok || raw == nil {
		return []string{}, nil
	}
	items, ok := raw.([]any)
	if !ok {
		return nil, newProtocolError(
			"response field 'ai_threat_signals' must be an array of strings",
			httpStatus,
			"",
		)
	}
	out := make([]string, 0, len(items))
	for _, item := range items {
		value, ok := item.(string)
		if !ok {
			return nil, newProtocolError(
				"response field 'ai_threat_signals' must be an array of strings",
				httpStatus,
				"",
			)
		}
		out = append(out, value)
	}
	return out, nil
}

func (c *Client) unknownHTTPError(resp *http.Response) error {
	return &HttpError{
		Detail:     c.responseDetail(resp),
		StatusCode: resp.StatusCode,
		RequestID:  c.requestID(resp, nil),
	}
}

func (c *Client) responseDetail(resp *http.Response) string {
	detail := fmt.Sprintf("HTTP %d", resp.StatusCode)
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return c.redact(detail)
	}
	resp.Body = io.NopCloser(bytes.NewReader(raw))
	var decoded map[string]any
	if err := json.Unmarshal(raw, &decoded); err == nil {
		if value, ok := decoded["detail"].(string); ok {
			detail = value
		}
	}
	return c.redact(detail)
}

func (c *Client) requestID(resp *http.Response, score map[string]any) string {
	if header := resp.Header.Get("X-Request-ID"); header != "" {
		return header
	}
	if score != nil {
		if value, ok := score["unique_trx_id"].(string); ok && value != "" {
			return value
		}
	}
	return ""
}

func (c *Client) redact(value string) string {
	return strings.ReplaceAll(value, c.apiKey, "[REDACTED]")
}

func (c *Client) sanitizedEnvelope(value map[string]any) map[string]any {
	return sanitizeMap(value, c.apiKey)
}

func sanitizeMap(value map[string]any, apiKey string) map[string]any {
	out := make(map[string]any, len(value))
	for key, item := range value {
		out[key] = sanitizeValue(item, apiKey)
	}
	return out
}

func sanitizeValue(item any, apiKey string) any {
	switch typed := item.(type) {
	case string:
		return strings.ReplaceAll(typed, apiKey, "[REDACTED]")
	case map[string]any:
		return sanitizeMap(typed, apiKey)
	case []any:
		out := make([]any, len(typed))
		for i, nested := range typed {
			out[i] = sanitizeValue(nested, apiKey)
		}
		return out
	default:
		return item
	}
}

func isFinite(value float64) bool {
	return !math.IsInf(value, 0) && !math.IsNaN(value)
}

func isTimeout(err error) bool {
	if err == nil {
		return false
	}
	if err == context.DeadlineExceeded {
		return true
	}
	type timeout interface{ Timeout() bool }
	if t, ok := err.(timeout); ok && t.Timeout() {
		return true
	}
	return strings.Contains(strings.ToLower(err.Error()), "timeout")
}

func defaultRandom() float64 {
	return float64(time.Now().UnixNano()%1000) / 1000.0
}

func newNetworkError(detail string) *NetworkError {
	return &NetworkError{Detail: detail}
}

func newTimeoutError(detail string) *TimeoutError {
	return &TimeoutError{Detail: detail}
}

func newAuthenticationError(detail, requestID string) *AuthenticationError {
	return &AuthenticationError{Detail: detail, StatusCode: 401, RequestID: requestID}
}

func newScopeError(detail, requestID string) *ScopeError {
	return &ScopeError{Detail: detail, StatusCode: 403, RequestID: requestID}
}

func newRateLimitError(detail, requestID string, retryAfter *float64, limit, remaining, reset string) *RateLimitError {
	return &RateLimitError{
		Detail:     detail,
		StatusCode: 429,
		RequestID:  requestID,
		RetryAfter: retryAfter,
		Limit:      limit,
		Remaining:  remaining,
		Reset:      reset,
	}
}

func newServerError(detail string, status int, requestID string, envelope map[string]any) *ServerError {
	return &ServerError{
		Detail:     detail,
		StatusCode: status,
		RequestID:  requestID,
		Envelope:   envelope,
	}
}

func newProtocolError(detail string, status int, requestID string) *ProtocolError {
	return &ProtocolError{Detail: detail, StatusCode: status, RequestID: requestID}
}
