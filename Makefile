.PHONY: build clean install deploy deploy-full generate-hierarchy test install-deps fmt lint

# Build output directory
BUILD_DIR := build
BINARY := mcp-proxy
STRUCTURE_GEN := structure_generator

# Default deployment paths (can be overridden)
MCP_PROXY_DIR ?= $(HOME)/.claude/mcp-proxy
MCP_SERVERS_DIR ?= $(HOME)/.claude/mcp-servers
CONFIG_FILE ?= config/config.local.json

# Go build flags
LDFLAGS := -ldflags "-s -w"

# Build both binaries
build: install-deps
	@echo "Building $(BINARY)..."
	@mkdir -p $(BUILD_DIR)
	go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY) ./cmd/mcp-proxy
	go build $(LDFLAGS) -o $(BUILD_DIR)/$(STRUCTURE_GEN) ./structure_generator/cmd
	@echo "Build complete: $(BUILD_DIR)/$(BINARY)"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
	@echo "Clean complete"

# Install dependencies
install-deps:
	@echo "Checking Go installation..."
	@which go > /dev/null || (echo "Go not installed. Run: ./scripts/install-go.sh" && exit 1)
	@echo "Installing dependencies..."
	go mod download
	go mod tidy

# Full installation using the install script
install: build
	@echo "Running install script..."
	./scripts/install.sh

# Deploy only the binary (safe - doesn't touch config or hierarchy)
deploy: build
	@echo "Deploying binary to $(MCP_PROXY_DIR)..."
	@mkdir -p $(MCP_PROXY_DIR)
	cp $(BUILD_DIR)/$(BINARY) $(MCP_PROXY_DIR)/
	cp $(BUILD_DIR)/$(STRUCTURE_GEN) $(MCP_PROXY_DIR)/
	chmod +x $(MCP_PROXY_DIR)/$(BINARY)
	chmod +x $(MCP_PROXY_DIR)/$(STRUCTURE_GEN)
	@echo "Binary deployed. Config and hierarchy unchanged."

# Generate hierarchy from config
generate-hierarchy: build
	@echo "Generating tool hierarchy to $(MCP_PROXY_DIR)/hierarchy..."
	@mkdir -p $(MCP_PROXY_DIR)/hierarchy
	@if [ -f $(MCP_PROXY_DIR)/config.json ]; then \
		./$(BUILD_DIR)/$(STRUCTURE_GEN) --config $(MCP_PROXY_DIR)/config.json --output $(MCP_PROXY_DIR)/hierarchy; \
	elif [ -f $(CONFIG_FILE) ]; then \
		./$(BUILD_DIR)/$(STRUCTURE_GEN) --config $(CONFIG_FILE) --output $(MCP_PROXY_DIR)/hierarchy; \
	else \
		echo "No config file found. Create $(MCP_PROXY_DIR)/config.json or $(CONFIG_FILE)"; \
		exit 1; \
	fi
	@echo "Hierarchy generated at $(MCP_PROXY_DIR)/hierarchy/"

# Full deploy: binary + config + regenerate hierarchy
deploy-full: deploy generate-hierarchy
	@echo "Full deploy complete!"
	@echo ""
	@echo "Add to ~/.claude.json if not already present:"
	@echo '  "mcpServers": {'
	@echo '    "mcp-proxy": {'
	@echo '      "type": "stdio",'
	@echo '      "command": "$(MCP_PROXY_DIR)/$(BINARY)",'
	@echo '      "args": ["--config", "$(MCP_PROXY_DIR)/config.json"]'
	@echo '    }'
	@echo '  }'

# Run tests
test:
	@echo "Running tests..."
	go test -v ./...

# Development helpers
dev-run: build
	./$(BUILD_DIR)/$(BINARY) --config $(CONFIG_FILE)

# Format code
fmt:
	go fmt ./...

# Lint code
lint:
	golangci-lint run

# Show help
help:
	@echo "mcp-proxy Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  build              Build the mcp-proxy binary"
	@echo "  clean              Remove build artifacts"
	@echo "  install            Full installation (build + deploy + config)"
	@echo "  deploy             Deploy binary only (preserves config)"
	@echo "  deploy-full        Deploy binary and regenerate hierarchy"
	@echo "  generate-hierarchy Generate tool hierarchy from config"
	@echo "  test               Run tests"
	@echo "  fmt                Format code"
	@echo "  lint               Run linter"
	@echo ""
	@echo "Variables (can be overridden):"
	@echo "  MCP_PROXY_DIR       Install directory (default: ~/.claude/mcp-proxy)"
	@echo "  MCP_SERVERS_DIR    MCP servers directory (default: ~/.claude/mcp-servers)"
	@echo "  CONFIG_FILE        Config file to use (default: config/config.local.json)"
	@echo ""
	@echo "Examples:"
	@echo "  make install"
	@echo "  make deploy MCP_PROXY_DIR=/custom/path"
	@echo "  make generate-hierarchy"
