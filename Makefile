.PHONY: build clean deploy deploy-full deploy-hierarchy generate-hierarchy test install-deps

# Build output directory
BUILD_DIR := build
BINARY := mcp-proxy
STRUCTURE_GEN := structure_generator

# Deployment paths
DEPLOY_DIR := /home/x-forge/.claude/lazy-mcp
CONFIG_FILE := config/config.json

# Go build flags
LDFLAGS := -ldflags "-s -w"

build: install-deps
	@echo "Building $(BINARY)..."
	@mkdir -p $(BUILD_DIR)
	go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY) ./cmd/mcp-proxy
	go build $(LDFLAGS) -o $(BUILD_DIR)/$(STRUCTURE_GEN) ./structure_generator/cmd
	@echo "Build complete: $(BUILD_DIR)/$(BINARY)"

clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
	@echo "Clean complete"

install-deps:
	@echo "Checking Go installation..."
	@which go > /dev/null || (echo "Go not installed. Run: ./scripts/install-go.sh" && exit 1)
	@echo "Installing dependencies..."
	go mod download
	go mod tidy

generate-hierarchy: build
	@echo "Generating tool hierarchy..."
	@mkdir -p deploy/hierarchy
	./$(BUILD_DIR)/$(STRUCTURE_GEN) --config $(CONFIG_FILE) --output deploy/hierarchy
	@echo "Hierarchy generated in deploy/hierarchy/"

# Deploy only the binary (safe - doesn't touch config or hierarchy)
deploy: build
	@echo "Deploying binary to $(DEPLOY_DIR)..."
	@mkdir -p $(DEPLOY_DIR)
	cp $(BUILD_DIR)/$(BINARY) $(DEPLOY_DIR)/
	@echo "Binary deployed. Config and hierarchy unchanged."

# Deploy hierarchy from repo to install location
deploy-hierarchy:
	@echo "Deploying hierarchy to $(DEPLOY_DIR)..."
	@if [ ! -d deploy/hierarchy ]; then \
		echo "ERROR: deploy/hierarchy not found. Run 'make generate-hierarchy' first."; \
		exit 1; \
	fi
	cp -r deploy/hierarchy $(DEPLOY_DIR)/
	@echo "Hierarchy deployed."

# Full deploy: binary + config + hierarchy (use with caution)
deploy-full: build
	@echo "Full deploy to $(DEPLOY_DIR)..."
	@mkdir -p $(DEPLOY_DIR)
	cp $(BUILD_DIR)/$(BINARY) $(DEPLOY_DIR)/
	@if [ -f $(CONFIG_FILE) ]; then \
		cp $(CONFIG_FILE) $(DEPLOY_DIR)/; \
	else \
		echo "No config/config.json - keeping existing config"; \
	fi
	@if [ -d deploy/hierarchy ]; then \
		cp -r deploy/hierarchy $(DEPLOY_DIR)/; \
	else \
		echo "No deploy/hierarchy - keeping existing hierarchy"; \
	fi
	@echo ""
	@echo "Deployment complete!"
	@echo ""
	@echo "Add to ~/.claude.json:"
	@echo '  "mcpServers": {'
	@echo '    "lazy-mcp": {'
	@echo '      "type": "stdio",'
	@echo '      "command": "$(DEPLOY_DIR)/$(BINARY)",'
	@echo '      "args": ["--config", "$(DEPLOY_DIR)/config.json"]'
	@echo '    }'
	@echo '  }'

test:
	@echo "Running tests..."
	go test -v ./...

# Development helpers
dev-run: build
	./$(BUILD_DIR)/$(BINARY) --config $(CONFIG_FILE)

fmt:
	go fmt ./...

lint:
	golangci-lint run
