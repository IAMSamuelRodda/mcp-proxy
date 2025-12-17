# ISSUES.md

> **Purpose:** Track bugs, improvements, and technical debt for lazy-mcp-preload
> **Lifecycle:** Living document, updated when issues change

**Last Updated:** 2025-12-18

---

## Status/Priority Guides

**Status Indicators:**
- 🔴 **Open** - Issue identified, needs attention
- 🟡 **In Progress** - Actively being worked on
- 🟢 **Resolved** - Fixed and verified
- 🔵 **Blocked** - Cannot proceed due to dependencies

**Priority Levels:**
- **P0** - Critical, blocks core functionality
- **P1** - High, affects user experience significantly
- **P2** - Medium, should fix but not urgent
- **P3** - Low, nice to have

---

## Active Issues

### Bugs

---

## Resolved Issues (Last 2 Weeks)

#### issue_002: structure_generator panics on MCP server connection
- **Status**: 🟢 Resolved
- **Priority**: P0 (blocks hierarchy regeneration)
- **Component**: structure_generator
- **Discovered**: 2025-12-17
- **Resolved**: 2025-12-18

**Root Cause:**
The `context7` server was configured with `transportType: "sse"` but had no `command` field. The `ServerConfig` struct only read `command/args/env` and ignored `transportType`. When `client.NewStdioMCPClient()` was called with an empty command, `mcp-go`'s `spawnCommand()` returned nil without error but didn't initialize `stdout`, causing a nil pointer panic in `readResponses()`.

**Fix Applied:**
1. Added `TransportType` and `URL` fields to `ServerConfig` struct
2. Added validation to reject empty commands for stdio transport
3. Added support for SSE transport (`client.NewSSEMCPClient`)
4. Added support for HTTP Streamable transport (`client.NewStreamableHttpClient`)
5. Updated context7 URL from deprecated `/sse` to `/mcp`
6. Added missing `stripe` and `vikunja` servers to config

**Result:**
- 12 servers, 109 tools generated successfully
- context7 works via HTTP Streamable transport
- stripe included in hierarchy (7 tools)
- vikunja times out (separate issue - needs Vikunja API running)

---

#### issue_001: Vikunja Tool Count Discrepancy (MOVED to vikunja-mcp)
- **Status**: 🔵 Moved to vikunja-mcp repository
- **Priority**: P2
- **Component**: Vikunja MCP server (not lazy-mcp-preload)
- **Discovered**: 2025-12-17
- **Tracking**: `/home/x-forge/repos/3-resources/MCP/vikunja-mcp/ISSUES.md#BUG-001`

**Description:**
Vikunja MCP server shows tool count discrepancy when accessed via lazy-mcp (27 actual vs 23 reported). Systematic review of 10 other MCP servers found NO similar discrepancy, indicating this is specific to vikunja-mcp implementation, not a lazy-mcp-preload bug.

**Resolution:**
Systematic review of 10 other MCP servers (cloudflare, joplin, mailjet, nextcloud-calendar, stalwart, stripe, todoist, tplink-router, youtube-transcript) found all report accurate tool counts. Issue is specific to vikunja-mcp server, not lazy-mcp-preload.

**See:** `/home/x-forge/repos/3-resources/MCP/vikunja-mcp/ISSUES.md#BUG-001` for full investigation and tracking.

---

### Improvements

*None currently*

---

### Technical Debt

*None currently*

---

## Resolved Issues (Last 2 Weeks)

*None yet*

---

## Archived Issues (Older than 2 Weeks)

*Items will be moved here from Resolved Issues after 2 weeks*

---

## Issue Patterns

*Track recurring issues here as patterns emerge*
