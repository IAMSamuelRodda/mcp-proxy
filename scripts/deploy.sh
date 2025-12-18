#!/bin/bash
# Deploy mcp-proxy to Claude Code

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEPLOY_DIR="/home/samuelrodda/.claude/mcp-proxy"
CLAUDE_JSON="/home/samuelrodda/.claude.json"

cd "$PROJECT_DIR"

echo "=== mcp-proxy Deployment ==="
echo ""

# Build
echo "[1/4] Building..."
make build

# Generate hierarchy
echo "[2/4] Generating tool hierarchy..."
make generate-hierarchy

# Deploy files
echo "[3/4] Deploying to ${DEPLOY_DIR}..."
mkdir -p "${DEPLOY_DIR}"
cp build/mcp-proxy "${DEPLOY_DIR}/"
cp config/config.json "${DEPLOY_DIR}/"
cp -r deploy/hierarchy "${DEPLOY_DIR}/"

# Make binary executable
chmod +x "${DEPLOY_DIR}/mcp-proxy"

# Update Claude config
echo "[4/4] Updating Claude Code configuration..."

if [ -f "$CLAUDE_JSON" ]; then
    # Backup existing config
    cp "$CLAUDE_JSON" "${CLAUDE_JSON}.backup.$(date +%Y%m%d_%H%M%S)"

    # Check if mcp-proxy entry already exists
    if grep -q '"mcp-proxy"' "$CLAUDE_JSON"; then
        echo "mcp-proxy entry already exists in ${CLAUDE_JSON}"
        echo "Please verify the configuration manually."
    else
        # Add mcp-proxy to mcpServers using Python
        python3 << 'PYTHON_SCRIPT'
import json
import sys

config_path = "/home/samuelrodda/.claude.json"

with open(config_path, 'r') as f:
    config = json.load(f)

# Ensure mcpServers exists
if 'mcpServers' not in config:
    config['mcpServers'] = {}

# Remove old direct MCP servers (they're now proxied)
servers_to_remove = ['joplin', 'todoist', 'nextcloud-calendar']
for server in servers_to_remove:
    if server in config['mcpServers']:
        print(f"Removing direct server: {server}")
        del config['mcpServers'][server]

# Add mcp-proxy
config['mcpServers']['mcp-proxy'] = {
    "type": "stdio",
    "command": "/home/samuelrodda/.claude/mcp-proxy/mcp-proxy",
    "args": ["--config", "/home/samuelrodda/.claude/mcp-proxy/config.json"]
}

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)

print("Updated ~/.claude.json with mcp-proxy")
PYTHON_SCRIPT
    fi
else
    echo "Warning: ${CLAUDE_JSON} not found"
    echo "Create it manually with the mcp-proxy configuration"
fi

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Deployed files:"
echo "  ${DEPLOY_DIR}/mcp-proxy"
echo "  ${DEPLOY_DIR}/config.json"
echo "  ${DEPLOY_DIR}/hierarchy/"
echo ""
echo "To test: claude mcp list"
echo "To revert: cp ${CLAUDE_JSON}.backup.* ${CLAUDE_JSON}"
