# lazy-mcp-preload

A fork of [voicetreelab/lazy-mcp](https://github.com/voicetreelab/lazy-mcp) with background server preloading for zero-latency MCP tool execution.

## Problem

lazy-mcp reduces context window usage by ~95% (from ~15,000 tokens to ~800 tokens for 30 tools). However, servers are started on-demand, causing ~500ms latency on first tool call to each server.

## Solution

This fork adds a `preloadAll` option that starts all configured MCP servers in the background immediately at proxy startup. By the time Claude needs them, they're already warm.

## Token Savings

| Metric | Direct MCP | lazy-mcp | lazy-mcp-preload |
|--------|------------|----------|------------------|
| Startup tokens | ~15,000 | ~800 | ~800 |
| First-call latency | 0ms | ~500ms | ~0ms |
| Tools visible | 30 | 2 | 2 |

## Installation

### Prerequisites

- Go 1.21+ (`sudo apt install golang-go` or use `./scripts/install-go.sh`)
- Your existing MCP servers configured and working

### Quick Start

```bash
# Clone the repository
git clone https://github.com/iamsamuelrodda/lazy-mcp-preload.git
cd lazy-mcp-preload

# Build the proxy
make build

# Generate tool hierarchy from your existing MCP servers
make generate-hierarchy

# Deploy to ~/.claude/lazy-mcp/
make deploy
```

## Configuration

### 1. Create config.json

Copy the example and customize for your MCP servers:

```bash
cp config/config.json.example config/config.json
```

Edit `config/config.json`:

```json
{
  "mcpProxy": {
    "name": "MCP Proxy",
    "version": "1.0.0",
    "type": "stdio",
    "hierarchyPath": "~/.claude/lazy-mcp/hierarchy",
    "options": {
      "lazyLoad": true,
      "preloadAll": true
    }
  },
  "mcpServers": {
    "your-server-name": {
      "transportType": "stdio",
      "command": "python",
      "args": ["/path/to/your/mcp_server.py"],
      "env": {},
      "options": { "lazyLoad": true }
    }
  }
}
```

**Key options:**
- `lazyLoad: true` - Only load tool schemas on-demand (reduces context)
- `preloadAll: true` - Pre-warm all servers in background (eliminates cold start)

### 2. Update Claude Code Configuration

Add to your `~/.claude.json`:

```json
{
  "mcpServers": {
    "lazy-mcp": {
      "type": "stdio",
      "command": "~/.claude/lazy-mcp/mcp-proxy",
      "args": ["--config", "~/.claude/lazy-mcp/config.json"]
    }
  }
}
```

**Important:** Remove your original MCP server entries from `~/.claude.json` - the proxy handles them now.

## How Preloading Works

```
0ms      50ms     200ms    500ms    1000ms+
│        │        │        │        │
▼        ▼        ▼        ▼        ▼
[proxy starts]
         [2 meta-tools ready ─ Claude can start]
         [───── background preload (parallel) ─────]
                  [user typing...]
                           [all servers warm]
                                    [tool call = instant]
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Claude Code                        │
│                        │                             │
│                        ▼                             │
│         ┌──────────────────────────────┐            │
│         │     lazy-mcp-preload         │            │
│         │                              │            │
│         │  Main thread:                │            │
│         │  • get_tools_in_category()   │ ~800 tokens│
│         │  • execute_tool()            │            │
│         │                              │            │
│         │  Background goroutine:       │            │
│         │  • Pre-starts all servers    │            │
│         └──────────────────────────────┘            │
│                        │                             │
│     ┌──────────────────┼──────────────────┐         │
│     ▼                  ▼                  ▼         │
│ [Joplin]          [Todoist]        [Nextcloud]      │
│  warm              warm             warm            │
└─────────────────────────────────────────────────────┘
```

## Development

### Project Structure

```
lazy-mcp-preload/
├── README.md
├── Makefile
├── go.mod / go.sum
├── cmd/mcp-proxy/         # Main entry point
├── internal/              # Core implementation
│   ├── client/            # MCP client connections
│   ├── config/            # Configuration parsing
│   ├── hierarchy/         # Tool schema management
│   └── server/            # Proxy server logic
├── config/                # Example configurations
├── scripts/               # Build & deploy scripts
├── structure_generator/   # Python tool for generating hierarchy
└── deploy/hierarchy/      # Generated tool schemas
```

### Making Changes

```bash
# Edit source in internal/ or cmd/
make build                                    # Rebuild
./build/mcp-proxy --config config/config.json # Test locally
make deploy                                   # Deploy to ~/.claude/lazy-mcp/
```

### Generating Tool Hierarchy

The hierarchy generator introspects your MCP servers and creates JSON schemas:

```bash
cd structure_generator
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python generate_hierarchy.py --config ../config/config.json --output ../deploy/hierarchy
```

## Upstream

Fork of [voicetreelab/lazy-mcp](https://github.com/voicetreelab/lazy-mcp).

**Changes from upstream:**
- Added `preloadAll` config option for background server initialization
- Servers start in parallel goroutines immediately at proxy startup
- Added deployment scripts and hierarchy generator for Claude Code

## Contributing

Contributions welcome! This project addresses [anthropics/claude-code#3036](https://github.com/anthropics/claude-code/issues/3036).

## Security Notes

### Remote Config

If using `--config https://...` to load config from a URL:
- Ensure the config server uses valid HTTPS certificates
- Config files fetched remotely contain the same sensitive data as local configs

### Auth Tokens

When using HTTP server mode with `authTokens`:
- Generate cryptographically strong tokens: `openssl rand -base64 32`
- Rotate tokens periodically

## License

MIT License (same as upstream)
