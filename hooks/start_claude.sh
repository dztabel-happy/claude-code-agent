#!/bin/bash
# Claude Code managed starter.
# Usage: ./start_claude.sh <session-name> <workdir> [claude args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../runtime/session_store.sh"

SESSION="${1:?Usage: $0 <session-name> <workdir> [claude args...]}"
WORKDIR="${2:?Usage: $0 <session-name> <workdir> [claude args...]}"
shift 2
CLAUDE_ARGS=("$@")
CUSTOM_SETTINGS=""
FILTERED_CLAUDE_ARGS=()

if ! command -v tmux >/dev/null 2>&1; then
    echo "❌ tmux not found"
    exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
    echo "❌ claude not found. Install: npm install -g @anthropic-ai/claude-code"
    exit 1
fi
CLAUDE_BIN="$(command -v claude)"

if [ ! -d "$WORKDIR" ]; then
    echo "❌ Directory not found: $WORKDIR"
    exit 1
fi

if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "❌ tmux session already exists: $SESSION"
    echo "   Use a different session name or stop the existing one first."
    exit 1
fi

PROJECT_LABEL="${OPENCLAW_PROJECT_LABEL:-$(session_store_project_label_from_cwd "$WORKDIR")}"
SESSION_KEY="${OPENCLAW_SESSION_KEY:-$(session_store_slugify "$SESSION")}"
OPENCLAW_SESSION_ID="${OPENCLAW_OPENCLAW_SESSION_ID:-$(session_store_openclaw_session_id "$SESSION_KEY")}"
CONTROLLER="${OPENCLAW_CONTROLLER:-openclaw}"
NOTIFY_MODE="${OPENCLAW_NOTIFY_MODE:-attention}"
MANAGED_BY="${OPENCLAW_MANAGED_BY:-openclaw}"
PERMISSION_POLICY="${OPENCLAW_PERMISSION_POLICY:-}"
CHAT_ID="${OPENCLAW_AGENT_CHAT_ID:-${CLAUDE_AGENT_CHAT_ID:-}}"
CHANNEL="${OPENCLAW_AGENT_CHANNEL:-${CLAUDE_AGENT_CHANNEL:-telegram}}"
AGENT_NAME="${OPENCLAW_AGENT_NAME:-${CLAUDE_AGENT_NAME:-main}}"
STARTED_AT="$(session_store_now_iso)"

for ((i=0; i<${#CLAUDE_ARGS[@]}; i++)); do
    case "${CLAUDE_ARGS[i]}" in
        --settings)
            if (( i + 1 < ${#CLAUDE_ARGS[@]} )); then
                CUSTOM_SETTINGS="${CLAUDE_ARGS[i+1]}"
                i=$((i + 1))
            fi
            ;;
        --settings=*)
            CUSTOM_SETTINGS="${CLAUDE_ARGS[i]#--settings=}"
            ;;
        *)
            FILTERED_CLAUDE_ARGS+=("${CLAUDE_ARGS[i]}")
            ;;
    esac
done

CLAUDE_ARGS=("${FILTERED_CLAUDE_ARGS[@]}")
MANAGED_SETTINGS_PATH="$(session_store_write_combined_settings "$SESSION_KEY" "$SKILL_DIR" "$CUSTOM_SETTINGS" "$WORKDIR")" || {
    echo "❌ Failed to prepare managed Claude settings overlay"
    exit 1
}

case "$CONTROLLER" in
    local|openclaw) ;;
    *)
        echo "❌ Invalid OPENCLAW_CONTROLLER: $CONTROLLER"
        exit 1
        ;;
esac

case "$NOTIFY_MODE" in
    off|attention|live) ;;
    *)
        echo "❌ Invalid OPENCLAW_NOTIFY_MODE: $NOTIFY_MODE"
        exit 1
        ;;
esac

if [ -z "$PERMISSION_POLICY" ]; then
    if [ "$CONTROLLER" = "openclaw" ]; then
        PERMISSION_POLICY="safe"
    else
        PERMISSION_POLICY="off"
    fi
fi

case "$PERMISSION_POLICY" in
    off|deny-dangerous|safe) ;;
    *)
        echo "❌ Invalid OPENCLAW_PERMISSION_POLICY: $PERMISSION_POLICY"
        exit 1
        ;;
esac

MODE="default"
for ((i=0; i<${#CLAUDE_ARGS[@]}; i++)); do
    case "${CLAUDE_ARGS[i]}" in
        --dangerously-skip-permissions)
            MODE="bypassPermissions"
            ;;
        --permission-mode)
            if (( i + 1 < ${#CLAUDE_ARGS[@]} )); then
                MODE="${CLAUDE_ARGS[i+1]}"
            fi
            ;;
        --permission-mode=*)
            MODE="${CLAUDE_ARGS[i]#--permission-mode=}"
            ;;
    esac
done

METADATA_JSON=$(jq -n \
    --arg session_key "$SESSION_KEY" \
    --arg project_label "$PROJECT_LABEL" \
    --arg cwd "$WORKDIR" \
    --arg tmux_session "$SESSION" \
    --arg launch_mode "interactive" \
    --arg controller "$CONTROLLER" \
    --arg notify_mode "$NOTIFY_MODE" \
    --arg status "running" \
    --arg managed_by "$MANAGED_BY" \
    --arg started_at "$STARTED_AT" \
    --arg last_activity_at "$STARTED_AT" \
    --arg last_event "session_registered" \
    --arg chat_id "$CHAT_ID" \
    --arg channel "$CHANNEL" \
    --arg agent_name "$AGENT_NAME" \
    --arg openclaw_session_id "$OPENCLAW_SESSION_ID" \
    --arg settings_path "$MANAGED_SETTINGS_PATH" \
    --arg permission_mode "$MODE" \
    --arg permission_policy "$PERMISSION_POLICY" \
    '{
        session_key: $session_key,
        project_label: $project_label,
        cwd: $cwd,
        tmux_session: $tmux_session,
        launch_mode: $launch_mode,
        controller: $controller,
        notify_mode: $notify_mode,
        status: $status,
        managed_by: $managed_by,
        claude_session_id: null,
        started_at: $started_at,
        last_activity_at: $last_activity_at,
        last_event: $last_event,
        last_summary: "",
        last_message: "",
        last_title: "",
        last_notification_type: "",
        attached_clients: 0,
        tmux_exists: true,
        chat_id: $chat_id,
        channel: $channel,
        agent_name: $agent_name,
        openclaw_session_id: $openclaw_session_id,
        managed_settings_path: $settings_path,
        permission_mode: $permission_mode,
        permission_policy: $permission_policy
    }')

session_store_write_json "$SESSION_KEY" "$METADATA_JSON"

CLAUDE_CMD=(
    env
    "OPENCLAW_HANDOFF_CAPABLE=1"
    "OPENCLAW_SESSION_KEY=$SESSION_KEY"
    "OPENCLAW_TMUX_SESSION=$SESSION"
    "OPENCLAW_PROJECT_LABEL=$PROJECT_LABEL"
    "OPENCLAW_OPENCLAW_SESSION_ID=$OPENCLAW_SESSION_ID"
    "OPENCLAW_PERMISSION_POLICY=$PERMISSION_POLICY"
    "$CLAUDE_BIN"
    "--settings" "$MANAGED_SETTINGS_PATH"
    "${CLAUDE_ARGS[@]}"
)
printf -v CLAUDE_CMD_STR '%q ' "${CLAUDE_CMD[@]}"
CLAUDE_CMD_STR="${CLAUDE_CMD_STR% }"

if ! tmux new-session -d -s "$SESSION" -c "$WORKDIR"; then
    session_store_merge "$SESSION_KEY" "$(jq -n \
        --arg status "error" \
        --arg last_event "tmux_create_failed" \
        --arg last_activity_at "$(session_store_now_iso)" \
        '{status: $status, last_event: $last_event, last_activity_at: $last_activity_at, tmux_exists: false}')" >/dev/null
    echo "❌ Failed to create tmux session: $SESSION"
    exit 1
fi

if ! tmux send-keys -t "$SESSION" "$CLAUDE_CMD_STR" Enter; then
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    session_store_merge "$SESSION_KEY" "$(jq -n \
        --arg status "error" \
        --arg last_event "tmux_send_failed" \
        --arg last_activity_at "$(session_store_now_iso)" \
        '{status: $status, last_event: $last_event, last_activity_at: $last_activity_at, tmux_exists: false}')" >/dev/null
    echo "❌ Failed to send command to tmux session: $SESSION"
    exit 1
fi

sleep 3
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    session_store_merge "$SESSION_KEY" "$(jq -n \
        --arg status "error" \
        --arg last_event "claude_start_failed" \
        --arg last_activity_at "$(session_store_now_iso)" \
        '{status: $status, last_event: $last_event, last_activity_at: $last_activity_at, tmux_exists: false}')" >/dev/null
    echo "❌ tmux session died immediately, Claude Code may have failed to start"
    exit 1
fi

echo "✅ Claude Code started"
echo "   session:      $SESSION"
echo "   session_key:  $SESSION_KEY"
echo "   project:      $PROJECT_LABEL"
echo "   workdir:      $WORKDIR"
echo "   controller:   $CONTROLLER"
echo "   notify_mode:  $NOTIFY_MODE"
echo "   mode:         $MODE"
echo "   perm_policy:  $PERMISSION_POLICY"
if [ "${#CLAUDE_ARGS[@]}" -gt 0 ]; then
    echo "   args:         ${CLAUDE_ARGS[*]}"
fi
echo ""
echo "📎 tmux attach -t $SESSION    # 直接查看"
echo "🔪 ./stop_claude.sh $SESSION  # 一键清理"
