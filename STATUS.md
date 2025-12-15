# STATUS.md

> **Purpose:** Current project state and active work (2-week rolling window)
> **Lifecycle:** Living document, updated daily/weekly

**Last Updated:** 2025-12-16

## Quick Overview

| Aspect | Status |
|--------|--------|
| Build | Working |
| Deployment | Deployed to ~/.claude/lazy-mcp/ |
| Testing | Passed |
| GitHub | Published |

## Current Focus

### This Week: Security Hardening & Repo Cleanup

- [x] STRIDE threat model security audit
- [x] Add auth token validation (24+ char minimum)
- [x] Add command injection protection for stdio configs
- [x] Remove --insecure flag (unused)
- [x] Audit full MCP server setup (11 servers, 102 tools)
- [x] Separate personal configs from public repo
- [x] Create SETUP.md guide for installation
- [ ] Merge dev/security-hardening to main

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
└── hierarchy/         # Tool schemas (102 tools across 11 servers)
    ├── joplin/
    ├── todoist/
    ├── nextcloud-calendar/
    ├── cloudflare/
    ├── cloudflare-full/
    ├── mailjet_mcp/
    ├── stalwart/
    ├── tplink-router/
    ├── visual-to-code/
    ├── youtube-transcript/
    └── context7/
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

### 2025-12-16
- **Security hardening** - STRIDE threat model audit, input validation
- **Auth token validation** - 24+ character minimum with helpful error messages
- **Command injection protection** - Block shell metacharacters in stdio configs
- **Removed --insecure flag** - Unused, removed entirely
- **Full MCP audit** - Discovered 102 tools across 11 servers
- **Repo cleanup** - Personal configs gitignored, examples/ for public
- **SETUP.md** - Claude Code guide for investigating and installing lazy-mcp

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
