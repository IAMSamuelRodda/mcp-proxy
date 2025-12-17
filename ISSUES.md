# ISSUES.md

> **Purpose:** Track bugs, improvements, and technical debt for lazy-mcp-preload
> **Lifecycle:** Living document, updated when issues change

**Last Updated:** 2025-12-17

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

#### issue_001: Incorrect Tool Count Reported by Hierarchy System
- **Status**: 🔴 Open
- **Priority**: P1
- **Component**: `internal/hierarchy`
- **Discovered**: 2025-12-17
- **Affects**: Tool discovery and reporting for MCP servers

**Description:**
The lazy-mcp-proxy hierarchy system incorrectly reports tool counts for MCP servers. Specifically observed with the Vikunja MCP server, where the server correctly registers 27 tools but lazy-mcp consistently reports only 23 tools.

**Evidence:**
- Vikunja MCP server verification shows 27 tools registered via `FastMCP.list_tools()`
- All 27 tools defined with `@mcp.tool` decorators in server.py
- Lazy-mcp hierarchy consistently shows "vikunja: 23 tools" in overview
- Multiple cache regenerations (including full hierarchy deletion) persist the incorrect count
- Tool execution attempts fail with "tool not found" errors

**Impact:**
- Inaccurate tool reporting in hierarchy overview
- Potential tool accessibility issues (unable to call certain tools)
- Affects user confidence in proxy functionality
- May indicate broader issue with tool discovery mechanism

**Root Cause Hypotheses:**
1. Bug in lazy-mcp's MCP protocol tool enumeration logic
2. Timeout during tool discovery (fetches only partial list)
3. Tool filtering logic incorrectly excluding valid tools
4. Connection/initialization issue preventing full tool list retrieval
5. Caching mechanism storing incorrect count from failed initial discovery

**Acceptance Criteria:**
- [ ] Lazy-mcp hierarchy reports correct tool count (27) for Vikunja
- [ ] All 27 Vikunja tools accessible via lazy-mcp interface
- [ ] Tool count matches server's actual registered tool count for all MCP servers
- [ ] Investigation documents root cause in this issue
- [ ] Fix includes test to prevent regression

**Reproduction Steps:**
1. Configure Vikunja MCP server in lazy-mcp config.json
2. Query hierarchy via `mcp__lazy-mcp__get_tools_in_category` with path "vikunja"
3. Observe reported count of 23 tools vs actual 27

**Expected vs Actual:**
- **Expected**: "vikunja: 27 tools"
- **Actual**: "vikunja: 23 tools"

**Investigation Notes:**
- Vikunja MCP server code verified correct: `/home/x-forge/.claude/mcp-servers/vikunja/src/server.py`
- Server startup successful with no errors
- Direct server inspection confirms all 27 tools present
- Issue isolated to lazy-mcp proxy layer, not Vikunja implementation
- Class naming fix applied (VikunjiaClient → VikunjaClient) - unrelated to count issue

**All 27 Tools (Verified Present in Server):**
```
vikunja_add_label_to_task
vikunja_add_reminder
vikunja_assign_task
vikunja_create_label
vikunja_create_project
vikunja_create_relation
vikunja_create_task
vikunja_delete_label
vikunja_delete_project
vikunja_delete_relation
vikunja_delete_reminder
vikunja_delete_task
vikunja_get_project_tasks
vikunja_get_relations
vikunja_get_task
vikunja_get_tasks_by_label
vikunja_get_team_members
vikunja_list_labels
vikunja_list_projects
vikunja_list_reminders
vikunja_list_tasks
vikunja_list_teams
vikunja_move_task_to_project
vikunja_remove_label_from_task
vikunja_share_project
vikunja_update_project
vikunja_update_task
```

**Related Files:**
- Vikunja server: `/home/x-forge/.claude/mcp-servers/vikunja/src/server.py`
- Lazy-mcp config: `/home/x-forge/.claude/lazy-mcp/config.json`
- Hierarchy cache: `/home/x-forge/.claude/lazy-mcp/hierarchy/`

**Next Steps:**
1. Debug lazy-mcp tool discovery code in `internal/hierarchy`
2. Add verbose logging to trace tool enumeration process
3. Compare tool discovery with other MCP servers (check if issue is widespread)
4. Test with minimal MCP server to isolate discovery mechanism
5. Review MCP protocol implementation for tool listing

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
