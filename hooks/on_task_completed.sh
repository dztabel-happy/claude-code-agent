#!/bin/bash
# Claude Code TaskCompleted Hook — only handles managed sessions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/hook_common.sh"

LOG_FILE="$(hook_prepare_log_file task)"
INPUT=$(cat)
QUALITY_GATE_SCRIPT=""
QUALITY_GATE_LABEL=""
QUALITY_GATE_OUTPUT=""

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // "unknown"')
TASK_ID=$(printf '%s' "$INPUT" | jq -r '.task_id // "unknown"')
TASK_SUBJECT=$(printf '%s' "$INPUT" | jq -r '.task_subject // "unknown"')
TEAMMATE=$(printf '%s' "$INPUT" | jq -r '.teammate_name // "unknown"')
TEAM=$(printf '%s' "$INPUT" | jq -r '.team_name // "unknown"')

hook_log "$LOG_FILE" "TaskCompleted hook fired: task=$TASK_ID, subject=$TASK_SUBJECT, teammate=$TEAMMATE"

SESSION_KEY="$(hook_managed_session_key)" || {
    hook_log "$LOG_FILE" "Ignoring unmanaged task hook"
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
SESSION_CWD="$(printf '%s' "$SESSION_JSON" | jq -r '.cwd // ""')"

resolve_task_completed_gate() {
    local configured_gate="${OPENCLAW_TASK_COMPLETED_GATE:-}"

    if [ -n "$configured_gate" ]; then
        QUALITY_GATE_SCRIPT="$configured_gate"
        if [ -n "$SESSION_CWD" ] && [ "${QUALITY_GATE_SCRIPT#/}" = "$QUALITY_GATE_SCRIPT" ]; then
            QUALITY_GATE_SCRIPT="$SESSION_CWD/$QUALITY_GATE_SCRIPT"
        fi
        QUALITY_GATE_LABEL="$QUALITY_GATE_SCRIPT"
        return 0
    fi

    return 1
}

run_task_completed_gate() {
    local rc

    if ! resolve_task_completed_gate; then
        return 0
    fi

    if [ ! -x "$QUALITY_GATE_SCRIPT" ]; then
        QUALITY_GATE_OUTPUT="TaskCompleted quality gate is not executable: $QUALITY_GATE_LABEL"
        hook_log "$LOG_FILE" "$QUALITY_GATE_OUTPUT"
        return 2
    fi

    hook_log "$LOG_FILE" "TaskCompleted quality gate running: $QUALITY_GATE_LABEL"

    set +e
    if [ -n "$SESSION_CWD" ] && [ -d "$SESSION_CWD" ]; then
        QUALITY_GATE_OUTPUT="$(
            cd "$SESSION_CWD" &&
            printf '%s' "$INPUT" | env \
                OPENCLAW_SESSION_KEY="$SESSION_KEY" \
                OPENCLAW_PROJECT_LABEL="$PROJECT_LABEL" \
                OPENCLAW_CLAUDE_SESSION_ID="$SESSION_ID" \
                OPENCLAW_CLAUDE_WORKDIR="$SESSION_CWD" \
                OPENCLAW_TEAM_NAME="$TEAM" \
                OPENCLAW_TEAMMATE_NAME="$TEAMMATE" \
                OPENCLAW_TASK_ID="$TASK_ID" \
                OPENCLAW_TASK_SUBJECT="$TASK_SUBJECT" \
                "$QUALITY_GATE_SCRIPT" 2>&1
        )"
        rc=$?
    else
        QUALITY_GATE_OUTPUT="$(
            printf '%s' "$INPUT" | env \
                OPENCLAW_SESSION_KEY="$SESSION_KEY" \
                OPENCLAW_PROJECT_LABEL="$PROJECT_LABEL" \
                OPENCLAW_CLAUDE_SESSION_ID="$SESSION_ID" \
                OPENCLAW_CLAUDE_WORKDIR="$SESSION_CWD" \
                OPENCLAW_TEAM_NAME="$TEAM" \
                OPENCLAW_TEAMMATE_NAME="$TEAMMATE" \
                OPENCLAW_TASK_ID="$TASK_ID" \
                OPENCLAW_TASK_SUBJECT="$TASK_SUBJECT" \
                "$QUALITY_GATE_SCRIPT" 2>&1
        )"
        rc=$?
    fi
    set -e

    if [ "$rc" -eq 0 ]; then
        hook_log "$LOG_FILE" "TaskCompleted quality gate passed: $QUALITY_GATE_LABEL"
        if [ -n "$QUALITY_GATE_OUTPUT" ]; then
            hook_log "$LOG_FILE" "Gate output: ${QUALITY_GATE_OUTPUT:0:300}"
        fi
        return 0
    fi

    if [ -z "$QUALITY_GATE_OUTPUT" ]; then
        QUALITY_GATE_OUTPUT="TaskCompleted blocked by quality gate: $QUALITY_GATE_LABEL"
    fi
    hook_log "$LOG_FILE" "TaskCompleted quality gate blocked (exit=$rc): ${QUALITY_GATE_OUTPUT:0:300}"
    return 2
}

if run_task_completed_gate; then
    LAST_EVENT="task_completed"
    LAST_MESSAGE="$TASK_ID"
    USER_IMPORTANCE="routine"
    MSG="✅ 任务完成
🏷️ $PROJECT_LABEL
📋 $TASK_SUBJECT
👤 Teammate: $TEAMMATE
👥 Team: $TEAM
📁 $CWD"
    AGENT_MSG="[Claude Code Hook] Team task completed，请检查质量并决定是否继续。
session_key: $SESSION_KEY
project: $PROJECT_LABEL
tmux_session: ${TMUX_SESSION:-none}
task_id: $TASK_ID
task: $TASK_SUBJECT
teammate: $TEAMMATE
team: $TEAM
cwd: $CWD
claude_session_id: $SESSION_ID"
else
    LAST_EVENT="task_completed_blocked"
    LAST_MESSAGE="${QUALITY_GATE_OUTPUT:0:1000}"
    USER_IMPORTANCE="important"
    MSG="⛔ 任务被质量门禁拦截
🏷️ $PROJECT_LABEL
📋 $TASK_SUBJECT
👤 Teammate: $TEAMMATE
👥 Team: $TEAM
📁 $CWD
🧪 ${QUALITY_GATE_OUTPUT:0:400}"
    AGENT_MSG="[Claude Code Hook] Team task blocked by quality gate，请修复后再继续。
session_key: $SESSION_KEY
project: $PROJECT_LABEL
tmux_session: ${TMUX_SESSION:-none}
task_id: $TASK_ID
task: $TASK_SUBJECT
teammate: $TEAMMATE
team: $TEAM
cwd: $CWD
claude_session_id: $SESSION_ID
gate: ${QUALITY_GATE_LABEL:-none}
reason: ${QUALITY_GATE_OUTPUT:0:600}"
fi

session_store_merge "$SESSION_KEY" "$(jq -n \
    --arg claude_session_id "$SESSION_ID" \
    --arg last_event "$LAST_EVENT" \
    --arg last_activity_at "$(session_store_now_iso)" \
    --arg last_summary "$TASK_SUBJECT" \
    --arg last_message "$LAST_MESSAGE" \
    '{
        claude_session_id: $claude_session_id,
        last_event: $last_event,
        last_activity_at: $last_activity_at,
        last_summary: $last_summary,
        last_message: $last_message
    }')" >/dev/null

if hook_should_notify_user "$NOTIFY_MODE" "$USER_IMPORTANCE" "$ATTACHED_CLIENTS"; then
    hook_send_user_message "$LOG_FILE" "$CHANNEL" "$CHAT_ID" "$MSG" || true
else
    hook_log "$LOG_FILE" "User notify suppressed (task completed, mode=$NOTIFY_MODE, importance=$USER_IMPORTANCE, attached=$ATTACHED_CLIENTS)"
fi

hook_wake_openclaw "$LOG_FILE" "$SESSION_KEY" "$CONTROLLER" "$AGENT_NAME" "$CHANNEL" "$AGENT_MSG" || true

if [ "$LAST_EVENT" = "task_completed_blocked" ]; then
    printf '%s\n' "$QUALITY_GATE_OUTPUT" >&2
    exit 2
fi

exit 0
