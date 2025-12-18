# mcp-proxy

Aggregating MCP proxy with ~95% context reduction through progressive tool disclosure.

## Build & Deploy

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

## Issue Tracking

Use GitHub Issues: https://github.com/IAMSamuelRodda/mcp-proxy/issues
