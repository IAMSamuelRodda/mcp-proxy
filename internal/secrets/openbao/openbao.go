// Package openbao provides an OpenBao/HashiCorp Vault secrets provider implementation.
package openbao

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/samuelrodda/mcp-proxy/internal/secrets"
)

// Provider implements secrets.Provider for OpenBao/Vault
type Provider struct {
	cfg *secrets.Config
}

// New creates a new OpenBao provider with the given configuration
func New(cfg *secrets.Config) *Provider {
	if cfg == nil {
		cfg = secrets.DefaultConfig()
	}
	return &Provider{cfg: cfg}
}

// Name returns the provider name
func (p *Provider) Name() string {
	return "openbao"
}

// CheckHealth performs a health check against the OpenBao agent
func (p *Provider) CheckHealth() *secrets.Status {
	if p.cfg.ProviderAddr == "" {
		return &secrets.Status{
			Available:    false,
			ErrorCode:    secrets.ErrProviderNotRunning,
			ErrorMessage: "no provider address configured",
			ProviderName: p.Name(),
		}
	}

	timeout := time.Duration(p.cfg.HealthTimeoutMs) * time.Millisecond
	if timeout == 0 {
		timeout = 2 * time.Second
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	healthURL := strings.TrimSuffix(p.cfg.ProviderAddr, "/") + "/v1/sys/health"
	req, err := http.NewRequestWithContext(ctx, "GET", healthURL, nil)
	if err != nil {
		return &secrets.Status{
			Available:    false,
			ErrorCode:    secrets.ErrProviderNotRunning,
			ErrorMessage: fmt.Sprintf("failed to create health check request: %v", err),
			ProviderName: p.Name(),
		}
	}

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return &secrets.Status{
			Available:    false,
			ErrorCode:    secrets.ErrProviderNotRunning,
			ErrorMessage: fmt.Sprintf("agent not responding at %s: %v", p.cfg.ProviderAddr, err),
			ProviderName: p.Name(),
		}
	}
	defer resp.Body.Close()

	// OpenBao/Vault health endpoint returns various status codes:
	// 200 - initialized, unsealed, active
	// 429 - unsealed and standby
	// 472 - disaster recovery mode replication secondary and active
	// 473 - performance standby
	// 501 - not initialized
	// 503 - sealed
	if resp.StatusCode == 200 || resp.StatusCode == 429 {
		return &secrets.Status{Available: true, ProviderName: p.Name()}
	}

	return &secrets.Status{
		Available:    false,
		ErrorCode:    secrets.ErrProviderNotRunning,
		ErrorMessage: fmt.Sprintf("agent returned unhealthy status: %d", resp.StatusCode),
		ProviderName: p.Name(),
	}
}

// CanAutoStart checks if auto-start is possible
func (p *Provider) CanAutoStart() (bool, secrets.ErrorCode) {
	// Check environment variable first
	if p.cfg.SessionEnvVar != "" && os.Getenv(p.cfg.SessionEnvVar) != "" {
		return true, ""
	}

	// Check session file path
	if p.cfg.SessionPath != "" {
		sessionPath := expandPath(p.cfg.SessionPath)
		if _, err := os.Stat(sessionPath); err == nil {
			return true, ""
		}
	}

	return false, secrets.ErrNoSession
}

// AutoStart attempts to start the OpenBao agent
func (p *Provider) AutoStart() *secrets.Status {
	if p.cfg.AutoStartCmd == "" {
		return &secrets.Status{
			Available:    false,
			ErrorCode:    secrets.ErrAutoStartFailed,
			ErrorMessage: "no auto-start command configured",
			ProviderName: p.Name(),
		}
	}

	canStart, errCode := p.CanAutoStart()
	if !canStart {
		return &secrets.Status{
			Available:    false,
			ErrorCode:    errCode,
			ErrorMessage: "no session available for auto-start",
			ProviderName: p.Name(),
		}
	}

	log.Printf("Attempting to auto-start secrets provider with: %s", p.cfg.AutoStartCmd)

	timeout := time.Duration(p.cfg.StartTimeoutMs) * time.Millisecond
	if timeout == 0 {
		timeout = 15 * time.Second
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	// Parse command - could be "cmd" or "cmd arg1 arg2"
	parts := strings.Fields(p.cfg.AutoStartCmd)
	cmd := exec.CommandContext(ctx, parts[0], parts[1:]...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("Auto-start command output: %s", string(output))
		return &secrets.Status{
			Available:    false,
			ErrorCode:    secrets.ErrAutoStartFailed,
			ErrorMessage: fmt.Sprintf("failed to execute %s: %v", p.cfg.AutoStartCmd, err),
			ProviderName: p.Name(),
		}
	}

	log.Printf("Auto-start initiated, waiting for provider to become healthy...")

	// Poll for health
	pollInterval := 500 * time.Millisecond
	deadline := time.Now().Add(timeout)

	for time.Now().Before(deadline) {
		status := p.CheckHealth()
		if status.Available {
			log.Printf("Secrets provider auto-started successfully")
			return &secrets.Status{
				Available:    true,
				AutoStarted:  true,
				ProviderName: p.Name(),
			}
		}
		time.Sleep(pollInterval)
	}

	return &secrets.Status{
		Available:    false,
		ErrorCode:    secrets.ErrAutoStartFailed,
		ErrorMessage: "auto-start initiated but provider did not become healthy within timeout",
		ProviderName: p.Name(),
	}
}

// EnsureAvailable checks health and auto-starts if needed
func (p *Provider) EnsureAvailable() *secrets.Status {
	// First check if already running
	status := p.CheckHealth()
	if status.Available {
		log.Printf("Secrets provider (%s) is healthy at %s", p.Name(), p.cfg.ProviderAddr)
		return status
	}

	log.Printf("Secrets provider not available: %s", status.ErrorMessage)

	// Try auto-start if enabled
	if p.cfg.AutoStart {
		log.Printf("Attempting auto-start...")
		return p.AutoStart()
	}

	return status
}

// expandPath expands ~ to home directory
func expandPath(path string) string {
	if strings.HasPrefix(path, "~/") {
		home, err := os.UserHomeDir()
		if err != nil {
			return path
		}
		return filepath.Join(home, path[2:])
	}
	return path
}
