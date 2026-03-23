#!/bin/bash
# Return a managed Claude session to local control.
# Usage: ./reclaim.sh <selector>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/session_store.sh"

print_help() {
    cat <<EOF
Usage: $0 <selector>

Return a managed Claude session to local control.

Examples:
  $0 my-project
  $0 claude-demo
  $0 /abs/path/to/project

Selector resolution order:
  session_key -> tmux_session -> full cwd -> openclaw_session_id -> unique project_label -> unique cwd basename
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    print_help
    exit 0
fi

SELECTOR="${1:?Usage: $0 <selector>}"
set +e
SESSION_KEY="$(session_store_resolve_selector_checked "$SELECTOR")"
RESOLVE_RC=$?
set -e
if [ "$RESOLVE_RC" -ne 0 ]; then
    exit "$RESOLVE_RC"
fi

session_store_refresh_live_state "$SESSION_KEY" >/dev/null 2>&1 || true
SESSION_JSON="$(session_store_read "$SESSION_KEY")"
PROJECT_LABEL="$(printf '%s' "$SESSION_JSON" | jq -r '.project_label // .session_key')"
TMUX_SESSION="$(printf '%s' "$SESSION_JSON" | jq -r '.tmux_session // ""')"

session_store_merge "$SESSION_KEY" "$(jq -n \
    --arg controller "local" \
    --arg notify_mode "off" \
    --arg permission_policy "off" \
    --arg last_event "manual_reclaim" \
    --arg last_activity_at "$(session_store_now_iso)" \
    '{
        controller: $controller,
        notify_mode: $notify_mode,
        permission_policy: $permission_policy,
        last_event: $last_event,
        last_activity_at: $last_activity_at
    }')" >/dev/null

echo "✅ Session returned to local control"
echo "   project:      $PROJECT_LABEL"
echo "   session_key:  $SESSION_KEY"
echo "   tmux_session: ${TMUX_SESSION:-"-"}"
echo "   notify_mode:  off"
echo "   perm_policy:  off"
