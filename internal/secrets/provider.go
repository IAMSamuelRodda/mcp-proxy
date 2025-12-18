// Package secrets provides a pluggable secrets provider interface for MCP servers.
//
// This allows mcp-proxy to integrate with various secrets backends (OpenBao, HashiCorp Vault,
// AWS Secrets Manager, etc.) while maintaining graceful degradation when secrets are unavailable.
package secrets

import (
	"encoding/json"
)

// ErrorCode represents standardized error codes for secrets operations
type ErrorCode string

const (
	// Access Errors (secrets provider issues)
	ErrProviderNotRunning   ErrorCode = "SECRETS_PROVIDER_NOT_RUNNING"
	ErrNoSession            ErrorCode = "SECRETS_NO_SESSION"
	ErrAutoStartFailed      ErrorCode = "SECRETS_AUTO_START_FAILED"
	ErrConnectionTimeout    ErrorCode = "SECRETS_CONNECTION_TIMEOUT"

	// Credential Errors (secret-specific issues)
	ErrSecretNotFound       ErrorCode = "SECRET_NOT_FOUND"
	ErrSecretPermissionDenied ErrorCode = "SECRET_PERMISSION_DENIED"
	ErrSecretInvalidToken   ErrorCode = "SECRET_INVALID_TOKEN"
	ErrSecretParseError     ErrorCode = "SECRET_PARSE_ERROR"

	// Source indicators (informational)
	SourceProvider ErrorCode = "SOURCE_PROVIDER"
	SourceEnv      ErrorCode = "SOURCE_ENV"
)

// Status represents the result of a secrets provider availability check
type Status struct {
	Available    bool      `json:"available"`
	ErrorCode    ErrorCode `json:"error_code,omitempty"`
	ErrorMessage string    `json:"error_message,omitempty"`
	AutoStarted  bool      `json:"auto_started,omitempty"`
	ProviderName string    `json:"provider_name,omitempty"`
}

// ToJSON returns the status as a JSON string
func (s *Status) ToJSON() string {
	data, _ := json.Marshal(s)
	return string(data)
}

// Config holds secrets provider configuration
type Config struct {
	// Provider type: "none", "openbao", "env"
	Provider string `json:"secretsProvider"`

	// Whether to attempt auto-start if provider not running
	AutoStart bool `json:"secretsAutoStart"`

	// Command to run for auto-start (e.g., "start-openbao-mcp")
	AutoStartCmd string `json:"secretsAutoStartCmd"`

	// Provider-specific address (e.g., "http://127.0.0.1:18200")
	ProviderAddr string `json:"secretsProviderAddr"`

	// Path to session file for auto-start capability check
	// e.g., "~/.bitwarden-guard/sessions/current"
	SessionPath string `json:"secretsSessionPath"`

	// Environment variable to check for session (alternative to SessionPath)
	// e.g., "BW_SESSION"
	SessionEnvVar string `json:"secretsSessionEnvVar"`

	// Timeouts in milliseconds
	HealthTimeoutMs int `json:"secretsHealthTimeoutMs"`
	StartTimeoutMs  int `json:"secretsStartTimeoutMs"`
}

// DefaultConfig returns a disabled secrets configuration
func DefaultConfig() *Config {
	return &Config{
		Provider:        "none",
		AutoStart:       false,
		AutoStartCmd:    "",
		ProviderAddr:    "",
		SessionPath:     "",
		SessionEnvVar:   "BW_SESSION",
		HealthTimeoutMs: 2000,
		StartTimeoutMs:  15000,
	}
}

// Provider is the interface that secrets backends must implement
type Provider interface {
	// Name returns the provider name (e.g., "openbao", "vault", "env")
	Name() string

	// CheckHealth checks if the provider is available
	CheckHealth() *Status

	// CanAutoStart checks if auto-start is possible
	CanAutoStart() (bool, ErrorCode)

	// AutoStart attempts to start the provider
	AutoStart() *Status

	// EnsureAvailable checks health and auto-starts if needed
	EnsureAvailable() *Status
}

// NewProvider creates a secrets provider based on configuration
func NewProvider(cfg *Config) Provider {
	if cfg == nil {
		cfg = DefaultConfig()
	}

	switch cfg.Provider {
	case "openbao":
		// Import and create OpenBao provider
		// This will be done via the openbao subpackage
		return nil // Placeholder - actual creation done in openbao package
	case "env":
		// Environment variable only provider (always "available")
		return &envProvider{}
	default:
		// "none" or unknown - return nil (secrets disabled)
		return nil
	}
}

// envProvider is a simple provider that just uses environment variables
type envProvider struct{}

func (e *envProvider) Name() string {
	return "env"
}

func (e *envProvider) CheckHealth() *Status {
	return &Status{Available: true, ProviderName: "env"}
}

func (e *envProvider) CanAutoStart() (bool, ErrorCode) {
	return true, "" // Always "startable" (no-op)
}

func (e *envProvider) AutoStart() *Status {
	return &Status{Available: true, ProviderName: "env"}
}

func (e *envProvider) EnsureAvailable() *Status {
	return &Status{Available: true, ProviderName: "env"}
}

// ParseErrorFromStderr attempts to parse an error code from MCP server stderr output
func ParseErrorFromStderr(stderr string) (ErrorCode, string) {
	// Check for structured error output
	if len(stderr) > 14 && stderr[:14] == "SECRETS_ERROR:" {
		var status Status
		if err := json.Unmarshal([]byte(stderr[14:]), &status); err == nil {
			return status.ErrorCode, status.ErrorMessage
		}
	}

	// Also check for legacy OPENBAO_ERROR format
	if len(stderr) > 14 && stderr[:14] == "OPENBAO_ERROR:" {
		var status Status
		if err := json.Unmarshal([]byte(stderr[14:]), &status); err == nil {
			return status.ErrorCode, status.ErrorMessage
		}
	}

	// Check for common error patterns
	patterns := map[string]ErrorCode{
		"agent not running":     ErrProviderNotRunning,
		"connection refused":    ErrProviderNotRunning,
		"secret not found":      ErrSecretNotFound,
		"permission denied":     ErrSecretPermissionDenied,
		"invalid token":         ErrSecretInvalidToken,
		"token expired":         ErrSecretInvalidToken,
		"403":                   ErrSecretPermissionDenied,
		"404":                   ErrSecretNotFound,
	}

	for pattern, code := range patterns {
		if containsIgnoreCase(stderr, pattern) {
			return code, stderr
		}
	}

	return ErrProviderNotRunning, stderr
}

// containsIgnoreCase checks if s contains substr (case-insensitive)
func containsIgnoreCase(s, substr string) bool {
	sLower := make([]byte, len(s))
	substrLower := make([]byte, len(substr))

	for i := 0; i < len(s); i++ {
		c := s[i]
		if c >= 'A' && c <= 'Z' {
			c = c + 32
		}
		sLower[i] = c
	}

	for i := 0; i < len(substr); i++ {
		c := substr[i]
		if c >= 'A' && c <= 'Z' {
			c = c + 32
		}
		substrLower[i] = c
	}

	for i := 0; i <= len(sLower)-len(substrLower); i++ {
		match := true
		for j := 0; j < len(substrLower); j++ {
			if sLower[i+j] != substrLower[j] {
				match = false
				break
			}
		}
		if match {
			return true
		}
	}
	return false
}
