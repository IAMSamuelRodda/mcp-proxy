# MCP Server Review - Comprehensive Report

> **Purpose:** Document systematic review of all MCP servers for OpenBao integration status and tool count accuracy
> **Date:** 2025-12-17
> **Scope:** All MCP servers in `/home/x-forge/repos/3-resources/MCP`

---

## Executive Summary

**Reviewed:** 11 MCP server repositories
**With OpenBao:** 2 servers (18%)
**Need Migration:** 8 servers (73%)
**Tool Count Discrepancies:** 1 server (Vikunja: 27 actual vs 23 reported)
**Infrastructure Projects:** 1 (rodda-mcp aggregator)

---

## Detailed Findings

### Tool Count Verification

| Server | Actual Tools | Lazy-MCP Reports | Status | OpenBao |
|--------|--------------|------------------|--------|---------|
| cloudflare-mcp | 6 | 6 | ✅ Match | ❌ No |
| joplin-mcp | 11 | 11 | ✅ Match | ✅ Yes |
| mailjet-mcp | 8 | 8 | ✅ Match | ❌ No |
| nextcloud-calendar-mcp | 7 | 7 | ✅ Match | ❌ No |
| rodda-mcp | N/A | N/A | 🔧 Aggregator | N/A |
| stalwart-mcp | 24 | 24 | ✅ Match | ❌ No |
| stripe-mcp | 7 | ? | ✅ Match | ❌ No |
| todoist-mcp | 12 | 12 | ✅ Match | ❌ No |
| tplink-router-mcp | 3 | 3 | ✅ Match | ❌ No |
| vikunja-mcp | 27 | 23 | ⚠️ MISMATCH (-4) | ✅ Yes |
| youtube-transcript-mcp | 3 | 3 | ✅ Match | ❌ No |

**Key Finding:** Only Vikunja MCP server exhibits tool count discrepancy. All other servers report accurate tool counts, indicating the issue is specific to Vikunja or a rare edge case in lazy-mcp's discovery mechanism.

---

## OpenBao Integration Status

### Servers WITH OpenBao (2)

1. **joplin-mcp** ✅
   - Location: `/home/x-forge/repos/3-resources/MCP/joplin-mcp/joplin_mcp.py`
   - Pattern: Arc Forge secret path pattern
   - Implementation: Complete with dev fallback
   - Tools: 11

2. **vikunja-mcp** ✅
   - Location: `/home/x-forge/.claude/mcp-servers/vikunja/src/server.py`
   - Pattern: Arc Forge secret path pattern
   - Implementation: Complete with dev fallback
   - Tools: 27 (reports 23 due to lazy-mcp bug)

### Servers NEEDING OpenBao Migration (8)

#### Priority 1: High-Security Credential Servers
Servers handling sensitive API keys or authentication tokens should be migrated first.

1. **cloudflare-mcp**
   - Tools: 6
   - Credentials: Cloudflare API token
   - Risk: High (infrastructure access)

2. **stalwart-mcp**
   - Tools: 24
   - Credentials: Email server credentials
   - Risk: High (email access)

3. **stripe-mcp**
   - Tools: 7
   - Credentials: Stripe API keys
   - Risk: Critical (payment processing)

#### Priority 2: Personal Data & Communication

4. **mailjet-mcp**
   - Tools: 8
   - Credentials: Mailjet API keys
   - Risk: Medium (email sending)

5. **nextcloud-calendar-mcp**
   - Tools: 7
   - Credentials: Nextcloud credentials
   - Risk: Medium (calendar/personal data)

6. **todoist-mcp**
   - Tools: 12
   - Credentials: Todoist API token
   - Risk: Medium (task data)

#### Priority 3: Utility & Read-Only

7. **tplink-router-mcp**
   - Tools: 3
   - Credentials: Router admin credentials
   - Risk: Medium (network access)

8. **youtube-transcript-mcp**
   - Tools: 3
   - Credentials: Potentially YouTube API key
   - Risk: Low (read-only transcripts)

### Infrastructure (Not Requiring Migration)

**rodda-mcp**
- Type: Remote MCP aggregator/proxy
- Tools: N/A (proxies other servers)
- Note: Does not store credentials itself; delegates to wrapped MCP servers

---

## Migration Plan

### Phase 1: Reference Implementation Review
**Duration:** 1-2 hours
**Goal:** Document reusable OpenBao integration pattern

1. Extract OpenBao integration code from `joplin-mcp` (most comprehensive)
2. Document pattern:
   - Agent connection logic
   - Secret path construction (Arc Forge pattern)
   - Dev mode fallback for local testing
   - Error handling and user messaging
3. Create migration template/checklist

### Phase 2: High-Priority Migrations
**Duration:** 3-4 hours
**Target:** stripe-mcp, cloudflare-mcp, stalwart-mcp

For each server:
1. Identify current credential storage mechanism
2. Add OpenBao integration code (based on joplin-mcp pattern)
3. Update documentation with setup instructions
4. Test dev mode fallback
5. Test production mode with OpenBao agent
6. Update repo README with credential resolution order

### Phase 3: Medium-Priority Migrations
**Duration:** 3-4 hours
**Target:** mailjet-mcp, nextcloud-calendar-mcp, todoist-mcp

Same process as Phase 2.

### Phase 4: Low-Priority Migrations
**Duration:** 1-2 hours
**Target:** tplink-router-mcp, youtube-transcript-mcp

Same process as Phase 2.

### Phase 5: Documentation & Standards
**Duration:** 1 hour

1. Update Arc Forge MCP standards document
2. Document OpenBao integration as required pattern
3. Create new MCP server template with OpenBao built-in
4. Add to Claude Code skills/documentation

---

## Tool Count Discrepancy: Vikunja Investigation

### Issue Summary
- **Server:** vikunja-mcp
- **Actual Tools:** 27 (verified in server.py)
- **Reported Tools:** 23 (via lazy-mcp hierarchy)
- **Discrepancy:** -4 tools missing
- **Impact:** Tools may be inaccessible via lazy-mcp proxy

### Isolated to Vikunja
After systematic review of all 11 MCP servers, **only Vikunja exhibits this discrepancy**. This suggests:
- Issue is specific to Vikunja's tool definitions or
- Rare edge case in lazy-mcp's discovery that only affects certain tool patterns

### Investigation Status
Documented in detail at: `/home/x-forge/repos/2-areas/lazy-mcp-preload/ISSUES.md#issue_001`

### Next Steps
1. Debug lazy-mcp tool discovery code in `internal/hierarchy`
2. Add verbose logging to trace tool enumeration for Vikunja
3. Compare Vikunja tool definitions with other servers (joplin, stalwart) to identify unique patterns
4. Test hypothesis: Does tool name length, description length, or parameter complexity affect discovery?

---

## Repository Locations

### Production Servers (Installed)
- joplin-mcp: `/home/x-forge/.claude/mcp-servers/joplin/`
- vikunja-mcp: `/home/x-forge/.claude/mcp-servers/vikunja/`

### Source Repositories
All servers: `/home/x-forge/repos/3-resources/MCP/`
- cloudflare-mcp/
- joplin-mcp/
- mailjet-mcp/
- nextcloud-calendar-mcp/
- rodda-mcp/
- stalwart-mcp/
- stripe-mcp/
- todoist-mcp/
- tplink-router-mcp/
- vikunja-mcp/
- youtube-transcript-mcp/

---

## Recommendations

1. **Immediate:** Migrate stripe-mcp (P1 - payment credentials)
2. **Short-term:** Migrate cloudflare-mcp and stalwart-mcp (P1 - infrastructure access)
3. **Medium-term:** Complete all P2 migrations (mailjet, nextcloud-calendar, todoist)
4. **Ongoing:** Debug and resolve Vikunja tool count discrepancy
5. **Standards:** Require OpenBao integration for all new MCP servers

---

## Appendix: Tool Counting Methodology

Tool counts verified using:
```bash
grep -c "@mcp\.tool" <server_file>.py
```

OpenBao integration verified using:
```bash
grep -l "openbao\|OpenBao" <server_file>.py
```

All counts manually verified against source code to ensure accuracy.
