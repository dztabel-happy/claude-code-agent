#!/bin/bash
# Hand a managed Claude session over to OpenClaw.
# Usage: ./takeover.sh [--notify-mode MODE] [--chat-id ID] [--channel CHANNEL] [--agent NAME] [--no-wake] <selector>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/session_store.sh"

NOTIFY_MODE="attention"
CHAT_ID=""
CHANNEL=""
AGENT_NAME=""
CHAT_ID_SET=0
CHANNEL_SET=0
AGENT_NAME_SET=0
WAKE_OPENCLAW=1

while [ "$#" -gt 0 ]; do
    case "$1" in
        --notify-mode)
            NOTIFY_MODE="${2:?--notify-mode requires a value}"
            shift 2
            ;;
        --chat-id)
            CHAT_ID="${2:?--chat-id requires a value}"
            CHAT_ID_SET=1
            shift 2
            ;;
        --channel)
            CHANNEL="${2:?--channel requires a value}"
            CHANNEL_SET=1
            shift 2
            ;;
        --agent)
            AGENT_NAME="${2:?--agent requires a value}"
            AGENT_NAME_SET=1
            shift 2
            ;;
        --no-wake)
            WAKE_OPENCLAW=0
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--notify-mode MODE] [--chat-id ID] [--channel CHANNEL] [--agent NAME] [--no-wake] <selector>"
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

case "$NOTIFY_MODE" in
    off|attention|live) ;;
    *)
        echo "❌ Invalid notify mode: $NOTIFY_MODE"
        exit 1
        ;;
esac

SELECTOR="${1:?Usage: $0 [options] <selector>}"
set +e
SESSION_KEY="$(session_store_resolve_selector_checked "$SELECTOR")"
RESOLVE_RC=$?
set -e
if [ "$RESOLVE_RC" -ne 0 ]; then
    exit "$RESOLVE_RC"
fi

session_store_refresh_live_state "$SESSION_KEY" >/dev/null 2>&1 || true
SESSION_JSON="$(session_store_read "$SESSION_KEY")"
STATUS="$(printf '%s' "$SESSION_JSON" | jq -r '.status // "running"')"
PROJECT_LABEL="$(printf '%s' "$SESSION_JSON" | jq -r '.project_label // .session_key')"
TMUX_SESSION="$(printf '%s' "$SESSION_JSON" | jq -r '.tmux_session // ""')"
CWD="$(printf '%s' "$SESSION_JSON" | jq -r '.cwd // ""')"
LAST_SUMMARY="$(printf '%s' "$SESSION_JSON" | jq -r '.last_summary // ""')"
LAST_EVENT="$(printf '%s' "$SESSION_JSON" | jq -r '.last_event // ""')"
OPENCLAW_SESSION_ID="$(printf '%s' "$SESSION_JSON" | jq -r '.openclaw_session_id // ""')"

if [ -z "$OPENCLAW_SESSION_ID" ] || [ "$OPENCLAW_SESSION_ID" = "null" ]; then
    OPENCLAW_SESSION_ID="$(session_store_openclaw_session_id "$SESSION_KEY")"
fi

if [ "$STATUS" != "running" ]; then
    echo "❌ Managed session is not running: $PROJECT_LABEL"
    exit 1
fi

if [ "$CHAT_ID_SET" -ne 1 ]; then
    CHAT_ID="$(printf '%s' "$SESSION_JSON" | jq -r '.chat_id // ""')"
fi
if [ -z "$CHAT_ID" ] || [ "$CHAT_ID" = "null" ]; then
    CHAT_ID="${OPENCLAW_AGENT_CHAT_ID:-${CLAUDE_AGENT_CHAT_ID:-}}"
fi

if [ "$CHANNEL_SET" -ne 1 ]; then
    CHANNEL="$(printf '%s' "$SESSION_JSON" | jq -r '.channel // "telegram"')"
fi
if [ -z "$CHANNEL" ] || [ "$CHANNEL" = "null" ]; then
    CHANNEL="${OPENCLAW_AGENT_CHANNEL:-${CLAUDE_AGENT_CHANNEL:-telegram}}"
fi

if [ "$AGENT_NAME_SET" -ne 1 ]; then
    AGENT_NAME="$(printf '%s' "$SESSION_JSON" | jq -r '.agent_name // "main"')"
fi
if [ -z "$AGENT_NAME" ] || [ "$AGENT_NAME" = "null" ]; then
    AGENT_NAME="${OPENCLAW_AGENT_NAME:-${CLAUDE_AGENT_NAME:-main}}"
fi

session_store_merge "$SESSION_KEY" "$(jq -n \
    --arg controller "openclaw" \
    --arg notify_mode "$NOTIFY_MODE" \
    --arg chat_id "$CHAT_ID" \
    --arg channel "$CHANNEL" \
    --arg agent_name "$AGENT_NAME" \
    --arg openclaw_session_id "$OPENCLAW_SESSION_ID" \
    --arg last_event "manual_takeover" \
    --arg last_activity_at "$(session_store_now_iso)" \
    '{
        controller: $controller,
        notify_mode: $notify_mode,
        chat_id: $chat_id,
        channel: $channel,
        agent_name: $agent_name,
        openclaw_session_id: $openclaw_session_id,
        last_event: $last_event,
        last_activity_at: $last_activity_at
    }')" >/dev/null

echo "✅ OpenClaw takeover enabled"
echo "   project:      $PROJECT_LABEL"
echo "   session_key:  $SESSION_KEY"
echo "   tmux_session: ${TMUX_SESSION:-"-"}"
echo "   oc_session:   $OPENCLAW_SESSION_ID"
echo "   notify_mode:  $NOTIFY_MODE"

if [ "$WAKE_OPENCLAW" -eq 1 ] && command -v openclaw >/dev/null 2>&1; then
    WAKE_MSG="[Claude Code Handoff] 接管已有会话并继续处理。
session_key: $SESSION_KEY
project: $PROJECT_LABEL
tmux_session: ${TMUX_SESSION:-none}
cwd: $CWD
last_event: $LAST_EVENT
last_summary: $LAST_SUMMARY
请先读取 tmux 最近输出，再在同一个 Claude 会话上继续工作。"

    openclaw agent --agent "$AGENT_NAME" --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MSG" --deliver --channel "$CHANNEL" --timeout 120 >/dev/null 2>&1 &
    echo "   wake:         OpenClaw wake requested"
fi
