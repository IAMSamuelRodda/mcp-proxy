package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/mark3labs/mcp-go/client"
	"github.com/mark3labs/mcp-go/mcp"
	generator "github.com/x-forge/lazy-mcp-preload/structure_generator"
)

type arrayFlags []string

func (i *arrayFlags) String() string {
	return strings.Join(*i, ", ")
}

func (i *arrayFlags) Set(value string) error {
	*i = append(*i, value)
	return nil
}

// Config represents the MCP server configuration
type Config struct {
	MCPServers map[string]ServerConfig `json:"mcpServers"`
	OutputDir  string                  `json:"outputDir,omitempty"`
}

// ServerConfig defines how to connect to an MCP server
type ServerConfig struct {
	TransportType string            `json:"transportType"` // "stdio", "sse", "http"
	Command       string            `json:"command"`
	Args          []string          `json:"args"`
	URL           string            `json:"url"` // For SSE/HTTP transports
	Env           map[string]string `json:"env,omitempty"`
}

func main() {
	var inputFiles arrayFlags
	flag.Var(&inputFiles, "input", "Path to tool JSON file (can be specified multiple times)")
	outputDir := flag.String("output", "./structure", "Output directory for generated structure")
	configPath := flag.String("config", "", "Path to MCP server config JSON (to fetch tools from live servers)")
	regenerateRoot := flag.Bool("regenerate", false, "Regenerate hierarchy from existing structure (preserves manual edits)")
	flag.Parse()

	// Mode 0: Regenerate hierarchy
	if *regenerateRoot {
		log.Printf("Regenerating hierarchy (preserves manual edits) in: %s", *outputDir)
		if err := generator.Regenerate(*outputDir); err != nil {
			log.Fatalf("Failed to regenerate: %v", err)
		}
		fmt.Printf("\n✓ Successfully regenerated hierarchy!\n")
		fmt.Printf("  Location: %s\n", *outputDir)
		os.Exit(0)
	}

	var servers []generator.ServerTools

	// Mode 1: Using config file to fetch from live MCP servers
	if *configPath != "" {
		log.Printf("Loading config from: %s", *configPath)
		configServers, err := fetchFromConfig(*configPath)
		if err != nil {
			log.Fatalf("Failed to fetch from config: %v", err)
		}
		servers = configServers

		// Use outputDir from config if not specified via flag
		if *outputDir == "./structure" {
			configData, _ := os.ReadFile(*configPath)
			var config Config
			if json.Unmarshal(configData, &config) == nil && config.OutputDir != "" {
				*outputDir = config.OutputDir
			}
		}
	} else if len(inputFiles) > 0 {
		// Mode 2: Using pre-fetched JSON files
		for _, inputFile := range inputFiles {
			data, err := os.ReadFile(inputFile)
			if err != nil {
				log.Fatalf("Failed to read %s: %v", inputFile, err)
			}

			var serverTools generator.ServerTools
			if err := json.Unmarshal(data, &serverTools); err != nil {
				log.Fatalf("Failed to parse %s: %v", inputFile, err)
			}

			servers = append(servers, serverTools)
			log.Printf("Loaded: %s (%d tools)", serverTools.ServerName, len(serverTools.Tools))
		}
	} else {
		log.Fatal("Usage:\n" +
			"  Mode 1 (fetch from live servers):  go run cmd/main.go -config <config.json>\n" +
			"  Mode 2 (use pre-fetched data):     go run cmd/main.go -input <file1.json> -input <file2.json>\n" +
			"  Mode 3 (regenerate hierarchy):     go run cmd/main.go -regenerate -output <structure_dir>\n\n" +
			"Examples:\n" +
			"  go run cmd/main.go -config tests/test_data/test_config.json\n" +
			"  go run cmd/main.go -input tests/test_data/github_tools.json -input tests/test_data/everything_tools.json\n" +
			"  go run cmd/main.go -regenerate -output ./structure")
	}

	if len(servers) == 0 {
		log.Fatal("No servers loaded")
	}

	// Generate structure
	log.Printf("\nGenerating structure to: %s", *outputDir)
	if err := generator.GenerateStructure(servers, *outputDir); err != nil {
		log.Fatalf("Failed to generate structure: %v", err)
	}

	// Print summary
	totalTools := 0
	for _, server := range servers {
		totalTools += len(server.Tools)
	}

	fmt.Printf("\n✓ Successfully generated structure!\n")
	fmt.Printf("  Location: %s\n", *outputDir)
	fmt.Printf("  Servers: %d\n", len(servers))
	fmt.Printf("  Total tools: %d\n\n", totalTools)

	fmt.Println("Generated structure:")
	fmt.Printf("%s/\n", *outputDir)
	fmt.Println("├── root.json")
	for i, server := range servers {
		if i == len(servers)-1 {
			fmt.Printf("└── %s/\n", server.ServerName)
			fmt.Printf("    └── %s.json (%d tools)\n", server.ServerName, len(server.Tools))
		} else {
			fmt.Printf("├── %s/\n", server.ServerName)
			fmt.Printf("│   └── %s.json (%d tools)\n", server.ServerName, len(server.Tools))
		}
	}

	// Explicitly exit to terminate any hanging stdio processes
	os.Exit(0)
}

// fetchFromConfig loads config and fetches tools from all MCP servers
func fetchFromConfig(configPath string) ([]generator.ServerTools, error) {
	// Read config file
	configData, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read config: %w", err)
	}

	var config Config
	if err := json.Unmarshal(configData, &config); err != nil {
		return nil, fmt.Errorf("failed to parse config: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	var allServers []generator.ServerTools

	// Fetch from each server
	for serverName, serverConfig := range config.MCPServers {
		log.Printf("Connecting to MCP server: %s", serverName)

		serverTools, err := fetchToolsFromServer(ctx, serverName, serverConfig)

		if err != nil {
			log.Printf("⚠ Warning: Failed to fetch tools from %s: %v", serverName, err)
			continue
		}

		allServers = append(allServers, serverTools)
		log.Printf("✓ Fetched %d tools from %s", len(serverTools.Tools), serverName)
	}

	return allServers, nil
}

// fetchToolsFromServer connects to an MCP server and fetches all tools
func fetchToolsFromServer(ctx context.Context, name string, config ServerConfig) (generator.ServerTools, error) {
	// Determine transport type (default to stdio if not specified)
	transportType := config.TransportType
	if transportType == "" {
		transportType = "stdio"
	}

	// Handle different transport types
	switch transportType {
	case "stdio":
		return fetchToolsFromStdioServer(ctx, name, config)
	case "sse":
		return fetchToolsFromSSEServer(ctx, name, config)
	case "http":
		return fetchToolsFromHTTPServer(ctx, name, config)
	default:
		return generator.ServerTools{}, fmt.Errorf("unsupported transport type: %s", transportType)
	}
}

// fetchToolsFromStdioServer fetches tools from a stdio-based MCP server
func fetchToolsFromStdioServer(ctx context.Context, name string, config ServerConfig) (generator.ServerTools, error) {
	// Validate command is not empty
	if config.Command == "" {
		return generator.ServerTools{}, fmt.Errorf("command is required for stdio transport")
	}

	log.Printf("[%s] Creating stdio client: %s %v", name, config.Command, config.Args)

	// Expand environment variables in args
	expandedArgs := make([]string, len(config.Args))
	for i, arg := range config.Args {
		expandedArgs[i] = os.ExpandEnv(arg)
	}

	// Convert env map to slice (KEY=VALUE format)
	var envSlice []string
	for key, value := range config.Env {
		envSlice = append(envSlice, fmt.Sprintf("%s=%s", key, os.ExpandEnv(value)))
	}
	if len(envSlice) > 0 {
		log.Printf("[%s] Environment: %v", name, envSlice)
	}

	// Create MCP client
	mcpClient, err := client.NewStdioMCPClient(config.Command, envSlice, expandedArgs...)
	if err != nil {
		return generator.ServerTools{}, fmt.Errorf("failed to create client: %w", err)
	}
	// Note: We intentionally don't close the client here because stdio cleanup can hang.
	// The process will terminate via os.Exit(0) in main(), which cleans up all resources.

	log.Printf("[%s] Client created, initializing...", name)

	// Create our own context with timeout (don't use the passed ctx)
	localCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Initialize connection
	initRequest := mcp.InitializeRequest{}
	initRequest.Params.ProtocolVersion = mcp.LATEST_PROTOCOL_VERSION
	initRequest.Params.ClientInfo = mcp.Implementation{
		Name:    "structure-generator",
		Version: "1.0.0",
	}
	initRequest.Params.Capabilities = mcp.ClientCapabilities{}

	if _, err := mcpClient.Initialize(localCtx, initRequest); err != nil {
		return generator.ServerTools{}, fmt.Errorf("failed to initialize: %w", err)
	}

	log.Printf("[%s] Initialized successfully", name)

	// Fetch all tools
	var allTools []generator.Tool
	toolsRequest := mcp.ListToolsRequest{}

	log.Printf("[%s] Listing tools...", name)
	toolsResult, err := mcpClient.ListTools(localCtx, toolsRequest)
	if err != nil {
		return generator.ServerTools{}, fmt.Errorf("failed to list tools: %w", err)
	}

	// Convert mcp.Tool to generator.Tool
	for _, mcpTool := range toolsResult.Tools {
		tool := generator.Tool{
			Name:        mcpTool.Name,
			Description: mcpTool.Description,
			InputSchema: convertToolInputSchema(mcpTool.InputSchema),
		}
		allTools = append(allTools, tool)
	}

	return generator.ServerTools{
		ServerName: name,
		Tools:      allTools,
	}, nil
}

// fetchToolsFromSSEServer fetches tools from an SSE-based MCP server (deprecated)
func fetchToolsFromSSEServer(ctx context.Context, name string, config ServerConfig) (generator.ServerTools, error) {
	// Validate URL is not empty
	if config.URL == "" {
		return generator.ServerTools{}, fmt.Errorf("url is required for SSE transport")
	}

	log.Printf("[%s] Creating SSE client: %s", name, config.URL)

	// Create SSE MCP client
	mcpClient, err := client.NewSSEMCPClient(config.URL)
	if err != nil {
		return generator.ServerTools{}, fmt.Errorf("failed to create SSE client: %w", err)
	}
	defer mcpClient.Close()

	log.Printf("[%s] SSE client created, starting...", name)

	// Start the client with timeout
	startCtx, startCancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer startCancel()

	if err := mcpClient.Start(startCtx); err != nil {
		return generator.ServerTools{}, fmt.Errorf("failed to start SSE client: %w", err)
	}

	return fetchToolsFromRemoteClient(ctx, name, mcpClient)
}

// fetchToolsFromHTTPServer fetches tools from an HTTP Streamable MCP server
func fetchToolsFromHTTPServer(ctx context.Context, name string, config ServerConfig) (generator.ServerTools, error) {
	// Validate URL is not empty
	if config.URL == "" {
		return generator.ServerTools{}, fmt.Errorf("url is required for HTTP transport")
	}

	log.Printf("[%s] Creating HTTP Streamable client: %s", name, config.URL)

	// Create HTTP Streamable MCP client
	mcpClient, err := client.NewStreamableHttpClient(config.URL)
	if err != nil {
		return generator.ServerTools{}, fmt.Errorf("failed to create HTTP client: %w", err)
	}
	defer mcpClient.Close()

	log.Printf("[%s] HTTP client created, starting...", name)

	// Start the client with timeout
	startCtx, startCancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer startCancel()

	if err := mcpClient.Start(startCtx); err != nil {
		return generator.ServerTools{}, fmt.Errorf("failed to start HTTP client: %w", err)
	}

	return fetchToolsFromRemoteClient(ctx, name, mcpClient)
}

// fetchToolsFromRemoteClient is a helper that fetches tools from any initialized remote client
func fetchToolsFromRemoteClient(ctx context.Context, name string, mcpClient *client.Client) (generator.ServerTools, error) {
	log.Printf("[%s] Remote client started, initializing...", name)

	// Create our own context with timeout
	localCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Initialize connection
	initRequest := mcp.InitializeRequest{}
	initRequest.Params.ProtocolVersion = mcp.LATEST_PROTOCOL_VERSION
	initRequest.Params.ClientInfo = mcp.Implementation{
		Name:    "structure-generator",
		Version: "1.0.0",
	}
	initRequest.Params.Capabilities = mcp.ClientCapabilities{}

	if _, err := mcpClient.Initialize(localCtx, initRequest); err != nil {
		return generator.ServerTools{}, fmt.Errorf("failed to initialize: %w", err)
	}

	log.Printf("[%s] Initialized successfully", name)

	// Fetch all tools
	var allTools []generator.Tool
	toolsRequest := mcp.ListToolsRequest{}

	log.Printf("[%s] Listing tools...", name)
	toolsResult, err := mcpClient.ListTools(localCtx, toolsRequest)
	if err != nil {
		return generator.ServerTools{}, fmt.Errorf("failed to list tools: %w", err)
	}

	// Convert mcp.Tool to generator.Tool
	for _, mcpTool := range toolsResult.Tools {
		tool := generator.Tool{
			Name:        mcpTool.Name,
			Description: mcpTool.Description,
			InputSchema: convertToolInputSchema(mcpTool.InputSchema),
		}
		allTools = append(allTools, tool)
	}

	return generator.ServerTools{
		ServerName: name,
		Tools:      allTools,
	}, nil
}

// convertToolInputSchema converts mcp.ToolInputSchema to map[string]interface{}
func convertToolInputSchema(schema mcp.ToolInputSchema) map[string]interface{} {
	result := make(map[string]interface{})

	if schema.Type != "" {
		result["type"] = schema.Type
	}
	if len(schema.Properties) > 0 {
		result["properties"] = schema.Properties
	}
	if len(schema.Required) > 0 {
		result["required"] = schema.Required
	}

	return result
}
