package neuraldefend

import "fmt"

// ValidationError is raised when local request validation fails.
type ValidationError struct {
	Detail     string
	StatusCode int
	RequestID  string
}

func (e *ValidationError) Error() string { return e.Detail }

// ProtocolError is raised when the server response does not match the required envelope.
type ProtocolError struct {
	Detail     string
	StatusCode int
	RequestID  string
}

func (e *ProtocolError) Error() string { return e.Detail }

// NetworkError is raised for non-timeout network failures; requests are not retried.
type NetworkError struct {
	Detail     string
	StatusCode int
	RequestID  string
}

func (e *NetworkError) Error() string { return e.Detail }

// TimeoutError is raised when an HTTP operation times out; requests are not retried.
type TimeoutError struct {
	Detail     string
	StatusCode int
	RequestID  string
}

func (e *TimeoutError) Error() string { return e.Detail }

// HttpError is raised for an otherwise unclassified HTTP response.
type HttpError struct {
	Detail     string
	StatusCode int
	RequestID  string
}

func (e *HttpError) Error() string { return e.Detail }

// AuthenticationError is raised for HTTP 401.
type AuthenticationError struct {
	Detail     string
	StatusCode int
	RequestID  string
}

func (e *AuthenticationError) Error() string { return e.Detail }

// ScopeError is raised for HTTP 403 when the key lacks endpoint access.
type ScopeError struct {
	Detail     string
	StatusCode int
	RequestID  string
}

func (e *ScopeError) Error() string { return e.Detail }

// RateLimitError is raised when HTTP 429 remains after configured retries.
type RateLimitError struct {
	Detail     string
	StatusCode int
	RequestID  string
	RetryAfter *float64
	Limit      string
	Remaining  string
	Reset      string
}

func (e *RateLimitError) Error() string { return e.Detail }

// ServerError is raised for an error envelope, including final HTTP 500/503.
type ServerError struct {
	Detail     string
	StatusCode int
	RequestID  string
	Envelope   map[string]any
}

func (e *ServerError) Error() string { return e.Detail }

func errorf(format string, args ...any) string {
	return fmt.Sprintf(format, args...)
}
