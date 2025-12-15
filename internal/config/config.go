package config

import (
	"errors"
	"fmt"
	nethttp "net/http"
	"strings"
	"time"

	"github.com/TBXark/optional-go"
	"github.com/go-sphere/confstore"
	"github.com/go-sphere/confstore/codec"
	"github.com/go-sphere/confstore/provider"
	"github.com/go-sphere/confstore/provider/file"
	"github.com/go-sphere/confstore/provider/http"
)

type StdioMCPClientConfig struct {
	Command string            `json:"command"`
	Env     map[string]string `json:"env"`
	Args    []string          `json:"args"`
}

type SSEMCPClientConfig struct {
	URL     string            `json:"url"`
	Headers map[string]string `json:"headers"`
}

type StreamableMCPClientConfig struct {
	URL     string            `json:"url"`
	Headers map[string]string `json:"headers"`
	Timeout time.Duration     `json:"timeout"`
}

type MCPClientType string

const (
	MCPClientTypeStdio      MCPClientType = "stdio"
	MCPClientTypeSSE        MCPClientType = "sse"
	MCPClientTypeStreamable MCPClientType = "streamable-http"
)

type MCPServerType string

const (
	MCPServerTypeStdio      MCPServerType = "stdio"
	MCPServerTypeSSE        MCPServerType = "sse"
	MCPServerTypeStreamable MCPServerType = "streamable-http"
)

// ---- V2 ----

type ToolFilterMode string

const (
	ToolFilterModeAllow ToolFilterMode = "allow"
	ToolFilterModeBlock ToolFilterMode = "block"
)

type ToolFilterConfig struct {
	Mode ToolFilterMode `json:"mode,omitempty"`
	List []string       `json:"list,omitempty"`
}

type OptionsV2 struct {
	PanicIfInvalid    optional.Field[bool] `json:"panicIfInvalid,omitempty"`
	LogEnabled        optional.Field[bool] `json:"logEnabled,omitempty"`
	LazyLoad          optional.Field[bool] `json:"lazyLoad,omitempty"`
	RecursiveLazyLoad optional.Field[bool] `json:"recursiveLazyLoad,omitempty"`
	PreloadAll        optional.Field[bool] `json:"preloadAll,omitempty"` // Preload all servers in background at startup
	AuthTokens        []string             `json:"authTokens,omitempty"`
	ToolFilter        *ToolFilterConfig    `json:"toolFilter,omitempty"`
}

type MCPProxyConfigV2 struct {
	BaseURL       string        `json:"baseURL"`
	Addr          string        `json:"addr"`
	Name          string        `json:"name"`
	Version       string        `json:"version"`
	Type          MCPServerType `json:"type,omitempty"`
	HierarchyPath string        `json:"hierarchyPath,omitempty"`
	Options       *OptionsV2    `json:"options,omitempty"`
}

type MCPClientConfigV2 struct {
	TransportType MCPClientType `json:"transportType,omitempty"`

	// Stdio
	Command string            `json:"command,omitempty"`
	Args    []string          `json:"args,omitempty"`
	Env     map[string]string `json:"env,omitempty"`

	// SSE or Streamable HTTP
	URL     string            `json:"url,omitempty"`
	Headers map[string]string `json:"headers,omitempty"`
	Timeout time.Duration     `json:"timeout,omitempty"`

	Options *OptionsV2 `json:"options,omitempty"`
}

// validateStdioCommand checks for command injection patterns in stdio config
func validateStdioCommand(command string, args []string) error {
	// Check for shell metacharacters that could indicate injection
	dangerousPatterns := []string{";", "|", "&&", "||", "`", "$(", "${", ">", "<", "&"}

	for _, pattern := range dangerousPatterns {
		if strings.Contains(command, pattern) {
			return fmt.Errorf("command contains potentially dangerous pattern %q - use absolute paths", pattern)
		}
		for i, arg := range args {
			if strings.Contains(arg, pattern) {
				return fmt.Errorf("args[%d] contains potentially dangerous pattern %q", i, pattern)
			}
		}
	}

	// Warn (via error) if command is not an absolute path
	if !strings.HasPrefix(command, "/") && command != "" {
		// Allow common interpreters but log a note
		allowedRelative := map[string]bool{"python": true, "python3": true, "node": true, "npx": true, "go": true, "ruby": true}
		if !allowedRelative[command] {
			return fmt.Errorf("command %q is not an absolute path - consider using full path for security", command)
		}
	}

	return nil
}

func ParseMCPClientConfigV2(conf *MCPClientConfigV2) (any, error) {
	if conf.Command != "" || conf.TransportType == MCPClientTypeStdio {
		if conf.Command == "" {
			return nil, errors.New("command is required for stdio transport")
		}
		if err := validateStdioCommand(conf.Command, conf.Args); err != nil {
			return nil, fmt.Errorf("stdio command validation failed: %w", err)
		}
		return &StdioMCPClientConfig{
			Command: conf.Command,
			Env:     conf.Env,
			Args:    conf.Args,
		}, nil
	}
	if conf.URL != "" {
		if conf.TransportType == MCPClientTypeStreamable {
			return &StreamableMCPClientConfig{
				URL:     conf.URL,
				Headers: conf.Headers,
				Timeout: conf.Timeout,
			}, nil
		} else {
			return &SSEMCPClientConfig{
				URL:     conf.URL,
				Headers: conf.Headers,
			}, nil
		}
	}
	return nil, errors.New("invalid server type")
}

// ---- Config ----

type Config struct {
	McpProxy   *MCPProxyConfigV2             `json:"mcpProxy"`
	McpServers map[string]*MCPClientConfigV2 `json:"mcpServers"`
}

type FullConfig struct {
	DeprecatedServerV1  *MCPProxyConfigV1             `json:"server"`
	DeprecatedClientsV1 map[string]*MCPClientConfigV1 `json:"clients"`

	McpProxy   *MCPProxyConfigV2             `json:"mcpProxy"`
	McpServers map[string]*MCPClientConfigV2 `json:"mcpServers"`
}

func newConfProvider(path string, expandEnv bool, httpHeaders string, httpTimeout int) (provider.Provider, error) {
	if http.IsRemoteURL(path) {
		var opts []http.Option
		httpClient := nethttp.DefaultClient
		if httpTimeout > 0 {
			httpClient.Timeout = time.Duration(httpTimeout) * time.Second
		}
		opts = append(opts, http.WithClient(httpClient))
		if httpHeaders != "" {
			// format: 'Key1:Value1;Key2:Value2'
			headers := make(nethttp.Header)
			for _, kv := range strings.Split(httpHeaders, ";") {
				parts := strings.SplitN(kv, ":", 2)
				if len(parts) == 2 {
					key := strings.TrimSpace(parts[0])
					value := strings.TrimSpace(parts[1])
					if key != "" && value != "" {
						headers.Add(key, value)
					}
				}
			}
		}
		pro := http.New(path, opts...)
		if expandEnv {
			return provider.NewExpandEnv(pro), nil
		} else {
			return pro, nil
		}
	}
	if file.IsLocalPath(path) {
		if expandEnv {
			return provider.NewExpandEnv(file.New(path, file.WithExpandEnv())), nil
		} else {
			return file.New(path), nil
		}
	}
	return nil, errors.New("unsupported config path")
}

// MinTokenLength is the minimum required length for auth tokens (24 bytes = 32 base64 chars)
const MinTokenLength = 24

// validateAuthTokens checks that auth tokens meet minimum security requirements
func validateAuthTokens(tokens []string) error {
	for i, token := range tokens {
		if len(token) < MinTokenLength {
			return fmt.Errorf("authToken[%d] is too short (%d chars). Minimum %d chars required for security. Generate with: openssl rand -base64 32", i, len(token), MinTokenLength)
		}
	}
	return nil
}

func Load(path string, expandEnv bool, httpHeaders string, httpTimeout int) (*Config, error) {
	pro, err := newConfProvider(path, expandEnv, httpHeaders, httpTimeout)
	if err != nil {
		return nil, err
	}
	conf, err := confstore.Load[FullConfig](pro, codec.JsonCodec())
	if err != nil {
		return nil, err
	}
	adaptMCPClientConfigV1ToV2(conf)

	if conf.McpProxy == nil {
		return nil, errors.New("mcpProxy is required")
	}
	if conf.McpProxy.Options == nil {
		conf.McpProxy.Options = &OptionsV2{}
	}
	for _, clientConfig := range conf.McpServers {
		if clientConfig.Options == nil {
			clientConfig.Options = &OptionsV2{}
		}
		if clientConfig.Options.AuthTokens == nil {
			clientConfig.Options.AuthTokens = conf.McpProxy.Options.AuthTokens
		}
		if !clientConfig.Options.PanicIfInvalid.Present() {
			clientConfig.Options.PanicIfInvalid = conf.McpProxy.Options.PanicIfInvalid
		}
		if !clientConfig.Options.LogEnabled.Present() {
			clientConfig.Options.LogEnabled = conf.McpProxy.Options.LogEnabled
		}
		if !clientConfig.Options.LazyLoad.Present() {
			clientConfig.Options.LazyLoad = conf.McpProxy.Options.LazyLoad
		}
	}

	if conf.McpProxy.Type == "" {
		conf.McpProxy.Type = MCPServerTypeSSE // default to SSE
	}

	// Validate auth token strength for HTTP server modes
	if conf.McpProxy.Type != MCPServerTypeStdio && conf.McpProxy.Options != nil && len(conf.McpProxy.Options.AuthTokens) > 0 {
		if err := validateAuthTokens(conf.McpProxy.Options.AuthTokens); err != nil {
			return nil, fmt.Errorf("security validation failed: %w", err)
		}
	}

	return &Config{
		McpProxy:   conf.McpProxy,
		McpServers: conf.McpServers,
	}, nil
}
