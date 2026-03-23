# Claude Code Agent

**English** | [中文](README_ZH.md)

`claude-code-agent` is an OpenClaw skill that turns Claude Code into a managed runtime instead of an unattended terminal session.

It adds the control plane OpenClaw needs:

- wrapper-launched Claude sessions
- per-session metadata and routing
- hook-driven wakeups back into OpenClaw
- local-to-OpenClaw handoff and reclaim
- tmux visibility when a human needs to step in

## What This Project Is

This repository is for people who want OpenClaw to supervise Claude Code as a worker.

It is **not** a replacement for Claude Code itself, and it does not try to manage arbitrary user-started `claude` sessions.

## Design Goals

- Managed sessions should not require editing global `~/.claude/settings.json`
- Each managed Claude session should map to its own OpenClaw session ID
- Default workflows should stay simple
- Experimental features should be explicit opt-ins
- Permission automation should stay conservative

## Current Runtime Model

There are three layers:

1. Claude Code executes the actual work.
2. This repo provides wrappers, session state, hooks, and routing.
3. OpenClaw decides strategy and reacts to hook wakeups.

The important managed-session fields are:

- `session_key`
- `project_label`
- `tmux_session`
- `cwd`
- `openclaw_session_id`
- `permission_mode`
- `permission_policy`
- `agent_teams_enabled`

## Key Features

### Managed sessions

- `hooks/start_claude.sh` starts an interactive managed session in `tmux`
- `hooks/run_claude.sh` runs a managed print-mode invocation
- `runtime/start_local_claude.sh` starts a session under local control first

### Session control

- `runtime/takeover.sh` hands a managed session to OpenClaw
- `runtime/reclaim.sh` returns control to the local operator
- `runtime/list_sessions.sh` and `runtime/session_status.sh` expose runtime state

### Hook integration

Always-on managed hooks:

- `Stop`
- `Notification`
- `PermissionRequest(Bash)`

Opt-in hooks when Agent Teams is enabled:

- `TeammateIdle`
- `TaskCompleted`

### Approval chain

The current approval layer is intentionally narrow:

- clearly safe read-only or verification-style Bash commands can be auto-allowed
- clearly dangerous Bash commands can be auto-denied
- everything else falls back to Claude's normal permission flow

## Simpler Defaults

- Prefer `run_claude.sh` for one-shot tasks
- Prefer `--permission-mode acceptEdits` for normal trusted repos
- Prefer `--permission-mode plan` for read-only analysis
- Treat `--dangerously-skip-permissions` as a special-case escape hatch
- Keep Agent Teams off unless you explicitly pass `--agent-teams`

## Quick Start

See [INSTALL.md](INSTALL.md) for setup details.

### Start a managed interactive session

```bash
bash hooks/start_claude.sh claude-demo /path/to/project --permission-mode acceptEdits
tmux attach -t claude-demo
```

### Start local-first, hand off later

```bash
bash runtime/start_local_claude.sh /path/to/project --permission-mode acceptEdits
bash runtime/takeover.sh my-project
bash runtime/reclaim.sh my-project
```

### Run a one-shot managed job

```bash
bash hooks/run_claude.sh /path/to/project -p --model sonnet "Analyze the repository and summarize the architecture."
```

### Enable Agent Teams explicitly

```bash
bash hooks/start_claude.sh claude-team /path/to/project --permission-mode acceptEdits --agent-teams
```

## Installation Notes

This project can live in either:

- `~/.openclaw/skills/claude-code-agent` for a managed shared skill
- `~/.openclaw/workspace/skills/claude-code-agent` for a workspace-local clone

The wrappers do not depend on a hard-coded install path.

If you want optional global Claude hooks for unmanaged sessions, use [hooks/hooks_config.json](hooks/hooks_config.json) as a template and replace `__SKILL_DIR__` with the real absolute path first.

## Repository Layout

| Path | Purpose |
|------|---------|
| `hooks/` | Claude hook handlers and launch wrappers |
| `runtime/` | session store, handoff, reclaim, and inspection scripts |
| `tests/` | regression coverage |
| `knowledge/` | reference notes used to maintain the skill |

## Requirements

- OpenClaw
- Claude Code with working auth
- `tmux`
- `jq`

After installation, the first check should usually be:

```bash
bash tests/regression.sh
```

## Status

- Latest release tag: `v0.2.0`
- `main` currently contains post-release simplification work
- Compatibility baseline:
  - OpenClaw `2026.3.11+`
  - Claude Code `2.1.80+`

For release history, see [CHANGELOG.md](CHANGELOG.md).

## Non-Goals

- replacing Claude Code itself
- silently mutating every user's global Claude config
- auto-approving all shell access
- enabling experimental team features for every managed session by default

## Documentation

- [INSTALL.md](INSTALL.md)
- [CHANGELOG.md](CHANGELOG.md)
- [SKILL.md](SKILL.md)
- [README_ZH.md](README_ZH.md)
- [knowledge/](knowledge)
