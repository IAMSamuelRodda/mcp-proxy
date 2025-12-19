#!/bin/bash
# install.sh - Lightweight mcp-proxy binary installation
#
# Use this if you already have MCP servers installed and just need the proxy.
# For full setup (MCP servers + proxy), use bootstrap.sh instead.
#
# What this does:
#   - Builds mcp-proxy binary
#   - Deploys to ~/.claude/mcp-proxy/
#   - Updates ~/.claude.json
#
# What this does NOT do:
#   - Install MCP servers (use bootstrap.sh for that)
#   - Install secrets infrastructure (use bootstrap.sh --secure)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default installation paths (can be overridden)
MCP_PROXY_DIR="${MCP_PROXY_DIR:-$HOME/.claude/mcp-proxy}"
MCP_SERVERS_DIR="${MCP_SERVERS_DIR:-$HOME/.claude/mcp-servers}"
CLAUDE_JSON="${CLAUDE_JSON:-$HOME/.claude.json}"

echo -e "${GREEN}=== mcp-proxy Installation ===${NC}"
echo ""
echo "Installation paths:"
echo "  MCP_PROXY_DIR:    $MCP_PROXY_DIR"
echo "  MCP_SERVERS_DIR: $MCP_SERVERS_DIR"
echo "  CLAUDE_JSON:     $CLAUDE_JSON"
echo ""

# Check for Go installation
check_go() {
    if ! command -v go &> /dev/null; then
        echo -e "${RED}Error: Go is not installed${NC}"
        echo "Install Go from https://go.dev/dl/ or run:"
        echo "  ./scripts/install-go.sh"
        exit 1
    fi
    echo -e "${GREEN}[OK]${NC} Go $(go version | awk '{print $3}')"
}

# Build the binary
build_binary() {
    echo ""
    echo "[1/5] Building binary..."
    cd "$PROJECT_DIR"

    mkdir -p build
    go mod download
    go build -ldflags "-s -w" -o build/mcp-proxy ./cmd/mcp-proxy
    go build -ldflags "-s -w" -o build/structure_generator ./structure_generator/cmd

    echo -e "${GREEN}[OK]${NC} Binary built: build/mcp-proxy"
}

# Create installation directories
setup_directories() {
    echo ""
    echo "[2/5] Setting up directories..."

    mkdir -p "$MCP_PROXY_DIR"
    mkdir -p "$MCP_PROXY_DIR/hierarchy"
    mkdir -p "$MCP_SERVERS_DIR"

    echo -e "${GREEN}[OK]${NC} Directories created"
}

# Install binary
install_binary() {
    echo ""
    echo "[3/5] Installing binary..."

    # Clean up any stale .new files from failed previous runs
    rm -f "$MCP_PROXY_DIR"/*.new
    # Atomic replacement to avoid "Text file busy" when binary is running
    cp "$PROJECT_DIR/build/mcp-proxy" "$MCP_PROXY_DIR/mcp-proxy.new"
    cp "$PROJECT_DIR/build/structure_generator" "$MCP_PROXY_DIR/structure_generator.new"
    chmod +x "$MCP_PROXY_DIR/mcp-proxy.new" "$MCP_PROXY_DIR/structure_generator.new"
    mv -f "$MCP_PROXY_DIR/mcp-proxy.new" "$MCP_PROXY_DIR/mcp-proxy"
    mv -f "$MCP_PROXY_DIR/structure_generator.new" "$MCP_PROXY_DIR/structure_generator"

    echo -e "${GREEN}[OK]${NC} Binary installed to $MCP_PROXY_DIR/mcp-proxy"
}

# Generate config from template
generate_config() {
    echo ""
    echo "[4/5] Generating configuration..."

    CONFIG_FILE="$MCP_PROXY_DIR/config.json"

    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}[WARN]${NC} Config file already exists: $CONFIG_FILE"
        echo "       Keeping existing configuration."
        echo "       To regenerate, delete and re-run install."
        return 0
    fi

    # Check if user has a custom config template
    if [ -f "$PROJECT_DIR/config/config.local.json" ]; then
        echo "Using custom config: config/config.local.json"
        # Expand environment variables in the template
        export MCP_PROXY_DIR MCP_SERVERS_DIR
        envsubst < "$PROJECT_DIR/config/config.local.json" > "$CONFIG_FILE"
    else
        # Create minimal default config
        cat > "$CONFIG_FILE" << EOF
{
  "mcpProxy": {
    "name": "MCP Proxy",
    "version": "1.0.0",
    "type": "stdio",
    "hierarchyPath": "$MCP_PROXY_DIR/hierarchy",
    "options": {
      "logEnabled": true,
      "lazyLoad": true,
      "preloadAll": true
    }
  },
  "mcpServers": {}
}
EOF
        echo -e "${YELLOW}[INFO]${NC} Created minimal config. Add your MCP servers to:"
        echo "       $CONFIG_FILE"
    fi

    echo -e "${GREEN}[OK]${NC} Configuration created"
}

# Update Claude Code configuration
update_claude_config() {
    echo ""
    echo "[5/5] Updating Claude Code configuration..."

    if [ ! -f "$CLAUDE_JSON" ]; then
        echo -e "${YELLOW}[WARN]${NC} $CLAUDE_JSON not found"
        echo "       Create it manually or let Claude Code create it on first run."
        echo ""
        echo "Add this to your ~/.claude.json mcpServers:"
        echo ""
        echo "  \"mcp-proxy\": {"
        echo "    \"type\": \"stdio\","
        echo "    \"command\": \"$MCP_PROXY_DIR/mcp-proxy\","
        echo "    \"args\": [\"--config\", \"$MCP_PROXY_DIR/config.json\"]"
        echo "  }"
        return 0
    fi

    # Backup existing config
    BACKUP="$CLAUDE_JSON.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CLAUDE_JSON" "$BACKUP"
    echo "Backed up config to: $BACKUP"

    # Check if mcp-proxy entry already exists
    if grep -q '"mcp-proxy"' "$CLAUDE_JSON"; then
        echo -e "${YELLOW}[WARN]${NC} mcp-proxy entry already exists in $CLAUDE_JSON"
        echo "       Please verify the configuration manually."
        return 0
    fi

    # Add mcp-proxy using Python (handles JSON properly)
    python3 << PYTHON_SCRIPT
import json
import sys

config_path = "$CLAUDE_JSON"
lazy_mcp_dir = "$MCP_PROXY_DIR"

try:
    with open(config_path, 'r') as f:
        config = json.load(f)
except json.JSONDecodeError as e:
    print(f"Error: Invalid JSON in {config_path}: {e}")
    sys.exit(1)

# Ensure mcpServers exists
if 'mcpServers' not in config:
    config['mcpServers'] = {}

# Add mcp-proxy
config['mcpServers']['mcp-proxy'] = {
    "type": "stdio",
    "command": f"{lazy_mcp_dir}/mcp-proxy",
    "args": ["--config", f"{lazy_mcp_dir}/config.json"]
}

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)

print("Updated ~/.claude.json with mcp-proxy")
PYTHON_SCRIPT

    echo -e "${GREEN}[OK]${NC} Claude Code configuration updated"
}

# Main installation
main() {
    check_go
    build_binary
    setup_directories
    install_binary
    generate_config
    update_claude_config

    echo ""
    echo -e "${GREEN}=== Installation Complete ===${NC}"
    echo ""
    echo "Installed files:"
    echo "  $MCP_PROXY_DIR/mcp-proxy"
    echo "  $MCP_PROXY_DIR/config.json"
    echo "  $MCP_PROXY_DIR/hierarchy/"
    echo ""
    echo "Next steps:"
    echo "  1. Add MCP servers to $MCP_PROXY_DIR/config.json"
    echo "  2. Generate hierarchy: $MCP_PROXY_DIR/structure_generator --config $MCP_PROXY_DIR/config.json --output $MCP_PROXY_DIR/hierarchy"
    echo "  3. Restart Claude Code"
    echo ""
    echo "To test: claude mcp list"
    echo "To view logs: The proxy logs to stderr (visible in Claude Code logs)"
    echo ""
    echo "To uninstall: rm -rf $MCP_PROXY_DIR"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mcp-proxy-dir)
            MCP_PROXY_DIR="$2"
            shift 2
            ;;
        --mcp-servers-dir)
            MCP_SERVERS_DIR="$2"
            shift 2
            ;;
        --claude-json)
            CLAUDE_JSON="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --mcp-proxy-dir DIR     Installation directory (default: ~/.claude/mcp-proxy)"
            echo "  --mcp-servers-dir DIR  MCP servers directory (default: ~/.claude/mcp-servers)"
            echo "  --claude-json FILE     Claude config file (default: ~/.claude.json)"
            echo "  -h, --help             Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

main
