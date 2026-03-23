#!/bin/bash
# Stop a managed Claude tmux session.
# Usage: ./stop_claude.sh <session-key|tmux-session|project-label|cwd>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../runtime/session_store.sh"

SELECTOR="${1:?Usage: $0 <session-key|tmux-session|project-label|cwd>}"
set +e
SESSION_KEY="$(session_store_resolve_selector_checked "$SELECTOR")"
RESOLVE_RC=$?
set -e
if [ "$RESOLVE_RC" -ne 0 ]; then
    exit "$RESOLVE_RC"
fi

session_store_refresh_live_state "$SESSION_KEY" >/dev/null 2>&1 || true
SESSION_JSON="$(session_store_read "$SESSION_KEY")"
TMUX_SESSION="$(printf '%s' "$SESSION_JSON" | jq -r '.tmux_session // ""')"
STATUS="$(printf '%s' "$SESSION_JSON" | jq -r '.status // "running"')"

if [ -n "$TMUX_SESSION" ] && tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux send-keys -t "$TMUX_SESSION" '/exit' 2>/dev/null || true
    sleep 1
    tmux send-keys -t "$TMUX_SESSION" Enter 2>/dev/null || true
    sleep 2
fi

if [ -n "$TMUX_SESSION" ] && tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux kill-session -t "$TMUX_SESSION"
    STATUS="stopped"
    echo "✅ Session stopped: $TMUX_SESSION"
else
    STATUS="stopped"
    echo "ℹ️ Session already inactive: $TMUX_SESSION"
fi

session_store_merge "$SESSION_KEY" "$(jq -n \
    --arg status "$STATUS" \
    --arg last_event "session_stopped" \
    --arg last_activity_at "$(session_store_now_iso)" \
    '{
        status: $status,
        last_event: $last_event,
        last_activity_at: $last_activity_at,
        attached_clients: 0,
        tmux_exists: false
    }')" >/dev/null

session_store_remove_settings_file "$SESSION_KEY" >/dev/null 2>&1 || true
