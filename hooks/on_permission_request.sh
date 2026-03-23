#!/bin/bash
# Claude Code PermissionRequest Hook — only handles managed sessions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/hook_common.sh"

LOG_FILE="$(hook_prepare_log_file permission)"
INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // "unknown"')
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // "unknown"')
PERMISSION_MODE_INPUT=$(printf '%s' "$INPUT" | jq -r '.permission_mode // ""')
COMMAND_RAW=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
DESCRIPTION=$(printf '%s' "$INPUT" | jq -r '.tool_input.description // ""')

permission_normalize_text() {
    local value="${1-}"

    printf '%s' "$value" | tr '\r\n' '  ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

permission_lower() {
    local value="${1-}"
    printf '%s' "$value" | tr '[:upper:]' '[:lower:]'
}

permission_is_bash_safe() {
    local command_lower="${1:-}"

    [ -n "$command_lower" ] || return 1

    case "$command_lower" in
        *'|'*|*';'*|*'&&'*|*'||'*|*'>'*|*'<'*|*'$('*|*'`'*)
            return 1
            ;;
    esac

    case "$command_lower" in
        pwd|ls|ls\ *|tree|tree\ *|find\ *|rg|rg\ *|grep\ *|git\ status|git\ status\ *|git\ diff|git\ diff\ *|git\ log|git\ log\ *|git\ show|git\ show\ *|git\ branch|git\ branch\ *|git\ rev-parse\ *|git\ ls-files|git\ ls-files\ *|git\ remote|git\ remote\ *|git\ grep\ *|cat\ *|head\ *|tail\ *|wc\ *|sed\ -n\ *|sort\ *|uniq\ *|cut\ *|basename\ *|dirname\ *|realpath\ *|which\ *|env|env\ *|printenv|printenv\ *|stat\ *|du\ -sh\ *|npm\ test|npm\ test\ *|npm\ run\ test|npm\ run\ test\ *|npm\ run\ lint|npm\ run\ lint\ *|npm\ run\ check|npm\ run\ check\ *|pnpm\ test|pnpm\ test\ *|pnpm\ lint|pnpm\ lint\ *|pnpm\ check|pnpm\ check\ *|pnpm\ exec\ eslint\ *|pnpm\ exec\ vitest\ *|yarn\ test|yarn\ test\ *|yarn\ lint|yarn\ lint\ *|bun\ test|bun\ test\ *|pytest|pytest\ *|python\ -m\ pytest|python\ -m\ pytest\ *|uv\ run\ pytest|uv\ run\ pytest\ *|vitest|vitest\ *|jest|jest\ *|go\ test|go\ test\ *|cargo\ test|cargo\ test\ *|cargo\ check|cargo\ check\ *|cargo\ fmt\ --check|cargo\ fmt\ --check\ *|ruff\ check|ruff\ check\ *|mypy|mypy\ *|tsc\ --noemit|tsc\ --noemit\ *|make\ test|make\ test\ *|make\ lint|make\ lint\ *|make\ check|make\ check\ *)
            return 0
            ;;
    esac

    return 1
}

permission_is_bash_dangerous() {
    local command_lower="${1:-}"

    [ -n "$command_lower" ] || return 1

    [[ "$command_lower" =~ (^|[[:space:];|&])sudo([[:space:]]|$) ]] && return 0
    [[ "$command_lower" =~ (^|[[:space:];|&])rm([[:space:]]+-[[:alnum:]-]*r[[:alnum:]-]*f|[[:space:]]+-[[:alnum:]-]*f[[:alnum:]-]*r)([[:space:]]|$) ]] && return 0
    [[ "$command_lower" =~ (^|[[:space:];|&])git[[:space:]]+reset[[:space:]]+--hard([[:space:]]|$) ]] && return 0
    [[ "$command_lower" =~ (^|[[:space:];|&])git[[:space:]]+clean([[:space:]]|$) ]] && return 0
    [[ "$command_lower" =~ (curl|wget)[^|]*\|[[:space:]]*(sh|bash|zsh|fish)([[:space:]]|$) ]] && return 0
    [[ "$command_lower" =~ (^|[[:space:];|&])dd([[:space:]]|$) ]] && return 0
    [[ "$command_lower" =~ (^|[[:space:];|&])mkfs([[:space:]]|$) ]] && return 0
    [[ "$command_lower" =~ (^|[[:space:];|&])(shutdown|reboot|poweroff|halt)([[:space:]]|$) ]] && return 0
    [[ "$command_lower" =~ (^|[[:space:];|&])npm[[:space:]]+(install|i)[[:space:]].*-g([[:space:]]|$) ]] && return 0
    [[ "$command_lower" =~ (^|[[:space:];|&])pnpm[[:space:]]+(add|install)[[:space:]].*-g([[:space:]]|$) ]] && return 0
    [[ "$command_lower" =~ (^|[[:space:];|&])yarn[[:space:]]+global[[:space:]]+add([[:space:]]|$) ]] && return 0

    return 1
}

permission_emit_allow() {
    local command="${1:?command required}"

    jq -n \
        --arg command "$command" \
        '{
            hookSpecificOutput: {
                hookEventName: "PermissionRequest",
                decision: {
                    behavior: "allow",
                    updatedPermissions: [
                        {
                            type: "addRules",
                            behavior: "allow",
                            destination: "session",
                            rules: [
                                {
                                    toolName: "Bash",
                                    ruleContent: $command
                                }
                            ]
                        }
                    ]
                }
            }
        }'
}

permission_emit_deny() {
    local message="${1:?message required}"
    local interrupt="${2:-false}"

    jq -n \
        --arg message "$message" \
        --arg interrupt "$interrupt" \
        '{
            hookSpecificOutput: {
                hookEventName: "PermissionRequest",
                decision: {
                    behavior: "deny",
                    message: $message,
                    interrupt: ($interrupt == "true")
                }
            }
        }'
}

SESSION_KEY="$(hook_managed_session_key)" || {
    hook_log "$LOG_FILE" "Ignoring unmanaged permission hook"
    exit 0
}

SESSION_JSON="$(hook_load_session_json "$SESSION_KEY")"
CONTROLLER="$(printf '%s' "$SESSION_JSON" | jq -r '.controller // "local"')"
NOTIFY_MODE="$(printf '%s' "$SESSION_JSON" | jq -r '.notify_mode // "off"')"
ATTACHED_CLIENTS="$(printf '%s' "$SESSION_JSON" | jq -r '.attached_clients // 0')"
PROJECT_LABEL="$(printf '%s' "$SESSION_JSON" | jq -r '.project_label // .session_key')"
CHAT_ID="$(printf '%s' "$SESSION_JSON" | jq -r '.chat_id // ""')"
CHANNEL="$(printf '%s' "$SESSION_JSON" | jq -r '.channel // "telegram"')"
AGENT_NAME="$(printf '%s' "$SESSION_JSON" | jq -r '.agent_name // "main"')"
TMUX_SESSION="$(printf '%s' "$SESSION_JSON" | jq -r '.tmux_session // ""')"
PERMISSION_POLICY="$(printf '%s' "$SESSION_JSON" | jq -r '.permission_policy // ""')"

if [ -z "$PERMISSION_POLICY" ] || [ "$PERMISSION_POLICY" = "null" ]; then
    if [ "$CONTROLLER" = "openclaw" ]; then
        PERMISSION_POLICY="safe"
    else
        PERMISSION_POLICY="off"
    fi
fi

COMMAND="$(permission_normalize_text "$COMMAND_RAW")"
COMMAND_LOWER="$(permission_lower "$COMMAND")"
REQUEST_PREVIEW="$COMMAND"
if [ -z "$REQUEST_PREVIEW" ]; then
    REQUEST_PREVIEW="$(permission_normalize_text "$DESCRIPTION")"
fi
if [ -z "$REQUEST_PREVIEW" ]; then
    REQUEST_PREVIEW="$(printf '%s' "$INPUT" | jq -c '.tool_input // {}')"
fi
REQUEST_PREVIEW="${REQUEST_PREVIEW:0:1000}"
NOW="$(session_store_now_iso)"

hook_log "$LOG_FILE" "PermissionRequest hook fired: tool=$TOOL_NAME, policy=$PERMISSION_POLICY, session=$SESSION_ID"
hook_log "$LOG_FILE" "Request preview: ${REQUEST_PREVIEW:0:300}"

session_store_merge "$SESSION_KEY" "$(jq -n \
    --arg claude_session_id "$SESSION_ID" \
    --arg permission_mode "$PERMISSION_MODE_INPUT" \
    --arg permission_policy "$PERMISSION_POLICY" \
    --arg last_event "permission_request:pending" \
    --arg last_activity_at "$NOW" \
    --arg last_summary "$TOOL_NAME" \
    --arg last_message "$REQUEST_PREVIEW" \
    --arg last_notification_type "permission_request" \
    --arg last_permission_tool "$TOOL_NAME" \
    --arg last_permission_preview "$REQUEST_PREVIEW" \
    --arg last_permission_decision "pending" \
    '{
        claude_session_id: $claude_session_id,
        permission_mode: $permission_mode,
        permission_policy: $permission_policy,
        last_event: $last_event,
        last_activity_at: $last_activity_at,
        last_summary: $last_summary,
        last_message: $last_message,
        last_notification_type: $last_notification_type,
        last_permission_tool: $last_permission_tool,
        last_permission_preview: $last_permission_preview,
        last_permission_decision: $last_permission_decision
    }')" >/dev/null

if [ "$PERMISSION_POLICY" = "off" ]; then
    hook_log "$LOG_FILE" "PermissionRequest left to Claude prompt (policy=off)"
    exit 0
fi

if [ "$TOOL_NAME" != "Bash" ]; then
    hook_log "$LOG_FILE" "PermissionRequest passthrough for unsupported tool: $TOOL_NAME"
    exit 0
fi

if permission_is_bash_dangerous "$COMMAND_LOWER"; then
    DENY_MESSAGE="Denied by claude-code-agent $PERMISSION_POLICY policy: potentially destructive Bash command. Use a safer alternative or wait for explicit operator approval."
    hook_log "$LOG_FILE" "PermissionRequest auto-denied: ${COMMAND:0:200}"

    session_store_merge "$SESSION_KEY" "$(jq -n \
        --arg last_event "permission_request:auto_deny" \
        --arg last_activity_at "$(session_store_now_iso)" \
        --arg last_message "$DENY_MESSAGE" \
        --arg last_permission_decision "auto_deny" \
        --arg last_permission_message "$DENY_MESSAGE" \
        '{
            last_event: $last_event,
            last_activity_at: $last_activity_at,
            last_message: $last_message,
            last_permission_decision: $last_permission_decision,
            last_permission_message: $last_permission_message
        }')" >/dev/null

    MSG="⛔ Claude Code 自动拒绝了高风险命令
🏷️ $PROJECT_LABEL
📁 $CWD
🧪 ${COMMAND:0:240}"
    AGENT_MSG="[Claude Code PermissionRequest] 已自动拒绝高风险命令，请决定是否改写策略或换更安全的实现。
session_key: $SESSION_KEY
project: $PROJECT_LABEL
tmux_session: ${TMUX_SESSION:-none}
cwd: $CWD
claude_session_id: $SESSION_ID
tool: $TOOL_NAME
command: ${COMMAND:0:600}
policy: $PERMISSION_POLICY
reason: $DENY_MESSAGE"

    if hook_should_notify_user "$NOTIFY_MODE" "important" "$ATTACHED_CLIENTS"; then
        hook_send_user_message "$LOG_FILE" "$CHANNEL" "$CHAT_ID" "$MSG" || true
    else
        hook_log "$LOG_FILE" "User notify suppressed (auto deny, mode=$NOTIFY_MODE, attached=$ATTACHED_CLIENTS)"
    fi

    hook_wake_openclaw "$LOG_FILE" "$SESSION_KEY" "$CONTROLLER" "$AGENT_NAME" "$CHANNEL" "$AGENT_MSG" || true
    permission_emit_deny "$DENY_MESSAGE" "false"
    exit 0
fi

if [ "$PERMISSION_POLICY" = "safe" ] && permission_is_bash_safe "$COMMAND_LOWER"; then
    hook_log "$LOG_FILE" "PermissionRequest auto-allowed: ${COMMAND:0:200}"

    session_store_merge "$SESSION_KEY" "$(jq -n \
        --arg last_event "permission_request:auto_allow" \
        --arg last_activity_at "$(session_store_now_iso)" \
        --arg last_message "$REQUEST_PREVIEW" \
        --arg last_permission_decision "auto_allow" \
        --arg last_permission_message "Allowed by safe policy" \
        '{
            last_event: $last_event,
            last_activity_at: $last_activity_at,
            last_message: $last_message,
            last_permission_decision: $last_permission_decision,
            last_permission_message: $last_permission_message
        }')" >/dev/null

    permission_emit_allow "$COMMAND"
    exit 0
fi

hook_log "$LOG_FILE" "PermissionRequest left to Claude prompt (no policy match)"
exit 0
