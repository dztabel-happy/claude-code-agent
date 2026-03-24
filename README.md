# Claude Code Agent

**English** | [中文](README_ZH.md)

`claude-code-agent` is an OpenClaw skill for running Claude Code as a managed, resumable worker.

This skill is not mainly about wrapping a Claude command. Its real value is that OpenClaw can treat Claude Code like a long-running project session: start it, leave it running in `tmux`, come back later, read progress, make decisions, and keep going.

## Core Value

- OpenClaw can start a new Claude Code session or resume an existing one
- the working session stays alive in `tmux`, so the live state is still there when you come back
- runtime metadata keeps track of the same managed session
- Claude hooks wake OpenClaw on `Notification`, `PermissionRequest`, `Stop`, and similar events
- when OpenClaw takes over again, it can read recent `tmux` output first and continue the same session
- you can leave the computer and still control the workflow remotely through OpenClaw
- OpenClaw does not need to stay attached all the time; it behaves more like a project manager returning when events or messages require action
- when you are at the keyboard, you can formally return the session to local control so OpenClaw stops receiving later notifications for that session
- when you leave again, you can ask OpenClaw to take over and it will read the previous context and `tmux` scene before continuing

## What This Skill Is

- OpenClaw is the project manager
- Claude Code is the executor
- this repository is the session, routing, and wakeup layer between them

This is not meant to be a terminal-first experience. The normal user entry point is OpenClaw conversation.

## How You Actually Use It

### Start a task

Talk to OpenClaw:

```text
Use claude-code-agent to analyze /path/to/project.
Use claude-code-agent to fix a bug in /path/to/project, run tests, and report back.
Use claude-code-agent to review the current changes in /path/to/project.
Use claude-code-agent to do a read-only audit of /path/to/project.
```

Expected flow:

1. OpenClaw selects this skill.
2. OpenClaw starts or reuses a managed Claude Code session.
3. Claude Code keeps working inside that same session.
4. OpenClaw comes back when hooks or messages require attention.

### Come back in the middle

You can return at any time and ask OpenClaw:

```text
Use claude-code-agent to check progress for /path/to/project.
Use claude-code-agent to continue the previous session.
Use claude-code-agent to summarize the current state first.
Use claude-code-agent to list the current managed Claude sessions.
```

The key point is not "start another Claude". The key point is "continue the same session".

Session state is stored in runtime metadata, and the live scene stays in `tmux`, so OpenClaw can read the scene and continue.

### Leave the computer

This is one of the main reasons the skill exists.

Typical pattern:

1. You ask OpenClaw to start work.
2. Claude Code keeps running in `tmux`.
3. You leave the computer.
4. If Claude needs approval, input, or reports completion, OpenClaw receives the event.
5. OpenClaw decides what to do next and keeps you informed.

OpenClaw does not need to sit in front of the terminal all the time. It is event-driven, like a project manager returning when needed.

### Work locally, then hand it back later

This is another key workflow:

1. While you are at the computer, ask OpenClaw to return the session to local control.
2. From that point on, you operate the session yourself in the terminal.
3. Because ownership is local again, OpenClaw stops receiving later notifications for that session.
4. When you leave the computer, message OpenClaw and ask it to take over again.
5. OpenClaw will read the existing context, stored session state, and recent `tmux` output before continuing the same session.

So you can move back and forth between local hands-on control and remote OpenClaw supervision without throwing away the session.

## How It Works

The flow is simple:

1. OpenClaw starts Claude Code through this skill.
2. Claude Code runs inside `tmux`.
3. Runtime state stores identifiers such as `session_key`, `cwd`, `openclaw_session_id`, and permission policy.
4. Hooks wake OpenClaw on important events.
5. OpenClaw reads session state and recent `tmux` output, then decides whether to continue, report, ask for confirmation, or hand control back.

## Quick Start

### 1. Prerequisites

- OpenClaw installed
- Claude Code installed and authenticated
- `tmux`
- `jq`

### 2. Install the skill where OpenClaw can discover it

Latest OpenClaw docs describe this discovery order:

1. `<workspace>/skills`
2. `~/.openclaw/skills`
3. bundled OpenClaw skills

Recommended install:

Workspace-local:

```bash
git clone https://github.com/dztabel-happy/claude-code-agent.git ~/.openclaw/workspace/skills/claude-code-agent
```

Shared:

```bash
git clone https://github.com/dztabel-happy/claude-code-agent.git ~/.openclaw/skills/claude-code-agent
```

If your workspace is not `~/.openclaw/workspace`, use `<your-workspace>/skills/claude-code-agent`.

### 3. Run OpenClaw onboarding if needed

```bash
openclaw onboard
```

Official docs describe this as the main onboarding flow for gateway, workspace, and skills.

### 4. Start a new OpenClaw conversation and use the skill

```text
Use claude-code-agent to analyze /path/to/project.
```

That is the main path. Not manual wrapper-first usage.

## How OpenClaw Installs This Skill

Two things matter here.

### Official OpenClaw direction

The latest OpenClaw docs describe:

- `openclaw onboard` as the recommended setup entrypoint
- an OpenClaw skills discovery and install system
- automatic discovery from workspace and shared skills directories

### Most reliable path for this repository today

For this GitHub repo, the most reliable path is still:

1. clone or copy it into `<workspace>/skills/claude-code-agent` or `~/.openclaw/skills/claude-code-agent`
2. start a new OpenClaw conversation
3. ask OpenClaw to use `claude-code-agent`

Do not assume OpenClaw can fetch this GitHub repository directly by skill name alone unless your current build and registry setup explicitly support that path.

## When You Want To Step In Yourself

Day to day, it is better to ask OpenClaw:

```text
Use claude-code-agent to hand the current session back to local control.
Use claude-code-agent to resume the Claude session for /path/to/project.
Use claude-code-agent to stop the claude-demo session.
```

If you are already at the keyboard, the local fallback tools are:

Inspect a live session without changing ownership:

```bash
tmux attach -t <session-name>
```

Formally control an existing managed session:

```bash
bash runtime/control_session.sh list
bash runtime/control_session.sh status
bash runtime/control_session.sh reclaim [selector]
bash runtime/control_session.sh takeover [selector]
bash runtime/control_session.sh stop [selector]
```

Simple rule:

- `tmux attach` = inspect or temporarily intervene
- `reclaim` = formally switch back to local control, and later notifications stop going to OpenClaw
- `takeover` = formally hand the session back to OpenClaw, which reads prior context and recent `tmux` output before continuing

## Why This Design Matters

Without this layer, OpenClaw is closer to "calling Claude Code once".

With this layer, OpenClaw can manage a real project session:

- the session survives
- the live scene is readable
- work can be resumed
- the user can leave the computer
- OpenClaw does not need to stay resident in the foreground
- the user can stay informed while OpenClaw keeps managing execution

That is the real core of this skill.

## Official References

- [OpenClaw Skills CLI docs](https://docs.openclaw.ai/cli/skills)
- [OpenClaw Skills guide](https://docs.openclaw.ai/tools/skills)
- [OpenClaw Onboarding CLI docs](https://docs.openclaw.ai/cli/onboard)
- [OpenClaw onboarding overview](https://docs.openclaw.ai/start/onboarding-overview)
