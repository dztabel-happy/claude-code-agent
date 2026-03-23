# Claude Code Agent

**English** | [中文](README.md)

An OpenClaw-exclusive skill that upgrades Claude Code from “a CLI you manually babysit” into a managed runtime with explicit session routing, native-hook supervision, and local-to-remote handoff.

> Current release: `v0.2.0`
> Compatibility baseline: OpenClaw `2026.3.11+`, Claude Code `2.1.80+`

## What It Is

This project lets OpenClaw operate Claude Code as a managed worker:

- design better prompts than a human usually writes
- choose model, effort, permission mode, and session strategy
- supervise Claude through tmux
- react to Claude native hooks (`Stop`, `Notification`, `TeammateIdle`, `TaskCompleted`)
- hand sessions from local control to OpenClaw and back again

## What Changed In This Upgrade

### Managed settings are now injected automatically

Managed sessions no longer depend on the user manually editing global `~/.claude/settings.json`.

The wrappers now generate a session-scoped Claude settings overlay and inject it with `--settings`.

### Every managed Claude session now gets its own OpenClaw session

This is the biggest architectural fix in the upgrade.

Before, multiple Claude-managed projects could wake the same OpenClaw agent conversation and cross-contaminate context.

Now:

- each managed Claude session maps to a deterministic `openclaw session-id`
- hook wake-ups use explicit `openclaw agent --session-id ...`
- multi-project supervision is much safer

### The knowledge base is synced to current Claude Code behavior

The repo now reflects:

- local Claude Code: `2.1.80`
- npm latest at check time: `2.1.81`

The knowledge base now explicitly covers:

- `--settings`
- `--setting-sources`
- `--session-id`
- `--effort`
- `--plugin-dir`
- `--ide`
- `--no-session-persistence`
- `permission-mode auto`

## v0.2.0 Highlights

- managed Claude sessions no longer share the same OpenClaw conversation by default
- wrappers now inject Claude managed settings overlays automatically
- docs and knowledge are maintained against both official docs and live CLI introspection
- regression coverage now includes session routing and settings overlay behavior

## Architecture

### Claude Code

Claude is still the execution engine.

### Managed wrappers

- `hooks/start_claude.sh`
- `hooks/run_claude.sh`
- `runtime/start_local_claude.sh`

They provide:

- managed session metadata
- Claude settings overlay injection
- handoff-safe runtime boundaries

### OpenClaw

OpenClaw remains the strategist and supervisor:

- understand the user request
- choose the best runtime strategy
- react to hook wake-ups
- keep the correct managed session moving

## Session Model

- **Unmanaged session**: user runs `claude` directly; this skill ignores it
- **OpenClaw-managed session**: wrapper-launched, `controller=openclaw`
- **Locally managed session**: launched with `runtime/start_local_claude.sh`, starts as `controller=local`

Important identifiers:

- `session_key`
- `project_label`
- `tmux_session`
- `cwd`
- `openclaw_session_id`

## Main Scripts

| Script | Purpose |
|------|---------|
| `hooks/run_claude.sh` | One-shot managed execution (`-p/--print` required) |
| `hooks/start_claude.sh` | Managed interactive tmux Claude session |
| `hooks/stop_claude.sh` | Stop a managed tmux session |
| `runtime/start_local_claude.sh` | Start a local-first handoff-capable session |
| `runtime/list_sessions.sh` | List managed sessions |
| `runtime/session_status.sh` | Inspect managed session metadata |
| `runtime/takeover.sh` | Hand a session to OpenClaw |
| `runtime/reclaim.sh` | Return a session to local control |

## Quick Start

See [INSTALL.md](INSTALL.md).

Common entry points:

```bash
# Start a managed session directly
bash hooks/start_claude.sh claude-demo /path/to/project --permission-mode acceptEdits

# Start local-first, then hand off later
bash runtime/start_local_claude.sh /path/to/project --permission-mode acceptEdits
bash runtime/takeover.sh my-project
bash runtime/reclaim.sh my-project
```

## Upgrading From Older Docs

If you previously followed the older setup style:

- manually merging this project's hooks into global `~/.claude/settings.json`
- changing OpenClaw session reset policy just to keep Claude-managed sessions alive

those are no longer hard prerequisites for managed sessions. The upgraded runtime is designed to rely on wrapper-scoped settings injection instead of global config coupling.

## Current State

The upgraded repo now includes regression coverage for:

- wake deduplication
- quality gate blocking
- selector ambiguity handling
- explicit OpenClaw `--session-id` routing
- managed Claude settings overlay injection

## Design Philosophy

The old mental model was “teach OpenClaw to operate Claude Code like a human in a terminal”.

The upgraded mental model is stronger:

- Claude Code is the execution engine
- OpenClaw is the strategist and supervisor
- the wrappers are the runtime control plane

That makes this feel much more like a durable product layer than a clever script bundle.
