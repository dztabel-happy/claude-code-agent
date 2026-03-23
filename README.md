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

## How You Actually Use It

For normal day-to-day use, you do **not** manually run the wrapper scripts first.

Your normal entry point is **OpenClaw conversation**, for example:

- "Use `claude-code-agent` to analyze `/path/to/project`."
- "Use `claude-code-agent` to fix this bug in `/path/to/project`, run tests, then report back."
- "Use `claude-code-agent` to review the current changes in `/path/to/project`."
- "Use `claude-code-agent` to do a read-only audit of `/path/to/project`."

OpenClaw should then choose this skill, launch or reuse a managed Claude Code session, and continue the task through hook wakeups.

The shell scripts in this repo are mainly:

- the skill's internal control plane
- manual recovery and debugging tools
- a direct fallback when you want to inspect or take over a live Claude session yourself

## OpenClaw Sleep / Wake Model

Yes: OpenClaw is expected to "go idle" between steps and wait for Claude Code to wake it through hooks.

In the managed flow:

1. OpenClaw launches or reuses a managed Claude Code session.
2. Claude Code works inside that session.
3. A hook event such as `Stop`, `Notification`, or `PermissionRequest` wakes OpenClaw.
4. OpenClaw continues the same managed session instead of busy-waiting.

This means the intended runtime model is event-driven, not "OpenClaw constantly watching a terminal".

## Manual Takeover And Return

You can step in at any time, but there are two different levels of intervention.

### 1. Inspect or talk to Claude directly

Attach to tmux:

```bash
tmux attach -t <session-name>
```

This lets you watch the live Claude Code session and reply manually.

However, this does **not** formally transfer ownership away from OpenClaw. It is a live intervention, not a routing change.

### 2. Formally take control back from OpenClaw

If you want the session to stop being OpenClaw-managed and become locally controlled, run:

```bash
bash runtime/reclaim.sh <selector>
```

Later, when you want OpenClaw to resume control:

```bash
bash runtime/takeover.sh <selector>
```

So the practical rule is:

- `tmux attach` = inspect or intervene live
- `runtime/reclaim.sh` = formally switch ownership back to local control
- `runtime/takeover.sh` = formally hand the session back to OpenClaw

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

The quickest way to understand this project is:

1. Install the skill where OpenClaw can discover it.
2. Ask OpenClaw to use `claude-code-agent` for a task.
3. Let OpenClaw sleep between Claude hook wakeups.
4. Use `tmux attach`, `runtime/reclaim.sh`, or `runtime/takeover.sh` only when you want to inspect or change control manually.

See [INSTALL.md](INSTALL.md) for setup details.

### OpenClaw-driven daily usage

Typical daily prompts to OpenClaw:

```text
Use claude-code-agent to analyze /path/to/project.
Use claude-code-agent to fix a bug in /path/to/project and run tests before reporting back.
Use claude-code-agent to review the current changes in /path/to/project.
Use claude-code-agent to do a read-only audit of /path/to/project.
```

### Manual fallback: start a managed interactive session

```bash
bash hooks/start_claude.sh claude-demo /path/to/project --permission-mode acceptEdits
tmux attach -t claude-demo
```

### Manual fallback: start local-first, hand off later

```bash
bash runtime/start_local_claude.sh /path/to/project --permission-mode acceptEdits
bash runtime/takeover.sh my-project
bash runtime/reclaim.sh my-project
```

### Manual fallback: run a one-shot managed job

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
