---
title: SDLC Pipeline
summary: Automated software development lifecycle using OpenClaw agents, Linear, and GitHub Actions
read_when: Setting up an automated development pipeline with AI agents
---

# SDLC Pipeline: Agents → Tickets → Code → Merge

An automated software development pipeline where OpenClaw agents collaborate on product decisions via Telegram, create Linear tickets, and trigger Claude Code implementation via GitHub Actions — with a human-in-the-loop question/answer flow.

## Architecture

```
CEO → Chief of Staff (CEO-DIRECTIVES) → PRODUCT-ROOM (all agents collaborate)
  → PM creates Linear ticket → ticket moved to "Ready"
  → Linear webhook → OpenClaw /hooks/linear → PM triggers GitHub Actions
  → Claude Code implements → PR created
  → Questions? → OpenClaw /hooks/agent → DEV-HANDOFF (Head of Product facilitates)
  → Head of Product posts answer as PR comment via github skill
  → Human adds "ready-to-continue" label → Claude Code resumes
  → PR ready → Human reviews and merges → Linear ticket → Done
```

## Why OpenClaw Native

Three built-in capabilities replace all middleware:

1. **Hooks endpoint** (`POST /hooks/agent`) — receives external webhooks (Linear, GitHub Actions), routes to agents. `deliver: true` auto-sends the agent's response to a Telegram group.
2. **`github` skill** — agents can run `gh api` commands to trigger GitHub Actions, post PR comments, manage labels.
3. **`message` tool** — agents can send messages to any Telegram group directly.

No Cloudflare Workers, no bridge bots, no Slack webhooks.

## Agent Roles

| Agent | Role | Channels | Key Tools |
|-------|------|----------|-----------|
| Chief of Staff | Receives CEO directives, delegates | CEO-DIRECTIVES, PRODUCT-ROOM | message |
| Head of Product | Facilitates product decisions, answers dev questions | PRODUCT-ROOM, DEV-HANDOFF | message, github |
| Product Manager | Creates tickets, triggers implementation | PRODUCT-ROOM, TICKETS | exec, message, github |
| Product Marketing | User voice, positioning | PRODUCT-ROOM | message |
| UX Designer | Design decisions, UX guidance | PRODUCT-ROOM, DEV-HANDOFF | message |

## Telegram Groups

| Group | Purpose | Mention Required |
|-------|---------|-----------------|
| CEO-DIRECTIVES | Direct CEO → Chief of Staff communication | No |
| PRODUCT-ROOM | All agents collaborate on specs | Yes (@mention) |
| TICKETS | Ticket creation notifications | No |
| DEV-HANDOFF | Dev questions from Claude Code PRs | Yes (@mention) |

## Linear Workflow Statuses

| Status | Automation Role |
|--------|----------------|
| Triage | New tickets land here |
| Backlog | Parked for later |
| Ready | Triggers Claude Code via GitHub Actions |
| In Progress | Claude Code is working |
| Needs Input | Blocked on a product question |
| Needs Review | PR ready for human review |
| Done | PR merged |

## Flow Details

### 1. Ticket Creation (Conversation → Linear)

1. CEO talks to Chief of Staff in CEO-DIRECTIVES
2. Chief of Staff delegates to PRODUCT-ROOM where agents collaborate
3. Product Manager synthesizes a spec and creates a Linear ticket via GraphQL API:
   ```bash
   curl -s -X POST https://api.linear.app/graphql \
     -H "Authorization: Bearer $LINEAR_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"query":"mutation { issueCreate(input: { teamId: \"TEAM_ID\", title: \"...\", description: \"...\" }) { issue { id identifier url } } }"}'
   ```
4. PM posts ticket link to TICKETS group via `message` tool

### 2. Implementation (Linear → Code)

1. Ticket moved to "Ready" in Linear
2. Linear webhook → OpenClaw `/hooks/linear` → PM agent
3. PM triggers GitHub Actions via `github` skill:
   ```bash
   gh api repos/OWNER/REPO/dispatches \
     -f event_type=linear-ticket-ready \
     -f 'client_payload[ticket_id]=PROJ-123' \
     -f 'client_payload[issue_id]=LINEAR-UUID' \
     -f 'client_payload[title]=Ticket Title' \
     -f 'client_payload[description]=Description...'
   ```
4. Claude Code implements the feature on a `feature/PROJ-123` branch

### 3. Question Loop (supports multiple rounds)

1. Claude Code has questions → creates draft PR with `[QUESTION]` comments
2. GitHub Action → OpenClaw `/hooks/agent` (`deliver: true`) → message in DEV-HANDOFF
3. Head of Product facilitates answer in Telegram
4. Head of Product posts answer as PR comment via `github` skill + removes "needs-input" label
5. Human adds "ready-to-continue" label (human-in-the-loop checkpoint)
6. Claude Code resumes → may loop back if more questions
7. When done → PR marked ready for review

### 4. Completion

1. Human reviews and merges PR
2. `linear-done.yml` workflow extracts ticket ID from PR title
3. Linear ticket automatically moved to "Done"

## OpenClaw Configuration

### Hooks (Linear Webhook → Agent)

```json
"hooks": {
  "enabled": true,
  "token": "<HOOKS_TOKEN>",
  "mappings": {
    "linear": {
      "match": { "source": "linear" },
      "action": "agent",
      "agentId": "product-manager",
      "messageTemplate": "Linear ticket moved to Ready:\n\nTicket: {{data.identifier}}\nTitle: {{data.title}}\nDescription: {{data.description}}\n\nPlease trigger the GitHub Action...",
      "deliver": true,
      "channel": "telegram",
      "to": "<TICKETS_GROUP_ID>"
    }
  }
}
```

### Agent Tools

```json
{
  "id": "product-manager",
  "tools": {
    "allow": ["exec", "group:sessions", "message", "github"]
  }
}
```

- **exec**: Run `curl` for Linear API calls
- **github**: Run `gh api` for GitHub Actions and PR management
- **message**: Send messages to Telegram groups

See [telegram-config-template.json](/gateway/telegram-config-template.json) for a complete configuration example.

## GitHub Actions Workflow

The `implement-ticket.yml` workflow handles both initial implementation and continuation after questions are answered:

- **Trigger 1**: `repository_dispatch` (type: `linear-ticket-ready`) — new ticket implementation
- **Trigger 2**: `pull_request: labeled` (label: `ready-to-continue`) — resume after Q&A

Key design for multi-round support:
- PR URL resolved from either trigger type (falls back to `github.event.pull_request.html_url`)
- Ticket ID extracted from PR title (format: `PROJ-123: Title`) — works on all rounds
- Linear issue ID looked up via GraphQL API by ticket number — not dependent on `client_payload`

## Required Secrets & Variables

### GitHub Repository Secrets

| Secret | Purpose |
|--------|---------|
| `ANTHROPIC_API_KEY` | Claude Code API access |
| `LINEAR_API_KEY` | Update Linear ticket statuses |
| `OPENCLAW_GATEWAY_URL` | OpenClaw gateway endpoint |
| `OPENCLAW_HOOKS_TOKEN` | Authenticate webhook calls |
| `TELEGRAM_DEV_HANDOFF_GROUP_ID` | DEV-HANDOFF Telegram group |

### GitHub Repository Variables

| Variable | Purpose |
|----------|---------|
| `LINEAR_STATE_IN_PROGRESS` | Linear "In Progress" state ID |
| `LINEAR_STATE_NEEDS_INPUT` | Linear "Needs Input" state ID |
| `LINEAR_STATE_NEEDS_REVIEW` | Linear "Needs Review" state ID |
| `LINEAR_STATE_DONE` | Linear "Done" state ID |

### Railway Environment Variables

| Variable | Purpose |
|----------|---------|
| Telegram bot tokens (one per agent) | Agent communication |
| `GH_TOKEN` | GitHub PAT for `github` skill |
| `LINEAR_API_KEY` | PM's ticket creation via exec+curl |
| `OPENCLAW_HOOKS_TOKEN` | Hooks authentication |

## Setup Checklist

- [ ] Create Telegram bots via BotFather (disable privacy, enable join groups)
- [ ] Create Telegram supergroups with correct bot members
- [ ] Update OpenClaw config with Telegram channels + hooks
- [ ] Deploy SOUL.md files for agents with special responsibilities
- [ ] Set up Linear webhook pointing to OpenClaw gateway
- [ ] Configure GitHub secrets and variables
- [ ] Configure Railway environment variables
- [ ] Test end-to-end: conversation → ticket → implementation → Q&A → merge → done
