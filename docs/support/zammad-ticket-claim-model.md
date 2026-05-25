# Zammad Ticket Claim Model

How developer-agent runtimes claim and process tickets using Zammad's native
assignee mechanism.

## Overview

Zammad's `owner_id` field (displayed as "Owner" or "Assignee" in the UI) is
the claim/lock mechanism. When a ticket is assigned to `developer-3`, only the
`developer-3` runtime should pull and process that ticket. No other runtime
touches it.

This is a **convention, not a Zammad enforcement** — Zammad allows any agent
with group access to update any ticket. The enforcement lives in the runtime's
polling query: each runtime only queries for tickets assigned to its own
identity.

## Assignment workflow

```
┌─────────────┐     ┌───────────────┐     ┌──────────────────┐     ┌──────────────┐
│ Ticket       │     │ Human triage  │     │ Human approval   │     │ Runtime      │
│ created      │────▶│               │────▶│                  │────▶│ picks up     │
│ (customer    │     │ Assigns to    │     │ Sets             │     │ & processes  │
│  or API)     │     │ developer-X   │     │ mports_agent_    │     │ ticket       │
└─────────────┘     │               │     │ approved=true    │     └──────────────┘
                    └───────────────┘     └──────────────────┘
```

### Step by step

1. **Ticket arrives** — created by customer (web/email) or via the mPorts
   engineering bug API. Lands in the "Engineering Bugs" group, unassigned.

2. **Human triages** — a human agent reviews the ticket, decides which
   developer-agent slot should handle it, and assigns the ticket:
   - Sets `owner_id` to the target developer (e.g., Developer Agent 3)
   - Optionally sets `mports_severity`, `mports_feature_area`, etc.

3. **Human approves** — when the ticket is ready for automated processing:
   - Sets `mports_agent_approved = true`
   - This is the gate: runtimes ignore tickets where this field is not `true`

4. **Runtime polls** — `developer-3`'s runtime queries:
   ```
   GET /api/v1/tickets/search?query=owner.email:developer-3@mports.local+mports_agent_approved:true
   ```
   Only tickets assigned to `developer-3` AND approved come back.

5. **Runtime processes** — the runtime:
   - Reads the ticket body + attachments for context
   - Works in its dedicated worktree (`mPorts-worktree-developer-3`)
   - Creates a branch, implements the fix, opens a PR
   - Updates the ticket with status notes (via internal articles)
   - Sets `mports_agent_state` to track progress (e.g., `in_progress`, `pr_opened`, `merged`)

6. **Human reviews** — the human reviews the PR. If approved, merges it and
   closes the ticket (or the runtime closes it after merge confirmation).

## Claim isolation

| Runtime | Queries for | Worktree | Ignores |
|---------|------------|----------|---------|
| developer-1 | `owner.email:developer-1@mports.local` | `mPorts-worktree-developer-1` | All other tickets |
| developer-2 | `owner.email:developer-2@mports.local` | `mPorts-worktree-developer-2` | All other tickets |
| ... | ... | ... | ... |
| developer-10 | `owner.email:developer-10@mports.local` | `mPorts-worktree-developer-10` | All other tickets |

A ticket can only have one owner at a time. Reassigning a ticket from
`developer-3` to `developer-5` transfers the claim — `developer-3`'s runtime
will stop seeing it on its next poll, and `developer-5`'s will pick it up.

## Custom fields used

| Field | Purpose | Set by |
|-------|---------|--------|
| `mports_agent_approved` | Gate: runtime only acts when `true` | Human |
| `mports_agent_state` | Runtime progress tracking | Runtime |
| `mports_severity` | Bug severity (critical/high/medium/low) | Human or API |
| `mports_feature_area` | Which part of the codebase | Human or API |
| `mports_environment` | Where the bug was observed | Human or API |
| `mports_trace_id` | Correlation ID from the originating system | API |
| `mports_pr_url` | Link to the PR the runtime created | Runtime |

## Why assignee, not a custom field

- **Native UI** — Zammad's owner dropdown is a first-class UI element. Humans
  can assign tickets with one click, no custom field hunting.
- **Built-in constraints** — Zammad enforces that the owner must be an agent
  in the ticket's group. You can't accidentally assign a ticket to a customer
  or a user without Engineering Bugs access.
- **Search/filter** — `owner.email:X` is a native Zammad search operator.
  No custom index needed.
- **Audit trail** — Zammad logs owner changes in the ticket history
  automatically, including who changed it and when.

## Why not webhooks (yet)

V1 uses polling because:
- Simpler to deploy and debug
- No webhook endpoint to secure
- No missed-delivery risk
- Polling interval can be tuned per-runtime

Future versions may add Zammad triggers that fire webhooks on assignment +
approval, converting from pull to push. The user identities and claim model
remain the same either way.

## Scaling

10 slots supports 10 concurrent developer-agent runtimes. If more are needed:
- Create additional `developer-11@mports.local` etc. users
- Same role (mPorts Engineering Agent), same group (Engineering Bugs)
- Generate a new API token per slot
- Map to a new worktree

The assignment model scales linearly — each slot is independent.
