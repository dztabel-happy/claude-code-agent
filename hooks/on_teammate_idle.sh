#!/bin/bash
# Claude Code TeammateIdle Hook — only handles managed sessions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/hook_common.sh"

LOG_FILE="$(hook_prepare_log_file teammate)"
INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // "unknown"')
TEAMMATE=$(printf '%s' "$INPUT" | jq -r '.teammate_name // "unknown"')
TEAM=$(printf '%s' "$INPUT" | jq -r '.team_name // "unknown"')

hook_log "$LOG_FILE" "TeammateIdle hook fired: teammate=$TEAMMATE, team=$TEAM"

SESSION_KEY="$(hook_managed_session_key)" || {
    hook_log "$LOG_FILE" "Ignoring unmanaged teammate hook"
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

session_store_merge "$SESSION_KEY" "$(jq -n \
    --arg claude_session_id "$SESSION_ID" \
    --arg last_event "teammate_idle" \
    --arg last_activity_at "$(session_store_now_iso)" \
    --arg last_summary "$TEAMMATE" \
    --arg last_message "$TEAM" \
    '{
        claude_session_id: $claude_session_id,
        last_event: $last_event,
        last_activity_at: $last_activity_at,
        last_summary: $last_summary,
        last_message: $last_message
    }')" >/dev/null

MSG="👤 Teammate 完成工作
🏷️ $PROJECT_LABEL
👥 Team: $TEAM
👤 Teammate: $TEAMMATE
📁 $CWD"

AGENT_MSG="[Claude Code Hook] Teammate 即将空闲，请检查是否还需要继续推进。
session_key: $SESSION_KEY
project: $PROJECT_LABEL
tmux_session: ${TMUX_SESSION:-none}
team: $TEAM
teammate: $TEAMMATE
cwd: $CWD
claude_session_id: $SESSION_ID"

if hook_should_notify_user "$NOTIFY_MODE" "routine" "$ATTACHED_CLIENTS"; then
    hook_send_user_message "$LOG_FILE" "$CHANNEL" "$CHAT_ID" "$MSG" || true
else
    hook_log "$LOG_FILE" "User notify suppressed (teammate idle, mode=$NOTIFY_MODE, attached=$ATTACHED_CLIENTS)"
fi

hook_wake_openclaw "$LOG_FILE" "$SESSION_KEY" "$CONTROLLER" "$AGENT_NAME" "$CHANNEL" "$AGENT_MSG" || true

exit 0
