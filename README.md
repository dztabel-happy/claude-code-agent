# Claude Code Agent

**English** | [中文](README_ZH.md)

`claude-code-agent` is an OpenClaw skill that turns Claude Code into a managed runtime instead of a terminal session that someone has to babysit manually.

It adds the operational pieces OpenClaw needs in practice:

- wrapper-launched Claude sessions instead of unmanaged `claude` processes
- per-session metadata and routing
- hook-driven wakeups back into OpenClaw
- local-to-OpenClaw handoff and reclaim
- tmux visibility when a human needs to step in

This repository is mainly for people who want OpenClaw to drive Claude Code as a worker. If you only use Claude Code directly, you probably do not need it.

## Why This Exists

Claude Code already has strong native capabilities. What it does not provide by itself is a clean control plane for a supervisor such as OpenClaw.

This project fills that gap by providing:

- a managed session wrapper around Claude Code
- runtime-generated `--settings` overlays for hooks
- explicit per-session `openclaw session-id` routing
- session inspection and handoff scripts
- a conservative approval layer for Bash permission requests

The goal is straightforward: let OpenClaw keep the right Claude session moving without mixing projects, depending on hand-edited global config, or losing the option to inspect the live terminal.

## What It Does

- Starts managed interactive Claude sessions in `tmux`
- Runs one-shot Claude print jobs through the same managed runtime
- Tracks session state in a local runtime store
- Wakes OpenClaw on Claude lifecycle events
- Supports local-first sessions that can be handed off later
- Adds a `PermissionRequest(Bash)` hook for narrow auto-allow and auto-deny cases
- Supports optional quality gates on `TaskCompleted`

## Design Choices

- Managed sessions do not require editing global `~/.claude/settings.json`
- Hooks are injected at runtime with `--settings`
- Each managed Claude session gets its own deterministic OpenClaw session ID
- Only wrapper-launched sessions are managed
- The system stays inspectable through `tmux attach`
- Permission automation is intentionally conservative

## Runtime Model

There are three layers:

1. Claude Code executes the work.
2. The wrappers and hooks in this repo handle session state, routing, and lifecycle events.
3. OpenClaw decides strategy, sends follow-up instructions, and reacts to hook wakeups.

Important session fields:

- `session_key`
- `project_label`
- `tmux_session`
- `cwd`
- `openclaw_session_id`
- `permission_mode`
- `permission_policy`

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

The managed overlay wires in these Claude hooks:

- `Stop`
- `Notification`
- `PermissionRequest(Bash)`
- `TeammateIdle`
- `TaskCompleted`

### Approval chain

The current approval layer is deliberately small in scope:

- clearly safe read-only or verification-style Bash commands can be auto-allowed
- obviously dangerous Bash commands can be auto-denied
- everything else falls back to Claude's normal permission flow

This reduces approval friction without pretending that all shell requests are safe to automate.

## Quick Start

See [INSTALL.md](INSTALL.md) for setup details.

Common entry points:

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

## Repository Layout

| Path | Purpose |
|------|---------|
| `hooks/` | Claude hook handlers and launch wrappers |
| `runtime/` | session store, handoff, reclaim, and inspection scripts |
| `tests/` | regression coverage |
| `knowledge/` | reference notes used to maintain the skill |

## Main Scripts

| Script | Purpose |
|------|---------|
| `hooks/start_claude.sh` | start an interactive managed Claude session |
| `hooks/run_claude.sh` | run a managed print-mode Claude invocation |
| `hooks/stop_claude.sh` | stop a managed session |
| `runtime/start_local_claude.sh` | start a local-first session that can later be handed off |
| `runtime/takeover.sh` | transfer control of a managed session to OpenClaw |
| `runtime/reclaim.sh` | return a session to local control |
| `runtime/list_sessions.sh` | list managed sessions |
| `runtime/session_status.sh` | inspect session metadata |

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
- `main` currently contains post-release work for the `PermissionRequest` approval chain
- Compatibility baseline:
  - OpenClaw `2026.3.11+`
  - Claude Code `2.1.80+`

For release history, see [CHANGELOG.md](CHANGELOG.md).

## Non-Goals

- replacing Claude Code itself
- managing arbitrary user-started `claude` sessions
- silently mutating every global Claude config on the machine
- auto-approving all shell access

## Documentation

- [INSTALL.md](INSTALL.md)
- [CHANGELOG.md](CHANGELOG.md)
- [SKILL.md](SKILL.md)
- [README_ZH.md](README_ZH.md)
- [knowledge/](knowledge)
