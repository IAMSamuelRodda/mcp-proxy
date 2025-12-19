#!/bin/bash
# bootstrap.sh - Full workstation setup for MCP proxy infrastructure
#
# Orchestrates installation of:
# 1. bitwarden-guard (session management)
# 2. openbao-agents (secrets access)
# 3. MCP servers (Python venvs)
# 4. mcp-proxy (this project)
#
# Prerequisites:
# - Git repos cloned to expected locations
# - Python 3.11+ installed
# - Go 1.21+ installed (or will prompt to install)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1" >&2; }
log_section() { echo -e "\n${BLUE}===${NC} $1 ${BLUE}===${NC}"; }

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# GitHub URLs for dependencies
BITWARDEN_GUARD_URL="https://github.com/IAMSamuelRodda/bitwarden-guard.git"
OPENBAO_AGENTS_URL="https://github.com/IAMSamuelRodda/openbao-agents.git"

# Default paths (can be overridden via environment)
DEPS_DIR="${DEPS_DIR:-$HOME/.claude/deps}"
BITWARDEN_GUARD_REPO="${BITWARDEN_GUARD_REPO:-$DEPS_DIR/bitwarden-guard}"
OPENBAO_AGENTS_REPO="${OPENBAO_AGENTS_REPO:-$DEPS_DIR/openbao-agents}"
MCP_SERVERS_DIR="${MCP_SERVERS_DIR:-$HOME/.claude/mcp-servers}"
MCP_PROXY_DIR="${MCP_PROXY_DIR:-$HOME/.claude/mcp-proxy}"

# Track what was installed
INSTALLED=()
SKIPPED=()
FAILED=()

check_python() {
    if ! command -v python3 &>/dev/null; then
        log_error "Python 3 not found"
        exit 1
    fi

    PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    if [[ $(echo "$PYTHON_VERSION < 3.11" | bc -l) -eq 1 ]]; then
        log_warn "Python $PYTHON_VERSION found, recommend 3.11+"
    else
        log_info "Python $PYTHON_VERSION"
    fi
}

check_uv() {
    if ! command -v uv &>/dev/null; then
        log_warn "uv not found, will use pip (slower)"
        return 1
    fi
    log_info "uv found (fast package installs)"
    return 0
}

# Step 1: bitwarden-guard
install_bitwarden_guard() {
    log_section "Step 1/4: bitwarden-guard"

    if command -v bitwarden-guard &>/dev/null; then
        log_info "bitwarden-guard already installed"
        SKIPPED+=("bitwarden-guard")
        return 0
    fi

    # Clone if not exists
    if [ ! -d "$BITWARDEN_GUARD_REPO" ]; then
        log_info "Cloning bitwarden-guard from GitHub..."
        mkdir -p "$DEPS_DIR"
        if ! git clone "$BITWARDEN_GUARD_URL" "$BITWARDEN_GUARD_REPO"; then
            log_error "Failed to clone bitwarden-guard"
            FAILED+=("bitwarden-guard")
            return 1
        fi
    fi

    log_info "Installing bitwarden-guard..."
    cd "$BITWARDEN_GUARD_REPO"
    if ./install.sh; then
        log_info "bitwarden-guard installed"
        INSTALLED+=("bitwarden-guard")
    else
        log_error "bitwarden-guard installation failed"
        FAILED+=("bitwarden-guard")
        return 1
    fi
}

# Step 2: openbao-agents
install_openbao_agents() {
    log_section "Step 2/4: openbao-agents"

    if command -v start-openbao-mcp &>/dev/null; then
        log_info "openbao-agents already installed"
        SKIPPED+=("openbao-agents")
        return 0
    fi

    # Clone if not exists
    if [ ! -d "$OPENBAO_AGENTS_REPO" ]; then
        log_info "Cloning openbao-agents from GitHub..."
        mkdir -p "$DEPS_DIR"
        if ! git clone "$OPENBAO_AGENTS_URL" "$OPENBAO_AGENTS_REPO"; then
            log_error "Failed to clone openbao-agents"
            FAILED+=("openbao-agents")
            return 1
        fi
    fi

    log_info "Installing openbao-agents..."
    cd "$OPENBAO_AGENTS_REPO"
    if ./install.sh; then
        log_info "openbao-agents installed"
        INSTALLED+=("openbao-agents")
    else
        log_error "openbao-agents installation failed"
        FAILED+=("openbao-agents")
        return 1
    fi
}

# Step 3: MCP servers
install_mcp_servers() {
    log_section "Step 3/4: MCP servers"

    if [ ! -d "$MCP_SERVERS_DIR" ]; then
        log_warn "MCP servers directory not found: $MCP_SERVERS_DIR"
        log_warn "Skipping MCP server venv setup"
        return 0
    fi

    local use_uv=false
    check_uv && use_uv=true

    for server_dir in "$MCP_SERVERS_DIR"/*/; do
        server_name=$(basename "$server_dir")

        # Skip if no Python files
        if ! ls "$server_dir"/*.py &>/dev/null && ! ls "$server_dir"/src/*.py &>/dev/null; then
            continue
        fi

        # Check for existing venv
        if [ -d "$server_dir/.venv" ]; then
            log_info "$server_name: venv exists"
            SKIPPED+=("mcp-$server_name")
            continue
        fi

        log_info "$server_name: creating venv..."
        cd "$server_dir"

        python3 -m venv .venv
        source .venv/bin/activate

        # Install dependencies
        if [ -f "pyproject.toml" ]; then
            if $use_uv; then
                uv pip install -e . 2>/dev/null || uv pip install -r requirements.txt 2>/dev/null || pip install -e .
            else
                pip install -e . 2>/dev/null || pip install -r requirements.txt 2>/dev/null
            fi
        elif [ -f "requirements.txt" ]; then
            if $use_uv; then
                uv pip install -r requirements.txt
            else
                pip install -r requirements.txt
            fi
        fi

        deactivate
        log_info "$server_name: venv created"
        INSTALLED+=("mcp-$server_name")
    done
}

# Step 4: mcp-proxy
install_mcp_proxy() {
    log_section "Step 4/4: mcp-proxy"

    cd "$PROJECT_DIR"

    # Check for config.local.json
    if [ ! -f "config/config.local.json" ]; then
        log_error "config/config.local.json not found!"
        log_error "Copy from config/config.template.json and configure for your machine"
        FAILED+=("mcp-proxy")
        return 1
    fi

    # Check Go
    if ! command -v go &>/dev/null; then
        log_warn "Go not installed. Run: ./scripts/install-go.sh"
        FAILED+=("mcp-proxy")
        return 1
    fi
    log_info "Go $(go version | awk '{print $3}')"

    # Build
    log_info "Building mcp-proxy..."
    make build

    # Deploy
    log_info "Deploying binaries..."
    mkdir -p "$MCP_PROXY_DIR"
    cp build/mcp-proxy "$MCP_PROXY_DIR/"
    cp build/structure_generator "$MCP_PROXY_DIR/"
    chmod +x "$MCP_PROXY_DIR/mcp-proxy" "$MCP_PROXY_DIR/structure_generator"

    # Config
    log_info "Copying configuration..."
    cp config/config.local.json "$MCP_PROXY_DIR/config.json"

    # Generate hierarchy
    log_info "Generating tool hierarchy..."
    "$MCP_PROXY_DIR/structure_generator" \
        --config "$MCP_PROXY_DIR/config.json" \
        --output "$MCP_PROXY_DIR/hierarchy"

    log_info "mcp-proxy installed"
    INSTALLED+=("mcp-proxy")
}

# Refresh only: skip deps, just update config and regenerate hierarchy
refresh_only() {
    log_section "Refreshing mcp-proxy (config + hierarchy)"

    cd "$PROJECT_DIR"

    if [ ! -f "config/config.local.json" ]; then
        log_error "config/config.local.json not found!"
        exit 1
    fi

    if [ ! -f "$MCP_PROXY_DIR/structure_generator" ]; then
        log_error "structure_generator not found. Run full bootstrap first."
        exit 1
    fi

    log_info "Copying configuration..."
    cp config/config.local.json "$MCP_PROXY_DIR/config.json"

    log_info "Generating tool hierarchy..."
    "$MCP_PROXY_DIR/structure_generator" \
        --config "$MCP_PROXY_DIR/config.json" \
        --output "$MCP_PROXY_DIR/hierarchy"

    log_info "Refresh complete!"
    echo ""
    echo "Restart Claude Code to pick up changes."
}

# Summary
print_summary() {
    log_section "Installation Summary"

    if [ ${#INSTALLED[@]} -gt 0 ]; then
        echo -e "${GREEN}Installed:${NC}"
        for item in "${INSTALLED[@]}"; do
            echo "  ✓ $item"
        done
    fi

    if [ ${#SKIPPED[@]} -gt 0 ]; then
        echo -e "${YELLOW}Already installed:${NC}"
        for item in "${SKIPPED[@]}"; do
            echo "  ⊘ $item"
        done
    fi

    if [ ${#FAILED[@]} -gt 0 ]; then
        echo -e "${RED}Failed:${NC}"
        for item in "${FAILED[@]}"; do
            echo "  ✗ $item"
        done
        echo ""
        echo "Fix the issues above and re-run: $0"
        return 1
    fi

    echo ""
    log_info "Bootstrap complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Configure Bitwarden items for OpenBao (see openbao-agents docs)"
    echo "  2. Restart Claude Code to pick up new MCP proxy"
    echo "  3. Test: claude mcp list"
}

# Main
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}     MCP Proxy Infrastructure Bootstrap              ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This script will install:"
    echo "  1. bitwarden-guard  (session management)"
    echo "  2. openbao-agents   (secrets access)"
    echo "  3. MCP servers      (Python venvs)"
    echo "  4. mcp-proxy        (aggregating proxy)"
    echo ""

    check_python

    install_bitwarden_guard || true
    install_openbao_agents || true
    install_mcp_servers || true
    install_mcp_proxy || true

    print_summary
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Bootstrap full MCP proxy infrastructure on a new workstation."
        echo "Dependencies are cloned from GitHub automatically if not present."
        echo ""
        echo "Options:"
        echo "  --refresh    Skip deps, just update config and regenerate hierarchy"
        echo "  -h, --help   Show this help"
        echo ""
        echo "GitHub repos:"
        echo "  bitwarden-guard: $BITWARDEN_GUARD_URL"
        echo "  openbao-agents:  $OPENBAO_AGENTS_URL"
        echo ""
        echo "Environment variables:"
        echo "  DEPS_DIR               Dependencies clone directory (default: ~/.claude/deps)"
        echo "  BITWARDEN_GUARD_REPO   Override bitwarden-guard repo path"
        echo "  OPENBAO_AGENTS_REPO    Override openbao-agents repo path"
        echo "  MCP_SERVERS_DIR        MCP servers directory (default: ~/.claude/mcp-servers)"
        echo "  MCP_PROXY_DIR          mcp-proxy install directory (default: ~/.claude/mcp-proxy)"
        echo ""
        echo "Examples:"
        echo "  $0              # Full bootstrap (first time setup)"
        echo "  $0 --refresh    # Just added a new server to config.local.json"
        exit 0
        ;;
    --refresh)
        refresh_only
        ;;
    *)
        main
        ;;
esac
