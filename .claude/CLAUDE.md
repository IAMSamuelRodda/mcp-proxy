# mcp-proxy

Aggregating MCP proxy with ~95% context reduction through progressive tool disclosure.

## Prerequisites

**CRITICAL**: Before running `make install` or `./scripts/install.sh`:

1. **config/config.local.json MUST exist and be configured** with absolute paths for your machine
2. Copy from `config/config.json.example` or `config/config.template.json` and update paths
3. The install script uses this file to generate `~/.claude/mcp-proxy/config.json`

Without a valid `config.local.json`, the install will create an empty config with no MCP servers.

## Full Workstation Bootstrap

For a new machine, run the bootstrap script to install all dependencies:

```bash
./scripts/bootstrap.sh
```

This orchestrates installation of:
1. **bitwarden-guard** ([GitHub](https://github.com/IAMSamuelRodda/bitwarden-guard)) - Session management
2. **obao** ([GitHub](https://github.com/IAMSamuelRodda/obao)) - Secrets access
3. **MCP servers** (`~/.claude/mcp-servers/*/`) - Each needs `.venv` with deps
4. **mcp-proxy** (this repo) - Aggregates all MCP servers

## Build & Deploy

```bash
# Quick deploy (binary only, preserves config)
make deploy

# Full deploy (binary + regenerate hierarchy from existing config)
make deploy-full

# Full install (build + deploy + config from config.local.json)
make install

# Or use the script directly
./scripts/install.sh
```

## Manual Steps

```bash
# Build
go build -o build/mcp-proxy ./cmd/mcp-proxy
go build -o build/structure_generator ./structure_generator/cmd

# Deploy locally
cp build/mcp-proxy ~/.claude/mcp-proxy/
cp build/structure_generator ~/.claude/mcp-proxy/

# Regenerate hierarchy
~/.claude/mcp-proxy/structure_generator \
  --config ~/.claude/mcp-proxy/config.json \
  --output ~/.claude/mcp-proxy/hierarchy
```

## Adding New MCP Servers

1. Add entry to `config/config.local.json`
2. Copy updated config: `cp config/config.local.json ~/.claude/mcp-proxy/config.json`
3. Regenerate hierarchy: `make generate-hierarchy`
4. Restart Claude Code

## Issue Tracking

Use GitHub Issues: https://github.com/IAMSamuelRodda/mcp-proxy/issues
