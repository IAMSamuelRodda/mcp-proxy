# mcp-proxy Setup Guide

This guide is designed for Claude Code to follow when helping users set up mcp-proxy with their existing MCP servers.

## Investigation Phase

### Step 1: Discover Existing MCP Configuration

Check for existing MCP servers in the user's setup:

```bash
# Check Claude Code's MCP config
cat ~/.claude.json 2>/dev/null | grep -A 50 '"mcpServers"'

# Check for project-level MCP config
cat .mcp.json 2>/dev/null

# Look for MCP server implementations
ls -la ~/.claude/mcp-servers/ 2>/dev/null
```

### Step 2: Analyze Each Server

For each discovered MCP server, determine:

1. **Transport type**: stdio, SSE, or streamable-http
2. **Command/URL**: How to start or connect to it
3. **Dependencies**: Python venv, Node modules, etc.
4. **Environment variables**: Required API keys or tokens

```bash
# For Python servers, check for venv and main script
ls ~/.claude/mcp-servers/*/
ls ~/.claude/mcp-servers/*/*.py
ls ~/.claude/mcp-servers/*/.venv/bin/python

# For Node servers
ls ~/.claude/mcp-servers/*/package.json
```

### Step 3: Check for npx-based Servers

Some MCP servers are installed via npx:

```bash
# Common patterns in ~/.claude.json
grep -E "npx|@modelcontextprotocol|@anthropic" ~/.claude.json
```

## Configuration Phase

### Step 4: Generate Config

Create `config/config.json` based on discovered servers:

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
    "<server-name>": {
      "transportType": "stdio|sse|streamable",
      "command": "/path/to/python/or/node",
      "args": ["/path/to/mcp_server.py"],
      "env": {},
      "options": { "lazyLoad": true }
    }
  }
}
```

**Transport type patterns:**

| Type | Config |
|------|--------|
| Python stdio | `"command": "/path/.venv/bin/python", "args": ["/path/server.py"]` |
| Node stdio | `"command": "node", "args": ["/path/server.js"]` |
| npx stdio | `"command": "npx", "args": ["@package/mcp-server"]` |
| SSE remote | `"transportType": "sse", "url": "https://example.com/sse"` |

### Step 5: Generate Hierarchy

```bash
# Build the structure generator
make build

# Generate hierarchy from your config
./build/structure_generator --config config/config.json --output deploy/hierarchy
```

**Note**: SSE/remote servers can't be auto-generated. Create their hierarchy manually:

```json
// deploy/hierarchy/<server>/<server>.json
{
  "overview": "<server>: N tools; tool1 -> description, tool2 -> description"
}
```

## Installation Phase

### Step 6: Deploy

```bash
# Deploy binary only (safe, preserves existing config/hierarchy)
make deploy

# Or full deploy (overwrites everything)
make deploy-full
```

### Step 7: Update Claude Config

Replace individual MCP servers in `~/.claude.json` with single lazy-mcp entry:

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

### Step 8: Verify

```bash
# Test proxy starts and loads hierarchy
timeout 5 ~/.claude/lazy-mcp/mcp-proxy --config ~/.claude/lazy-mcp/config.json
```

Expected output:
- "Loaded X hierarchy nodes"
- "Background preloading N MCP servers..."
- "Preloaded server X in Yms"

## Troubleshooting

### Server fails to connect

```bash
# Test server directly
/path/to/.venv/bin/python /path/to/mcp_server.py
```

### Missing environment variables

Check if server needs API keys:
```bash
cat ~/.claude/mcp-servers/<server>/.env.example
```

### Hierarchy not generating

The structure generator only supports stdio transport. For SSE/remote servers:
1. Create hierarchy JSON manually
2. Or skip and let lazy-mcp handle it without hierarchy metadata

## Migration Checklist

- [ ] Discovered all existing MCP servers
- [ ] Created config/config.json with all servers
- [ ] Generated hierarchy for stdio servers
- [ ] Added manual hierarchy for SSE/remote servers
- [ ] Deployed binary and hierarchy
- [ ] Updated ~/.claude.json to use lazy-mcp
- [ ] Verified proxy starts correctly
- [ ] Tested tool execution through proxy
