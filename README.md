# mcp-proxy

[![GitHub release](https://img.shields.io/github/v/release/IAMSamuelRodda/mcp-proxy)](https://github.com/IAMSamuelRodda/mcp-proxy/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

An aggregating MCP proxy that reduces context window usage by ~95% while providing zero-latency tool execution.

## How It Works

Instead of exposing all tools directly to Claude (consuming ~15,000+ tokens), mcp-proxy exposes just 2 meta-tools:

1. **`get_tools_in_category`** - Navigate a hierarchical tree of available tools
2. **`execute_tool`** - Execute any tool by its path

This progressive disclosure pattern reduces context to ~800 tokens while maintaining full access to all tools.

## Features

| Feature | Benefit |
|---------|---------|
| **95% context reduction** | ~800 tokens instead of ~15,000 |
| **Background preloading** | Zero cold-start latency |
| **Multi-transport** | stdio, SSE, HTTP Streamable |
| **Graceful degradation** | Failed servers disabled, don't block |
| **Secrets integration** | Optional OpenBao/Vault support |
| **Source-based installation** | MCP servers installed from git/local sources |
| **Portable config** | Variable expansion for machine-independent configs |

## Prerequisites

| Dependency | Purpose | Install |
|-----------|---------|---------|
| **Go 1.21+** | Build mcp-proxy binary | [go.dev/dl](https://go.dev/dl/) or `./scripts/install-go.sh` |
| **Python 3.10+** | MCP server runtimes | Usually pre-installed |
| **jq** | JSON config parsing | `sudo apt install jq` / `brew install jq` |
| **envsubst** | Variable expansion in configs | `sudo apt install gettext-base` / `brew install gettext` |
| **uv** *(optional)* | Faster Python package installs | [docs.astral.sh/uv](https://docs.astral.sh/uv/) |

## Quick Start

```bash
# 1. Clone
git clone https://github.com/IAMSamuelRodda/mcp-proxy.git
cd mcp-proxy

# 2. Create your config
cp config/config.template.json config/config.local.json

# 3. Edit config.local.json:
#    - Remove example-* entries
#    - Add your MCP servers with source URLs
#    - Keep ${VARIABLES} as-is (expanded automatically)

# 4. Bootstrap (validates config, installs servers, updates ~/.claude.json)
./scripts/bootstrap.sh

# 5. Restart Claude Code
```

### Minimal Config Example

```json
{
  "mcpProxy": {
    "hierarchyPath": "${MCP_PROXY_DIR}/hierarchy",
    "options": { "lazyLoad": true, "preloadAll": true }
  },
  "mcpServers": {
    "my-server": {
      "source": { "type": "git", "url": "https://github.com/you/my-mcp.git" },
      "transportType": "stdio",
      "command": "${MCP_SERVERS_DIR}/my-server/.venv/bin/python",
      "args": ["${MCP_SERVERS_DIR}/my-server/server.py"],
      "envFile": "${MCP_SERVERS_DIR}/my-server/.env",
      "env": {},
      "options": { "lazyLoad": true }
    }
  }
}
```

**Key points:**
- Use `${MCP_SERVERS_DIR}` for server paths (expands to `~/.claude/mcp-servers`)
- Use `${MCP_PROXY_DIR}` for proxy paths (expands to `~/.claude/mcp-proxy`)
- Add `envFile` for `.env` secrets OR use `env: {}` for inline variables
- Every server needs a `source` for bootstrap to install it

## Bootstrap Workflow

The bootstrap script orchestrates full workstation setup:

```
./scripts/bootstrap.sh [FLAGS]
```

| Flag | Behavior |
|------|----------|
| (none) | Default: MCP servers → mcp-proxy |
| `--secure` | Include secrets infrastructure (bitwarden-guard, obao) |
| `--refresh` | Config + hierarchy only (fast, skips source updates) |
| `--force` | Clean reinstall all MCP servers from source |

**What it does:**
1. **Validates config** - Checks for missing/placeholder values
2. **Installs MCP servers** - Clones from git, creates venvs
3. **Builds mcp-proxy** - Compiles Go binary + structure generator
4. **Deploys** - Copies to `~/.claude/mcp-proxy/`, expands variables
5. **Updates ~/.claude.json** - Adds mcp-proxy entry automatically
6. *(--secure only)* Installs bitwarden-guard + obao

## Configuration

### Portable Config with Variables

Config files use variables that are expanded at deploy time:

```json
{
  "mcpProxy": {
    "hierarchyPath": "${MCP_PROXY_DIR}/hierarchy"
  },
  "mcpServers": {
    "my-server": {
      "source": {
        "type": "git",
        "url": "https://github.com/user/mcp-server.git"
      },
      "command": "${MCP_SERVERS_DIR}/my-server/.venv/bin/python",
      "args": ["${MCP_SERVERS_DIR}/my-server/server.py"]
    }
  }
}
```

**Available variables:**
| Variable | Default |
|----------|---------|
| `${MCP_SERVERS_DIR}` | `~/.claude/mcp-servers` |
| `${MCP_PROXY_DIR}` | `~/.claude/mcp-proxy` |
| `${HOME}` | User home directory |

### Source Types

Each MCP server can specify a source for installation:

**Git source** (recommended):
```json
"source": {
  "type": "git",
  "url": "https://github.com/user/mcp-server.git"
}
```

**Local source** (for development):
```json
"source": {
  "type": "local",
  "path": "~/repos/my-mcp-server"
}
```

**Remote HTTP** (no installation needed):
```json
"transportType": "streamable-http",
"url": "https://example.com/mcp"
```

### Update Behavior

| Source Type | Update Mechanism |
|-------------|------------------|
| Git | `git pull` on each bootstrap run |
| Local | Clean replace (rm + cp) preserving .venv |
| Remote | No installation, connects directly |

**Venv rebuilds** only occur when `pyproject.toml` or `requirements.txt` changes (hash-based detection).

## Setup Options

| Mode | Secrets Storage | Best For |
|------|-----------------|----------|
| **Simple** | `.env` files per server | Local dev, single machine |
| **Secure** | OpenBao + Bitwarden | Production, multi-machine, audit trails |

**Simple mode:** Configure MCP servers with environment variables. See [config.template.json](config/config.template.json).

**Secure mode:** Full secrets management with OpenBao, Bitwarden integration. See [docs/SECURE_SETUP.md](docs/SECURE_SETUP.md).

## Claude Code Integration

Add to `~/.claude.json`:

```json
{
  "mcpServers": {
    "mcp-proxy": {
      "type": "stdio",
      "command": "~/.claude/mcp-proxy/mcp-proxy",
      "args": ["--config", "~/.claude/mcp-proxy/config.json"]
    }
  }
}
```

> **⚠️ CRITICAL:** Your `~/.claude.json` should contain **ONLY** the `mcp-proxy` entry above.
>
> Remove all other MCP server entries (cloudflare, joplin, etc.) - the proxy handles them.
>
> Having both direct servers AND mcp-proxy causes duplicate connections and wasted context.
>
> The install script will detect this and prompt you to clean up automatically.

## Finding MCP Servers

mcp-proxy aggregates any MCP server that uses stdio, SSE, or Streamable HTTP transport. To find servers to add:

- **[mcp.so](https://mcp.so)** — Community registry of MCP servers
- **[modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers)** — Official reference implementations
- **[awesome-mcp-servers](https://github.com/punkpeye/awesome-mcp-servers)** — Curated list

Add any server to your config with a `source` field and bootstrap will install it automatically.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Claude Code                        │
│                        │                             │
│                        ▼                             │
│         ┌──────────────────────────────┐            │
│         │         mcp-proxy            │            │
│         │                              │            │
│         │  2 meta-tools (~800 tokens)  │            │
│         │  • get_tools_in_category()   │            │
│         │  • execute_tool()            │            │
│         │                              │            │
│         │  Background: preload all     │            │
│         └──────────────────────────────┘            │
│                        │                             │
│     ┌──────────────────┼──────────────────┐         │
│     ▼                  ▼                  ▼         │
│ [Server 1]        [Server 2]        [Server 3]      │
│   warm              warm              warm          │
└─────────────────────────────────────────────────────┘
```

## Project Structure

```
mcp-proxy/
├── cmd/mcp-proxy/         # Main entry point
├── internal/
│   ├── client/            # MCP client connections
│   ├── config/            # Configuration parsing
│   ├── hierarchy/         # Tool schema management
│   ├── secrets/           # Secrets provider interface
│   └── server/            # Proxy server logic
├── structure_generator/   # Hierarchy generation tool
├── config/                # Configuration templates
│   ├── config.template.json   # Portable template with variables
│   └── config.local.json      # Your local config (gitignored)
├── scripts/
│   ├── bootstrap.sh       # Full setup: install MCP servers + build proxy (start here)
│   ├── install.sh         # Binary-only: rebuild proxy without touching servers
│   └── install-go.sh      # Install Go if missing
└── docs/
    └── SECURE_SETUP.md    # OpenBao + Bitwarden guide
```

## Development

```bash
# Build
make build

# Test
go test ./...

# Deploy binary only (keeps existing config)
make deploy

# Full install (binary + config from config.local.json)
make install

# Regenerate hierarchy only
make generate-hierarchy
```

## Acknowledgments

This project was inspired by [voicetreelab/lazy-mcp](https://github.com/voicetreelab/lazy-mcp), which introduced the elegant 2-meta-tool pattern for progressive tool disclosure. mcp-proxy extends this foundation with background preloading, multi-transport support, secrets integration, and production resilience features.

## License

MIT License
