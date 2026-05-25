# Zammad Developer Agent Users

10 dedicated Zammad identities for the mPorts Review-Gated Developer Agent
system. Each identity maps 1:1 to a developer-agent runtime slot.

## User inventory

| Slot | Email | Display Name | User ID | Role | Group |
|------|-------|-------------|---------|------|-------|
| 1 | developer-1@mports.local | Developer Agent 1 | 10 | mPorts Engineering Agent | Engineering Bugs (full) |
| 2 | developer-2@mports.local | Developer Agent 2 | 11 | mPorts Engineering Agent | Engineering Bugs (full) |
| 3 | developer-3@mports.local | Developer Agent 3 | 12 | mPorts Engineering Agent | Engineering Bugs (full) |
| 4 | developer-4@mports.local | Developer Agent 4 | 13 | mPorts Engineering Agent | Engineering Bugs (full) |
| 5 | developer-5@mports.local | Developer Agent 5 | 14 | mPorts Engineering Agent | Engineering Bugs (full) |
| 6 | developer-6@mports.local | Developer Agent 6 | 15 | mPorts Engineering Agent | Engineering Bugs (full) |
| 7 | developer-7@mports.local | Developer Agent 7 | 16 | mPorts Engineering Agent | Engineering Bugs (full) |
| 8 | developer-8@mports.local | Developer Agent 8 | 17 | mPorts Engineering Agent | Engineering Bugs (full) |
| 9 | developer-9@mports.local | Developer Agent 9 | 18 | mPorts Engineering Agent | Engineering Bugs (full) |
| 10 | developer-10@mports.local | Developer Agent 10 | 19 | mPorts Engineering Agent | Engineering Bugs (full) |

## Security properties

- **NOT Admin** — none of these users have the Admin role. They cannot access
  Zammad settings, manage other users, or modify system configuration.
- **Engineering Bugs only** — group access is scoped to the "Engineering Bugs"
  group with `full` permission (read, create, update). They cannot see tickets
  in other groups (e.g., general support).
- **API tokens** — each user has a persistent API token for runtime
  authentication. Tokens are stored in the Zammad database `tokens` table,
  NOT in git. Rotate via the Zammad admin UI or Rails console.
- **Review-Gated only** — these agents operate in Review-Gated Mode. They
  propose changes; a human reviews and approves before merge.

## Runtime slot mapping

Each developer-agent runtime maps to exactly one worktree and one Zammad
identity:

```
developer-1  → /workspaces/mPorts-agents/mPorts-worktree-developer-1
developer-2  → /workspaces/mPorts-agents/mPorts-worktree-developer-2
developer-3  → /workspaces/mPorts-agents/mPorts-worktree-developer-3
developer-4  → /workspaces/mPorts-agents/mPorts-worktree-developer-4
developer-5  → /workspaces/mPorts-agents/mPorts-worktree-developer-5
developer-6  → /workspaces/mPorts-agents/mPorts-worktree-developer-6
developer-7  → /workspaces/mPorts-agents/mPorts-worktree-developer-7
developer-8  → /workspaces/mPorts-agents/mPorts-worktree-developer-8
developer-9  → /workspaces/mPorts-agents/mPorts-worktree-developer-9
developer-10 → /workspaces/mPorts-agents/mPorts-worktree-developer-10
```

## Environment variables for runtimes

Each developer-agent runtime should be configured with:

```bash
# Zammad connection
ZAMMAD_URL=https://help.example.com
ZAMMAD_AGENT_TOKEN=<token from secret store>

# Identity
DEVELOPER_AGENT_ID=developer-1
DEVELOPER_AGENT_USER_ID=10
DEVELOPER_AGENT_EMAIL=developer-1@mports.local

# Worktree
DEVELOPER_WORKTREE_PATH=/workspaces/mPorts-agents/mPorts-worktree-developer-1
```

Tokens must come from a secret manager (1Password, Vault, AWS SecretsManager,
etc.) — never from env files committed to git.

## API usage

### Authenticate

```bash
curl -H "Authorization: Token token=$ZAMMAD_AGENT_TOKEN" \
  $ZAMMAD_URL/api/v1/users/me
```

### Query tickets assigned to this agent

```bash
curl -H "Authorization: Token token=$ZAMMAD_AGENT_TOKEN" \
  "$ZAMMAD_URL/api/v1/tickets/search?query=owner.email:$DEVELOPER_AGENT_EMAIL&limit=50"
```

### Query approved tickets ready for processing

```bash
curl -H "Authorization: Token token=$ZAMMAD_AGENT_TOKEN" \
  "$ZAMMAD_URL/api/v1/tickets/search?query=owner.email:$DEVELOPER_AGENT_EMAIL+mports_agent_approved:true&limit=50"
```

## Token rotation

Tokens can be rotated without downtime:

```ruby
# In rails console:
u = User.find_by(email: "developer-1@mports.local")
old_token = Token.find_by(user_id: u.id, action: "api")
new_token = Token.create!(
  action: "api", persistent: true, user_id: u.id,
  name: "developer-agent-runtime-1-rotated-#{Date.today}",
  preferences: { permission: %w[ticket.agent] },
)
puts "New token: #{new_token.token}"
# Update the secret store, then delete the old token:
# old_token.destroy!
```

## What these users are NOT

- They are NOT Linux/VM user accounts
- They are NOT Admin users
- They do NOT have webhooks or polling configured (yet)
- They do NOT have automation triggers (yet)
- They are purely logical Zammad identities for ticket assignment and audit
