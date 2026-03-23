# Changelog

## [Unreleased]

### Added
- `PermissionRequest` hook for managed Claude sessions, with session-scoped auto-allow for a narrow safe Bash allowlist

### Changed
- OpenClaw takeover now enables `permission_policy=safe` by default for managed sessions
- Local reclaim now turns managed approval automation back off

### Fixed
- Reduced the approval-chain friction where Claude still had to wait for tmux-side human handling on common safe shell reads/tests
- Auto-denied obviously dangerous Bash requests before they fall through to manual tmux approval

## [0.2.0] - 2026-03-23

This release turns `claude-code-agent` from a tmux-and-hooks prototype into a cleaner managed runtime layer with explicit OpenClaw session routing and session-scoped Claude settings injection.

### Added
- Explicit OpenClaw session routing per managed Claude session via deterministic `openclaw session-id`
- Managed Claude settings overlay generation in runtime state directory
- Regression coverage for explicit `--session-id` wake routing
- Regression coverage for managed `--settings` injection
- Session status output for `oc_session` and managed settings path

### Changed
- `start_claude.sh` and `run_claude.sh` now inject hooks through `--settings` instead of assuming global Claude settings were manually edited
- Managed sessions now carry `openclaw_session_id` metadata
- Install flow now treats global `~/.claude/settings.json` hook edits as optional, not mandatory
- Install flow no longer treats OpenClaw session reset changes as a hard prerequisite
- Knowledge base refreshed to Claude Code `2.1.80` local baseline and `2.1.81` npm latest at check time
- Documentation now uses `{baseDir}` in skill instructions instead of placeholder `<skill_dir>`

### Fixed
- Removed the architecture risk where multiple Claude-managed projects could wake the same OpenClaw agent conversation
- Reduced coupling between managed sessions and user-global Claude configuration
- Updated stale Claude Code capability assumptions, including permission modes and newer CLI flags

## [0.1.0] - 2026-03-06

### Added
- Initial release of `claude-code-agent`
- Managed tmux wrappers for Claude Code
- Claude native hooks integration
- Session metadata registry
- Agent Teams hooks and quality gate support
- Knowledge base and usage docs
