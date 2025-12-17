# STATUS.md

> **Purpose:** Current project state and active work (2-week rolling window)
> **Lifecycle:** Living document, updated daily/weekly

**Last Updated:** 2025-12-18

## Quick Overview

| Aspect | Status |
|--------|--------|
| Build | Working |
| Deployment | Deployed to ~/.claude/lazy-mcp/ |
| Testing | Passed (13 servers, 136 tools) |
| GitHub | Published |

## Current Focus

### This Week: Structure Generator Fixes

- [x] Fix nil pointer panic in structure_generator (context7 SSE transport)
- [x] Add HTTP Streamable transport support (context7 now works)
- [x] Add environment variable passthrough for stdio servers
- [x] Fix vikunja timeout (PYTHONPATH not being passed)
- [x] Update Makefile for direct hierarchy generation (no intermediate deploy/)
- [x] Update context7 URL from deprecated /sse to /mcp

## Deployment Status

| Environment | Status | Notes |
|-------------|--------|-------|
| Local (~/.claude/lazy-mcp/) | Deployed | Config updated in ~/.claude.json |
| GitHub | Published | https://github.com/iamsamuelrodda/lazy-mcp-preload |

## Configuration

```
~/.claude/lazy-mcp/
├── mcp-proxy          # Go binary
├── config.json        # preloadAll: true enabled (gitignored - personal)
└── hierarchy/         # Tool schemas (136 tools across 13 servers)
    ├── cloudflare/ (6)
    ├── cloudflare-full/ (23)
    ├── context7/ (2)
    ├── joplin/ (11)
    ├── mailjet_mcp/ (8)
    ├── nextcloud-calendar/ (7)
    ├── stalwart/ (24)
    ├── stripe/ (7)
    ├── todoist/ (12)
    ├── tplink-router/ (3)
    ├── vikunja/ (27)
    ├── visual-to-code/ (3)
    └── youtube-transcript/ (3)
```

## Known Issues

*None currently*

### Recently Fixed

**Pydantic params wrapper issue (2025-11-27)**
- **Symptom:** First MCP tool call fails with `params Field required` validation error, retry succeeds
- **Root cause:** Python MCP servers using Pydantic expect args wrapped in `params`, Claude passes flat args
- **Fix:** Auto-wrap detection in `maybeWrapInParams()` - transparent to Claude, zero context bloat
- **Commit:** `78d95da`

## Recent Achievements (Last 2 Weeks)

### 2025-12-18
- **Fixed structure_generator panic** - context7 SSE transport caused nil pointer
- **Added multi-transport support** - stdio, SSE, and HTTP Streamable
- **Fixed env var passthrough** - vikunja now works (PYTHONPATH)
- **Direct hierarchy generation** - No intermediate deploy/ folder
- **Full hierarchy** - 13 servers, 136 tools generated successfully

### 2025-12-16
- **Security hardening** - STRIDE threat model audit, input validation
- **Auth token validation** - 24+ character minimum with helpful error messages
- **Command injection protection** - Block shell metacharacters in stdio configs

### 2025-11-27
- Forked voicetreelab/lazy-mcp
- Added `preloadAll` config option
- Implemented `PreloadServers()` with parallel goroutines
- **Testing passed** - ~95% context reduction, zero cold-start latency
- **Fixed Pydantic params issue** - auto-wrap args when schema requires `params` wrapper

## Next Steps (Prioritized)

1. **Merge security branch** - Review and merge dev/security-hardening to main
2. **Monitor feedback** - Watch for issues/improvements on GitHub
3. **Consider upstream PR** - If voicetreelab/lazy-mcp is active, propose preloadAll feature

## Related Resources

- **Issue:** [anthropics/claude-code#3036](https://github.com/anthropics/claude-code/issues/3036)
- **Upstream:** [voicetreelab/lazy-mcp](https://github.com/voicetreelab/lazy-mcp)
- **Draft comment:** `GITHUB_COMMENT_DRAFT.md`
