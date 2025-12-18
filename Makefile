.PHONY: build clean install deploy deploy-full generate-hierarchy test install-deps fmt lint

# Build output directory
BUILD_DIR := build
BINARY := mcp-proxy
STRUCTURE_GEN := structure_generator

# Default deployment paths (can be overridden)
LAZY_MCP_DIR ?= $(HOME)/.claude/lazy-mcp
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
	@echo "Deploying binary to $(LAZY_MCP_DIR)..."
	@mkdir -p $(LAZY_MCP_DIR)
	cp $(BUILD_DIR)/$(BINARY) $(LAZY_MCP_DIR)/
	cp $(BUILD_DIR)/$(STRUCTURE_GEN) $(LAZY_MCP_DIR)/
	chmod +x $(LAZY_MCP_DIR)/$(BINARY)
	chmod +x $(LAZY_MCP_DIR)/$(STRUCTURE_GEN)
	@echo "Binary deployed. Config and hierarchy unchanged."

# Generate hierarchy from config
generate-hierarchy: build
	@echo "Generating tool hierarchy to $(LAZY_MCP_DIR)/hierarchy..."
	@mkdir -p $(LAZY_MCP_DIR)/hierarchy
	@if [ -f $(LAZY_MCP_DIR)/config.json ]; then \
		./$(BUILD_DIR)/$(STRUCTURE_GEN) --config $(LAZY_MCP_DIR)/config.json --output $(LAZY_MCP_DIR)/hierarchy; \
	elif [ -f $(CONFIG_FILE) ]; then \
		./$(BUILD_DIR)/$(STRUCTURE_GEN) --config $(CONFIG_FILE) --output $(LAZY_MCP_DIR)/hierarchy; \
	else \
		echo "No config file found. Create $(LAZY_MCP_DIR)/config.json or $(CONFIG_FILE)"; \
		exit 1; \
	fi
	@echo "Hierarchy generated at $(LAZY_MCP_DIR)/hierarchy/"

# Full deploy: binary + config + regenerate hierarchy
deploy-full: deploy generate-hierarchy
	@echo "Full deploy complete!"
	@echo ""
	@echo "Add to ~/.claude.json if not already present:"
	@echo '  "mcpServers": {'
	@echo '    "lazy-mcp": {'
	@echo '      "type": "stdio",'
	@echo '      "command": "$(LAZY_MCP_DIR)/$(BINARY)",'
	@echo '      "args": ["--config", "$(LAZY_MCP_DIR)/config.json"]'
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
	@echo "lazy-mcp-preload Makefile"
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
	@echo "  LAZY_MCP_DIR       Install directory (default: ~/.claude/lazy-mcp)"
	@echo "  MCP_SERVERS_DIR    MCP servers directory (default: ~/.claude/mcp-servers)"
	@echo "  CONFIG_FILE        Config file to use (default: config/config.local.json)"
	@echo ""
	@echo "Examples:"
	@echo "  make install"
	@echo "  make deploy LAZY_MCP_DIR=/custom/path"
	@echo "  make generate-hierarchy"
