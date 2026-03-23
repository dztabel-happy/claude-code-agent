#!/bin/bash
# Claude Code Notification Hook — only handles managed sessions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/hook_common.sh"

LOG_FILE="$(hook_prepare_log_file notification)"
INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // "unknown"')
NTYPE=$(printf '%s' "$INPUT" | jq -r '.notification_type // "unknown"')
MESSAGE=$(printf '%s' "$INPUT" | jq -r '.message // ""')
TITLE=$(printf '%s' "$INPUT" | jq -r '.title // ""')

hook_log "$LOG_FILE" "Notification hook fired: type=$NTYPE, session=$SESSION_ID"

SESSION_KEY="$(hook_managed_session_key)" || {
    hook_log "$LOG_FILE" "Ignoring unmanaged notification hook"
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
NOW="$(session_store_now_iso)"

session_store_merge "$SESSION_KEY" "$(jq -n \
    --arg claude_session_id "$SESSION_ID" \
    --arg last_event "notification:$NTYPE" \
    --arg last_activity_at "$NOW" \
    --arg last_message "$MESSAGE" \
    --arg last_title "$TITLE" \
    --arg last_notification_type "$NTYPE" \
    '{
        claude_session_id: $claude_session_id,
        last_event: $last_event,
        last_activity_at: $last_activity_at,
        last_message: $last_message,
        last_title: $last_title,
        last_notification_type: $last_notification_type
    }')" >/dev/null

case "$NTYPE" in
    permission_prompt)
        IMPORTANCE="important"
        MSG="⏸️ Claude Code 等待审批
🏷️ $PROJECT_LABEL
📋 $MESSAGE
🔧 session: $SESSION_ID
📁 $CWD"
        AGENT_MSG="[Claude Code Notification] 托管会话需要审批。
session_key: $SESSION_KEY
project: $PROJECT_LABEL
tmux_session: ${TMUX_SESSION:-none}
cwd: $CWD
claude_session_id: $SESSION_ID
message: $MESSAGE
请在对应 tmux 会话里处理审批。"
        ;;

    idle_prompt)
        IMPORTANCE="routine"
        MSG="💤 Claude Code 等待输入
🏷️ $PROJECT_LABEL
📁 $CWD
🔧 session: $SESSION_ID"
        AGENT_MSG="[Claude Code Notification] 托管会话正在等待输入。
session_key: $SESSION_KEY
project: $PROJECT_LABEL
tmux_session: ${TMUX_SESSION:-none}
cwd: $CWD
claude_session_id: $SESSION_ID
请决定下一步操作。"
        ;;

    *)
        hook_log "$LOG_FILE" "Unhandled notification type: $NTYPE"
        exit 0
        ;;
esac

if hook_should_notify_user "$NOTIFY_MODE" "$IMPORTANCE" "$ATTACHED_CLIENTS"; then
    hook_send_user_message "$LOG_FILE" "$CHANNEL" "$CHAT_ID" "$MSG" || true
else
    hook_log "$LOG_FILE" "User notify suppressed ($NTYPE, mode=$NOTIFY_MODE, attached=$ATTACHED_CLIENTS)"
fi

hook_wake_openclaw "$LOG_FILE" "$SESSION_KEY" "$CONTROLLER" "$AGENT_NAME" "$CHANNEL" "$AGENT_MSG" || true

exit 0
