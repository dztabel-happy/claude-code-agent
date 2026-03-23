#!/bin/bash
# Claude Code Stop Hook — only handles managed sessions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/hook_common.sh"

LOG_FILE="$(hook_prepare_log_file stop)"
INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // "unknown"')
LAST_MSG=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // "Turn Complete!"')
STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')

hook_log "$LOG_FILE" "Stop hook fired: session=$SESSION_ID, cwd=$CWD"
hook_log "$LOG_FILE" "Summary: ${LAST_MSG:0:200}"

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    hook_log "$LOG_FILE" "stop_hook_active=true, skipping notification to avoid loop"
    exit 0
fi

SESSION_KEY="$(hook_managed_session_key)" || {
    hook_log "$LOG_FILE" "Ignoring unmanaged stop hook"
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
SUMMARY="${LAST_MSG:0:1000}"
NOW="$(session_store_now_iso)"

session_store_merge "$SESSION_KEY" "$(jq -n \
    --arg claude_session_id "$SESSION_ID" \
    --arg last_event "stop" \
    --arg last_activity_at "$NOW" \
    --arg last_summary "$SUMMARY" \
    --arg last_message "$LAST_MSG" \
    '{
        claude_session_id: $claude_session_id,
        last_event: $last_event,
        last_activity_at: $last_activity_at,
        last_summary: $last_summary,
        last_message: $last_message
    }')" >/dev/null

MSG="🔔 Claude Code 任务回复
🏷️ $PROJECT_LABEL
📁 $CWD
💬 $SUMMARY"

AGENT_MSG="[Claude Code Hook] 托管会话有新回复，请检查输出并继续推进。
session_key: $SESSION_KEY
project: $PROJECT_LABEL
tmux_session: ${TMUX_SESSION:-none}
cwd: $CWD
claude_session_id: $SESSION_ID
summary: $SUMMARY"

if hook_should_notify_user "$NOTIFY_MODE" "routine" "$ATTACHED_CLIENTS"; then
    hook_send_user_message "$LOG_FILE" "$CHANNEL" "$CHAT_ID" "$MSG" || true
else
    hook_log "$LOG_FILE" "User notify suppressed (mode=$NOTIFY_MODE, attached=$ATTACHED_CLIENTS)"
fi

hook_wake_openclaw "$LOG_FILE" "$SESSION_KEY" "$CONTROLLER" "$AGENT_NAME" "$CHANNEL" "$AGENT_MSG" || true

exit 0
