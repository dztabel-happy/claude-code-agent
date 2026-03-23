#!/bin/bash
# List managed Claude sessions.
# Usage: ./list_sessions.sh [--all] [--json]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/session_store.sh"

INCLUDE_STOPPED=0
JSON_OUTPUT=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --all)
            INCLUDE_STOPPED=1
            shift
            ;;
        --json)
            JSON_OUTPUT=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--all] [--json]"
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ "$JSON_OUTPUT" -eq 1 ]; then
    session_store_list_json "$INCLUDE_STOPPED"
    exit 0
fi

printf '%-18s %-18s %-10s %-10s %-8s %-20s %s\n' "PROJECT" "TMUX" "CTRL" "NOTIFY" "ATTACH" "LAST_ACTIVITY" "CWD"
printf '%-18s %-18s %-10s %-10s %-8s %-20s %s\n' "-------" "----" "----" "------" "------" "-------------" "---"

FOUND=0
while IFS= read -r session_key; do
    [ -n "$session_key" ] || continue
    session_store_refresh_live_state "$session_key" >/dev/null 2>&1 || true
    SESSION_JSON="$(session_store_read "$session_key")" || continue
    STATUS="$(printf '%s' "$SESSION_JSON" | jq -r '.status // "running"')"

    if [ "$INCLUDE_STOPPED" -ne 1 ] && [ "$STATUS" != "running" ]; then
        continue
    fi

    FOUND=1
    printf '%-18s %-18s %-10s %-10s %-8s %-20s %s\n' \
        "$(printf '%s' "$SESSION_JSON" | jq -r '.project_label // .session_key')" \
        "$(printf '%s' "$SESSION_JSON" | jq -r '.tmux_session // "-"')" \
        "$(printf '%s' "$SESSION_JSON" | jq -r '.controller // "-"')" \
        "$(printf '%s' "$SESSION_JSON" | jq -r '.notify_mode // "-"')" \
        "$(printf '%s' "$SESSION_JSON" | jq -r '.attached_clients // 0')" \
        "$(printf '%s' "$SESSION_JSON" | jq -r '.last_activity_at // "-"')" \
        "$(printf '%s' "$SESSION_JSON" | jq -r '.cwd // "-"')"
done < <(session_store_list_keys)

if [ "$FOUND" -eq 0 ]; then
    echo "No managed Claude sessions found."
fi
