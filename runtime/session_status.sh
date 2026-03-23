#!/bin/bash
# Show details for one managed Claude session.
# Usage: ./session_status.sh [--json] <session-key|tmux-session|project-label|cwd>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/session_store.sh"

JSON_OUTPUT=0

print_help() {
    cat <<EOF
Usage: $0 [--json] <selector>

Show details for one managed Claude session.

Options:
  --json      Print raw session JSON
  -h, --help  Show this help

Selector resolution order:
  session_key -> tmux_session -> full cwd -> unique project_label -> unique cwd basename
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --json)
            JSON_OUTPUT=1
            shift
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

SELECTOR="${1:?Usage: $0 [--json] <session-key|tmux-session|project-label|cwd>}"
set +e
SESSION_KEY="$(session_store_resolve_selector_checked "$SELECTOR")"
RESOLVE_RC=$?
set -e
if [ "$RESOLVE_RC" -ne 0 ]; then
    exit "$RESOLVE_RC"
fi

session_store_refresh_live_state "$SESSION_KEY" >/dev/null 2>&1 || true
SESSION_JSON="$(session_store_read "$SESSION_KEY")"

if [ "$JSON_OUTPUT" -eq 1 ]; then
    printf '%s\n' "$SESSION_JSON"
    exit 0
fi

echo "session_key:    $(printf '%s' "$SESSION_JSON" | jq -r '.session_key')"
echo "project_label:  $(printf '%s' "$SESSION_JSON" | jq -r '.project_label')"
echo "tmux_session:   $(printf '%s' "$SESSION_JSON" | jq -r '.tmux_session // "-"')"
echo "controller:     $(printf '%s' "$SESSION_JSON" | jq -r '.controller // "-"')"
echo "notify_mode:    $(printf '%s' "$SESSION_JSON" | jq -r '.notify_mode // "-"')"
echo "status:         $(printf '%s' "$SESSION_JSON" | jq -r '.status // "-"')"
echo "attached:       $(printf '%s' "$SESSION_JSON" | jq -r '.attached_clients // 0')"
echo "process_pid:    $(printf '%s' "$SESSION_JSON" | jq -r '.process_pid // "-"')"
echo "process_alive:  $(printf '%s' "$SESSION_JSON" | jq -r '.process_running // false')"
echo "oc_session:     $(printf '%s' "$SESSION_JSON" | jq -r '.openclaw_session_id // "-"')"
echo "settings_path:  $(printf '%s' "$SESSION_JSON" | jq -r '.managed_settings_path // "-"')"
echo "perm_mode:      $(printf '%s' "$SESSION_JSON" | jq -r '.permission_mode // "-"')"
echo "perm_policy:    $(printf '%s' "$SESSION_JSON" | jq -r '.permission_policy // "-"')"
echo "agent_teams:    $(printf '%s' "$SESSION_JSON" | jq -r '.agent_teams_enabled // false')"
echo "cwd:            $(printf '%s' "$SESSION_JSON" | jq -r '.cwd // "-"')"
echo "claude_session: $(printf '%s' "$SESSION_JSON" | jq -r '.claude_session_id // "-"')"
echo "last_event:     $(printf '%s' "$SESSION_JSON" | jq -r '.last_event // "-"')"
echo "last_activity:  $(printf '%s' "$SESSION_JSON" | jq -r '.last_activity_at // "-"')"
