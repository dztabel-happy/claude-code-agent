#!/bin/bash
# Claude Code one-shot managed runner.
# Usage: ./run_claude.sh <workdir> [claude args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../runtime/session_store.sh"

WORKDIR="${1:?Usage: $0 <workdir> [claude args...]}"
shift
CLAUDE_ARGS=("$@")
CUSTOM_SETTINGS=""
FILTERED_CLAUDE_ARGS=()

if ! command -v claude >/dev/null 2>&1; then
    echo "❌ claude not found. Install: npm install -g @anthropic-ai/claude-code"
    exit 1
fi
CLAUDE_BIN="$(command -v claude)"

if [ ! -d "$WORKDIR" ]; then
    echo "❌ Directory not found: $WORKDIR"
    exit 1
fi

PROJECT_LABEL="${OPENCLAW_PROJECT_LABEL:-$(session_store_project_label_from_cwd "$WORKDIR")}"
SESSION_KEY="${OPENCLAW_SESSION_KEY:-$(session_store_slugify "claude-print-$PROJECT_LABEL-$(date +%s)-$$")}"
OPENCLAW_SESSION_ID="${OPENCLAW_OPENCLAW_SESSION_ID:-$(session_store_openclaw_session_id "$SESSION_KEY")}"
CONTROLLER="${OPENCLAW_CONTROLLER:-openclaw}"
NOTIFY_MODE="${OPENCLAW_NOTIFY_MODE:-attention}"
MANAGED_BY="${OPENCLAW_MANAGED_BY:-openclaw}"
PERMISSION_POLICY="${OPENCLAW_PERMISSION_POLICY:-}"
CHAT_ID="${OPENCLAW_AGENT_CHAT_ID:-${CLAUDE_AGENT_CHAT_ID:-}}"
CHANNEL="${OPENCLAW_AGENT_CHANNEL:-${CLAUDE_AGENT_CHANNEL:-telegram}}"
AGENT_NAME="${OPENCLAW_AGENT_NAME:-${CLAUDE_AGENT_NAME:-main}}"
STARTED_AT="$(session_store_now_iso)"
CLAUDE_PID=""
PRINT_MODE=0

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

for arg in "${CLAUDE_ARGS[@]}"; do
    case "$arg" in
        -p|--print)
            PRINT_MODE=1
            ;;
    esac
done

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

if [ "$PRINT_MODE" -ne 1 ]; then
    echo "❌ run_claude.sh requires Claude print mode (-p/--print)."
    echo "   Example: bash hooks/run_claude.sh <workdir> -p --model sonnet \"<prompt>\""
    exit 1
fi

METADATA_JSON=$(jq -n \
    --arg session_key "$SESSION_KEY" \
    --arg project_label "$PROJECT_LABEL" \
    --arg cwd "$WORKDIR" \
    --arg launch_mode "print" \
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
    --arg launcher_pid "$$" \
    '{
        session_key: $session_key,
        project_label: $project_label,
        cwd: $cwd,
        tmux_session: "",
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
        tmux_exists: false,
        launcher_pid: ($launcher_pid | tonumber),
        process_pid: null,
        process_running: false,
        chat_id: $chat_id,
        channel: $channel,
        agent_name: $agent_name,
        openclaw_session_id: $openclaw_session_id,
        managed_settings_path: $settings_path,
        permission_mode: $permission_mode,
        permission_policy: $permission_policy
    }')

session_store_write_json "$SESSION_KEY" "$METADATA_JSON"

finalize_print_session() {
    local final_status="${1:?final status required}"
    local final_event="${2:?final event required}"
    local current_status

    current_status=$(session_store_read "$SESSION_KEY" 2>/dev/null | jq -r '.status // "running"' 2>/dev/null || echo "running")
    if [ "$current_status" = "running" ]; then
        session_store_merge "$SESSION_KEY" "$(jq -n \
            --arg status "$final_status" \
            --arg last_event "$final_event" \
            --arg last_activity_at "$(session_store_now_iso)" \
            '{
                status: $status,
                last_event: $last_event,
                last_activity_at: $last_activity_at,
                process_running: false
            }')" >/dev/null
    fi
}

handle_signal() {
    local signal_name="${1:-signal}"

    if [ -n "$CLAUDE_PID" ]; then
        kill "$CLAUDE_PID" 2>/dev/null || true
        wait "$CLAUDE_PID" 2>/dev/null || true
    fi

    finalize_print_session "error" "process_interrupted_$signal_name"
    exit 130
}

trap 'handle_signal term' TERM
trap 'handle_signal int' INT
trap 'handle_signal hup' HUP

export OPENCLAW_HANDOFF_CAPABLE=1
export OPENCLAW_SESSION_KEY="$SESSION_KEY"
export OPENCLAW_TMUX_SESSION=""
export OPENCLAW_PROJECT_LABEL="$PROJECT_LABEL"
export OPENCLAW_OPENCLAW_SESSION_ID="$OPENCLAW_SESSION_ID"
export OPENCLAW_PERMISSION_POLICY="$PERMISSION_POLICY"

cd "$WORKDIR"
"$CLAUDE_BIN" --settings "$MANAGED_SETTINGS_PATH" "${CLAUDE_ARGS[@]}" &
CLAUDE_PID=$!

session_store_merge "$SESSION_KEY" "$(jq -n \
    --arg process_pid "$CLAUDE_PID" \
    --arg last_event "process_started" \
    --arg last_activity_at "$(session_store_now_iso)" \
    '{
        process_pid: ($process_pid | tonumber),
        process_running: true,
        last_event: $last_event,
        last_activity_at: $last_activity_at
    }')" >/dev/null

if wait "$CLAUDE_PID"; then
    STATUS=0
else
    STATUS=$?
fi

if [ "$STATUS" -eq 0 ]; then
    FINAL_STATUS="stopped"
    FINAL_EVENT="process_exit"
else
    FINAL_STATUS="error"
    FINAL_EVENT="process_exit_error"
fi

finalize_print_session "$FINAL_STATUS" "$FINAL_EVENT"
session_store_remove_settings_file "$SESSION_KEY" >/dev/null 2>&1 || true

exit "$STATUS"
