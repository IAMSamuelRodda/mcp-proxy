#!/bin/bash
# bootstrap.sh - Full workstation setup for MCP proxy infrastructure
#
# Installs:
# 1. bitwarden-guard (session management)
# 2. openbao-agents (secrets access)
# 3. MCP servers (from source definitions in config)
# 4. mcp-proxy (this project)
#
# Flags:
#   (none)      Full bootstrap - install/update everything
#   --refresh   Config + hierarchy only (skip source updates)
#   --force     Clean reinstall of all MCP servers

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

# GitHub URLs for core dependencies
BITWARDEN_GUARD_URL="https://github.com/IAMSamuelRodda/bitwarden-guard.git"
OPENBAO_AGENTS_URL="https://github.com/IAMSamuelRodda/openbao-agents.git"

# Default paths
DEPS_DIR="${DEPS_DIR:-$HOME/.claude/deps}"
BITWARDEN_GUARD_REPO="${BITWARDEN_GUARD_REPO:-$DEPS_DIR/bitwarden-guard}"
OPENBAO_AGENTS_REPO="${OPENBAO_AGENTS_REPO:-$DEPS_DIR/openbao-agents}"
MCP_SERVERS_DIR="${MCP_SERVERS_DIR:-$HOME/.claude/mcp-servers}"
MCP_PROXY_DIR="${MCP_PROXY_DIR:-$HOME/.claude/mcp-proxy}"
CONFIG_FILE="$PROJECT_DIR/config/config.local.json"

# Flags
FORCE_REINSTALL=false

# Track results
INSTALLED=()
UPDATED=()
SKIPPED=()
FAILED=()

check_dependencies() {
    log_section "Checking dependencies"

    # Python
    if ! command -v python3 &>/dev/null; then
        log_error "Python 3 not found"
        exit 1
    fi
    log_info "Python $(python3 --version | awk '{print $2}')"

    # jq for JSON parsing
    if ! command -v jq &>/dev/null; then
        log_error "jq not found. Install: sudo apt install jq"
        exit 1
    fi
    log_info "jq found"

    # envsubst for variable expansion
    if ! command -v envsubst &>/dev/null; then
        log_error "envsubst not found. Install: sudo apt install gettext-base"
        exit 1
    fi
    log_info "envsubst found"

    # uv (optional, faster)
    if command -v uv &>/dev/null; then
        log_info "uv found (fast package installs)"
        USE_UV=true
    else
        log_warn "uv not found, using pip"
        USE_UV=false
    fi
}

# Compute hash of dependency files
compute_deps_hash() {
    local dir="$1"
    local hash=""

    if [ -f "$dir/pyproject.toml" ]; then
        hash=$(md5sum "$dir/pyproject.toml" 2>/dev/null | cut -d' ' -f1)
    elif [ -f "$dir/requirements.txt" ]; then
        hash=$(md5sum "$dir/requirements.txt" 2>/dev/null | cut -d' ' -f1)
    fi

    echo "$hash"
}

# Install Python venv for a server
install_venv() {
    local server_dir="$1"
    local server_name="$2"

    cd "$server_dir"

    # Check if deps changed
    local current_hash=$(compute_deps_hash "$server_dir")
    local hash_file="$server_dir/.deps_hash"
    local old_hash=""
    [ -f "$hash_file" ] && old_hash=$(cat "$hash_file")

    if [ -d ".venv" ] && [ "$current_hash" = "$old_hash" ] && [ "$FORCE_REINSTALL" = false ]; then
        log_info "$server_name: venv up to date"
        return 0
    fi

    # Create/recreate venv
    if [ -d ".venv" ]; then
        log_info "$server_name: rebuilding venv (deps changed)"
        rm -rf .venv
    else
        log_info "$server_name: creating venv"
    fi

    python3 -m venv .venv
    source .venv/bin/activate

    # Install deps
    if [ -f "pyproject.toml" ]; then
        if $USE_UV; then
            uv pip install -e . 2>/dev/null || pip install -e .
        else
            pip install -e .
        fi
    elif [ -f "requirements.txt" ]; then
        if $USE_UV; then
            uv pip install -r requirements.txt
        else
            pip install -r requirements.txt
        fi
    fi

    deactivate

    # Save hash
    echo "$current_hash" > "$hash_file"
}

# Install/update a single MCP server from source
install_mcp_server() {
    local name="$1"
    local source_type="$2"
    local source_location="$3"
    local server_dir="$MCP_SERVERS_DIR/$name"

    log_info "Processing: $name"

    mkdir -p "$MCP_SERVERS_DIR"

    if [ "$source_type" = "git" ]; then
        if [ -d "$server_dir" ]; then
            if [ "$FORCE_REINSTALL" = true ]; then
                log_info "$name: force reinstall - removing existing"
                # Preserve .venv temporarily
                if [ -d "$server_dir/.venv" ]; then
                    mv "$server_dir/.venv" "/tmp/.venv_$name" 2>/dev/null || true
                fi
                rm -rf "$server_dir"
                git clone "$source_location" "$server_dir"
                # Restore .venv
                if [ -d "/tmp/.venv_$name" ]; then
                    mv "/tmp/.venv_$name" "$server_dir/.venv"
                fi
                UPDATED+=("$name")
            elif [ -d "$server_dir/.git" ]; then
                log_info "$name: pulling latest"
                cd "$server_dir"
                git pull --ff-only 2>/dev/null || git pull --rebase || {
                    log_warn "$name: git pull failed, skipping update"
                }
                cd "$PROJECT_DIR"
                UPDATED+=("$name")
            else
                log_warn "$name: exists but not a git repo, skipping"
                SKIPPED+=("$name")
                return 0
            fi
        else
            log_info "$name: cloning from $source_location"
            git clone "$source_location" "$server_dir"
            INSTALLED+=("$name")
        fi

    elif [ "$source_type" = "local" ]; then
        # Expand ~ in path
        local local_path="${source_location/#\~/$HOME}"

        if [ ! -d "$local_path" ]; then
            log_error "$name: local source not found: $local_path"
            FAILED+=("$name")
            return 1
        fi

        # Clean replace (preserve .venv)
        if [ -d "$server_dir/.venv" ]; then
            mv "$server_dir/.venv" "/tmp/.venv_$name"
        fi

        rm -rf "$server_dir"
        cp -r "$local_path" "$server_dir"

        if [ -d "/tmp/.venv_$name" ]; then
            mv "/tmp/.venv_$name" "$server_dir/.venv"
        fi

        if [ -d "$server_dir" ]; then
            [ ${#INSTALLED[@]} -eq 0 ] && UPDATED+=("$name") || INSTALLED+=("$name")
        fi
    fi

    # Install venv
    install_venv "$server_dir" "$name"
}

# Parse config and install all MCP servers with source definitions
install_mcp_servers() {
    log_section "Step 3/4: MCP servers"

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Config file not found: $CONFIG_FILE"
        return 1
    fi

    # Extract server names that have source definitions
    local servers=$(jq -r '.mcpServers | to_entries[] | select(.value.source != null) | .key' "$CONFIG_FILE")

    if [ -z "$servers" ]; then
        log_warn "No servers with source definitions found in config"
        return 0
    fi

    for name in $servers; do
        local source_type=$(jq -r ".mcpServers[\"$name\"].source.type" "$CONFIG_FILE")
        local source_location=""

        if [ "$source_type" = "git" ]; then
            source_location=$(jq -r ".mcpServers[\"$name\"].source.url" "$CONFIG_FILE")
        elif [ "$source_type" = "local" ]; then
            source_location=$(jq -r ".mcpServers[\"$name\"].source.path" "$CONFIG_FILE")
        else
            log_warn "$name: unknown source type '$source_type', skipping"
            SKIPPED+=("$name")
            continue
        fi

        install_mcp_server "$name" "$source_type" "$source_location" || true
    done
}

# Step 1: bitwarden-guard
install_bitwarden_guard() {
    log_section "Step 1/4: bitwarden-guard"

    if command -v bitwarden-guard &>/dev/null; then
        log_info "bitwarden-guard already installed"
        SKIPPED+=("bitwarden-guard")
        return 0
    fi

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

# Step 4: mcp-proxy
install_mcp_proxy() {
    log_section "Step 4/4: mcp-proxy"

    cd "$PROJECT_DIR"

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "config/config.local.json not found!"
        log_error "Copy from config/config.template.json and configure"
        FAILED+=("mcp-proxy")
        return 1
    fi

    if ! command -v go &>/dev/null; then
        log_warn "Go not installed. Run: ./scripts/install-go.sh"
        FAILED+=("mcp-proxy")
        return 1
    fi
    log_info "Go $(go version | awk '{print $3}')"

    log_info "Building mcp-proxy..."
    make build

    log_info "Deploying binaries..."
    mkdir -p "$MCP_PROXY_DIR"
    # Atomic replacement to avoid "Text file busy" when binary is running
    cp build/mcp-proxy "$MCP_PROXY_DIR/mcp-proxy.new"
    cp build/structure_generator "$MCP_PROXY_DIR/structure_generator.new"
    chmod +x "$MCP_PROXY_DIR/mcp-proxy.new" "$MCP_PROXY_DIR/structure_generator.new"
    mv -f "$MCP_PROXY_DIR/mcp-proxy.new" "$MCP_PROXY_DIR/mcp-proxy"
    mv -f "$MCP_PROXY_DIR/structure_generator.new" "$MCP_PROXY_DIR/structure_generator"

    log_info "Expanding and copying configuration..."
    export MCP_SERVERS_DIR MCP_PROXY_DIR HOME
    envsubst '${MCP_SERVERS_DIR} ${MCP_PROXY_DIR} ${HOME}' < "$CONFIG_FILE" > "$MCP_PROXY_DIR/config.json"

    log_info "Generating tool hierarchy..."
    "$MCP_PROXY_DIR/structure_generator" \
        --config "$MCP_PROXY_DIR/config.json" \
        --output "$MCP_PROXY_DIR/hierarchy"

    log_info "mcp-proxy installed"
    INSTALLED+=("mcp-proxy")
}

# Refresh only: config + hierarchy
refresh_only() {
    log_section "Refreshing mcp-proxy (config + hierarchy)"

    cd "$PROJECT_DIR"

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "config/config.local.json not found!"
        exit 1
    fi

    if [ ! -f "$MCP_PROXY_DIR/structure_generator" ]; then
        log_error "structure_generator not found. Run full bootstrap first."
        exit 1
    fi

    log_info "Expanding and copying configuration..."
    export MCP_SERVERS_DIR MCP_PROXY_DIR HOME
    envsubst '${MCP_SERVERS_DIR} ${MCP_PROXY_DIR} ${HOME}' < "$CONFIG_FILE" > "$MCP_PROXY_DIR/config.json"

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
    log_section "Summary"

    if [ ${#INSTALLED[@]} -gt 0 ]; then
        echo -e "${GREEN}Installed:${NC}"
        for item in "${INSTALLED[@]}"; do
            echo "  ✓ $item"
        done
    fi

    if [ ${#UPDATED[@]} -gt 0 ]; then
        echo -e "${BLUE}Updated:${NC}"
        for item in "${UPDATED[@]}"; do
            echo "  ↑ $item"
        done
    fi

    if [ ${#SKIPPED[@]} -gt 0 ]; then
        echo -e "${YELLOW}Skipped (already installed):${NC}"
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
        return 1
    fi

    echo ""
    log_info "Bootstrap complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Restart Claude Code"
    echo "  2. Test: claude mcp list"
}

# Main
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}       MCP Proxy Infrastructure Bootstrap              ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_dependencies

    install_bitwarden_guard || true
    install_openbao_agents || true
    install_mcp_servers || true
    install_mcp_proxy || true

    print_summary
}

# Help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Bootstrap full MCP proxy infrastructure."
    echo ""
    echo "Options:"
    echo "  (none)       Full bootstrap - install/update all components"
    echo "  --refresh    Config + hierarchy only (skip source updates)"
    echo "  --force      Force clean reinstall of all MCP servers"
    echo "  -h, --help   Show this help"
    echo ""
    echo "MCP servers are installed from source definitions in config.local.json."
    echo "Each server can specify a 'source' with type 'git' or 'local'."
    echo ""
    echo "Examples:"
    echo "  $0               # Full bootstrap"
    echo "  $0 --refresh     # Just update config and hierarchy"
    echo "  $0 --force       # Reinstall everything fresh"
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    --refresh)
        refresh_only
        ;;
    --force)
        FORCE_REINSTALL=true
        main
        ;;
    *)
        main
        ;;
esac
