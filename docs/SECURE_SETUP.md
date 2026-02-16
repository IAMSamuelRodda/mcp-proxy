# Secure Setup: OpenBao + Bitwarden Integration

Production-grade secrets management for MCP servers using OpenBao (HashiCorp Vault fork) with Bitwarden for credential bootstrapping.

**Use this if:** You need centralized secrets, audit trails, or manage multiple machines.

**Skip this if:** Local dev only → use `.env` files instead.

---

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ Bitwarden Vault │────>│ bitwarden-guard  │────>│ obao  │
│ (master creds)  │     │ (session mgmt)   │     │ (local agents)  │
└─────────────────┘     └──────────────────┘     └────────┬────────┘
                                                          │
                        ┌──────────────────┐              │ SSH tunnel
                        │   MCP Servers    │<─────────────┤
                        │ (fetch secrets)  │              │
                        └──────────────────┘     ┌────────▼────────┐
                                                 │  OpenBao Server │
                                                 │   (VPS/remote)  │
                                                 └─────────────────┘
```

---

## Prerequisites

| Component | Purpose | Install |
|-----------|---------|---------|
| Bitwarden CLI | Credential storage | `sudo snap install bw` |
| OpenBao CLI | Secrets engine | [openbao.org/downloads](https://openbao.org/downloads) |
| OpenBao Server | Remote secrets store | Self-hosted on VPS |

---

## Quick Start

```bash
# Clone mcp-proxy
git clone https://github.com/IAMSamuelRodda/mcp-proxy.git
cd mcp-proxy

# Run bootstrap (clones dependencies, installs everything)
./scripts/bootstrap.sh
```

---

## Manual Setup

### Step 1: bitwarden-guard

Session management for Bitwarden CLI.

```bash
git clone https://github.com/IAMSamuelRodda/bitwarden-guard.git ~/.claude/deps/bitwarden-guard
cd ~/.claude/deps/bitwarden-guard && ./install.sh
```

**Verify:** `bitwarden-guard unlock` prompts for master password.

### Step 2: obao

Local agents that authenticate to OpenBao via AppRole.

```bash
git clone https://github.com/IAMSamuelRodda/obao.git ~/.claude/deps/obao
cd ~/.claude/deps/obao && ./install.sh
```

**Creates:** `start-openbao-mcp`, `start-openbao-admin`, `start-openbao-workstation`

### Step 3: Bitwarden Items

Create these items in Bitwarden:

| Item Name | Password Field | Custom Field |
|-----------|---------------|--------------|
| `OpenBao Client0 MCP AppRole` | `secret_id` | `Role-ID` = `role_id` |
| `OpenBao Dev Admin AppRole` | `secret_id` | `Role-ID` = `role_id` |
| `OpenBao Dev Machine AppRole` | `secret_id` | `Role-ID` = `role_id` |

### Step 4: Extract Role IDs

```bash
# Unlock Bitwarden
bitwarden-guard unlock
BW_SESSION=$(cat ~/.bitwarden-guard/sessions/current)

# Extract and save role_ids
bw list items --search "OpenBao Dev Admin AppRole" --session "$BW_SESSION" | \
  jq -r '.[0].fields[] | select(.name == "Role-ID") | .value' \
  > ~/.config/openbao-agent/role-id-admin

bw list items --search "OpenBao Client0 MCP AppRole" --session "$BW_SESSION" | \
  jq -r '.[0].fields[] | select(.name == "Role-ID") | .value' \
  > ~/.config/openbao-agent/role-id-mcp

bw list items --search "OpenBao Dev Machine AppRole" --session "$BW_SESSION" | \
  jq -r '.[0].fields[] | select(.name == "Role-ID") | .value' \
  > ~/.config/openbao-agent/role-id

chmod 600 ~/.config/openbao-agent/role-id*
```

### Step 5: Test Agent

```bash
start-openbao-mcp
# Should prompt for Bitwarden password if no session
# Then: "MCP agent ready at http://127.0.0.1:18200"

curl http://127.0.0.1:18200/v1/sys/health
```

### Step 6: Configure mcp-proxy

Create `config/config.local.json` with secrets provider:

```json
{
  "mcpProxy": {
    "hierarchyPath": "${MCP_PROXY_DIR}/hierarchy",
    "options": {
      "secretsProvider": "openbao",
      "secretsAutoStart": true,
      "secretsAutoStartCmd": "start-openbao-mcp",
      "secretsProviderAddr": "http://127.0.0.1:18200"
    }
  },
  "mcpServers": { ... }
}
```

### Step 7: Build & Deploy

```bash
make build
make deploy
cp config/config.local.json ~/.claude/mcp-proxy/config.json
make generate-hierarchy
```

---

## Agent Ports

| Agent | Port | Purpose |
|-------|------|---------|
| MCP | 18200 | Read-only for MCP servers |
| Admin | 18201 | Full secret/policy management |
| Workstation | 18202 | Developer access |

---

## Storing MCP Secrets in OpenBao

```bash
# Start admin agent
start-openbao-admin

# Store a secret
curl -X POST http://127.0.0.1:18201/v1/secret/data/mcp/myservice \
  -d '{"data":{"api_key":"sk-xxx","api_secret":"yyy"}}'

# MCP servers read via port 18200
curl http://127.0.0.1:18200/v1/secret/data/mcp/myservice
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "No Bitwarden session" | Run `bitwarden-guard unlock` |
| "role_id file not found" | Run Step 4 to extract from Bitwarden |
| "SSH tunnel failed" | Check `~/.ssh/config` has host entry |
| "OpenBao not accessible" | Verify VPS is running, firewall allows 8200 |

---

## Security Notes

- `secret_id` fetched at runtime (never on disk)
- `role_id` stored in `~/.config/openbao-agent/` (not sensitive, like username)
- All secrets accessed via local agent (no direct remote calls)
- Bitwarden master password only entered once per session
