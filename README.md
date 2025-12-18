# mcp-proxy

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
| **Fast-fail detection** | 5s timeout for quick error feedback |

## Quick Start

```bash
# Clone and build
git clone https://github.com/IAMSamuelRodda/mcp-proxy.git
cd mcp-proxy
./scripts/install.sh

# Or manually:
go build -o build/mcp-proxy ./cmd/mcp-proxy
```

## Configuration

### 1. Create config.json

```json
{
  "mcpProxy": {
    "name": "MCP Proxy",
    "version": "1.0.0",
    "type": "stdio",
    "hierarchyPath": "~/.claude/mcp-proxy/hierarchy",
    "options": {
      "lazyLoad": true,
      "preloadAll": true
    }
  },
  "mcpServers": {
    "your-server": {
      "transportType": "stdio",
      "command": "/path/to/.venv/bin/python",
      "args": ["/path/to/mcp_server.py"],
      "options": { "lazyLoad": true }
    }
  }
}
```

**Key options:**
- `lazyLoad: true` - Progressive tool disclosure (reduces context)
- `preloadAll: true` - Pre-warm servers in background (eliminates cold start)

### 2. Generate Tool Hierarchy

```bash
./build/structure_generator --config config.json --output hierarchy/
```

### 3. Configure Claude Code

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

**Important:** Remove individual MCP server entries - the proxy handles them.

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

## Secrets Provider (Optional)

For integrating with secrets managers like OpenBao/HashiCorp Vault:

```json
{
  "mcpProxy": {
    "options": {
      "secretsProvider": "openbao",
      "secretsAutoStart": true,
      "secretsProviderAddr": "http://127.0.0.1:8200"
    }
  }
}
```

Supported providers: `none` (default), `openbao`, `env`

See [config.template.json](config/config.template.json) for all options.

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
├── config/                # Example configurations
└── scripts/               # Build & install scripts
```

## Development

```bash
# Build
go build ./...

# Test
go test ./...

# Run locally
./build/mcp-proxy --config config/config.json
```

## Acknowledgments

This project was inspired by [voicetreelab/lazy-mcp](https://github.com/voicetreelab/lazy-mcp), which introduced the elegant 2-meta-tool pattern for progressive tool disclosure. mcp-proxy extends this foundation with background preloading, multi-transport support, secrets integration, and production resilience features.

## License

MIT License
