#!/bin/bash
# Unified control entrypoint for managed Claude sessions.
# Usage: ./control_session.sh <list|status|reclaim|takeover|stop> [options] [selector]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/session_store.sh"

print_help() {
    cat <<EOF
Usage: $0 <command> [options] [selector]

Control managed Claude sessions through one entrypoint.

Commands:
  list [--all] [--json]
      List managed Claude sessions.

  status [--json] [selector]
      Show one managed session. If selector is omitted, auto-select only when unambiguous.

  reclaim [selector]
      Return a managed session to local control. If selector is omitted, auto-select only when unambiguous.

  takeover [options] [selector]
      Hand a managed session back to OpenClaw. If selector is omitted, auto-select only when unambiguous.
      Supported options:
        --notify-mode <off|attention|live>
        --permission-policy <off|deny-dangerous|safe>
        --chat-id <id>
        --channel <channel>
        --agent <name>
        --no-wake

  stop [selector]
      Stop one managed Claude session. If selector is omitted, auto-select only when unambiguous.

Selector resolution order:
  session_key -> tmux_session -> full cwd -> openclaw_session_id -> unique project_label -> unique cwd basename

Auto-selection order when selector is omitted:
  1. current OpenClaw session id from environment, if available
  2. exactly one running session with the preferred controller for the action
  3. exactly one running managed session overall

Examples:
  $0 list
  $0 status
  $0 reclaim
  $0 takeover --no-wake
  $0 takeover /path/to/project
  $0 stop claude-demo
EOF
}

current_openclaw_session_id() {
    local name
    local value

    for name in OPENCLAW_SESSION_ID OPENCLAW_CURRENT_SESSION_ID OPENCLAW_OPENCLAW_SESSION_ID; do
        value="${!name:-}"
        if [ -n "$value" ] && [ "$value" != "null" ]; then
            printf '%s\n' "$value"
            return 0
        fi
    done

    return 1
}

print_running_candidates() {
    echo "Running managed Claude sessions:" >&2
    bash "$SCRIPT_DIR/list_sessions.sh" >&2
}

resolve_session_key_for_action() {
    local action="${1:?action required}"
    local selector="${2:-}"
    local sessions_json
    local session_key=""
    local candidate_count="0"
    local preferred_controller=""
    local current_session_id=""
    local total_count="0"

    if [ -n "$selector" ]; then
        session_store_resolve_selector_checked "$selector"
        return 0
    fi

    sessions_json="$(session_store_list_json 0)"
    total_count="$(printf '%s' "$sessions_json" | jq 'length')"

    if [ "$total_count" -eq 0 ]; then
        echo "❌ No running managed Claude sessions found." >&2
        return 1
    fi

    if current_session_id="$(current_openclaw_session_id)"; then
        candidate_count="$(printf '%s' "$sessions_json" | jq -r --arg id "$current_session_id" '[.[] | select(.openclaw_session_id == $id)] | length')"
        if [ "$candidate_count" -eq 1 ]; then
            printf '%s' "$sessions_json" | jq -r --arg id "$current_session_id" '.[] | select(.openclaw_session_id == $id) | .session_key'
            return 0
        fi
    fi

    case "$action" in
        reclaim)
            preferred_controller="openclaw"
            ;;
        takeover)
            preferred_controller="local"
            ;;
    esac

    if [ -n "$preferred_controller" ]; then
        candidate_count="$(printf '%s' "$sessions_json" | jq -r --arg controller "$preferred_controller" '[.[] | select(.controller == $controller)] | length')"
        if [ "$candidate_count" -eq 1 ]; then
            printf '%s' "$sessions_json" | jq -r --arg controller "$preferred_controller" '.[] | select(.controller == $controller) | .session_key'
            return 0
        fi
    fi

    if [ "$total_count" -eq 1 ]; then
        printf '%s' "$sessions_json" | jq -r '.[0].session_key'
        return 0
    fi

    if [ -n "$preferred_controller" ] && [ "$candidate_count" -gt 1 ]; then
        echo "❌ Multiple running managed Claude sessions are eligible for '$action'." >&2
    else
        echo "❌ Multiple running managed Claude sessions found; please specify a selector." >&2
    fi
    print_running_candidates
    return 2
}

run_status() {
    local selector=""
    local args=()
    local session_key

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --json)
                args+=("$1")
                shift
                ;;
            --help|-h)
                exec bash "$SCRIPT_DIR/session_status.sh" --help
                ;;
            *)
                if [ -n "$selector" ]; then
                    echo "❌ Too many selectors for status." >&2
                    exit 1
                fi
                selector="$1"
                shift
                ;;
        esac
    done

    session_key="$(resolve_session_key_for_action status "$selector")"
    exec bash "$SCRIPT_DIR/session_status.sh" "${args[@]}" "$session_key"
}

run_reclaim() {
    local selector="${1:-}"
    local session_key

    if [ "${selector:-}" = "--help" ] || [ "${selector:-}" = "-h" ]; then
        exec bash "$SCRIPT_DIR/reclaim.sh" --help
    fi

    if [ "$#" -gt 1 ]; then
        echo "❌ Too many selectors for reclaim." >&2
        exit 1
    fi

    session_key="$(resolve_session_key_for_action reclaim "$selector")"
    exec bash "$SCRIPT_DIR/reclaim.sh" "$session_key"
}

run_takeover() {
    local selector=""
    local args=()
    local session_key

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --notify-mode|--permission-policy|--chat-id|--channel|--agent)
                args+=("$1" "${2:?$1 requires a value}")
                shift 2
                ;;
            --no-wake)
                args+=("$1")
                shift
                ;;
            --help|-h)
                exec bash "$SCRIPT_DIR/takeover.sh" --help
                ;;
            *)
                if [ -n "$selector" ]; then
                    echo "❌ Too many selectors for takeover." >&2
                    exit 1
                fi
                selector="$1"
                shift
                ;;
        esac
    done

    session_key="$(resolve_session_key_for_action takeover "$selector")"
    exec bash "$SCRIPT_DIR/takeover.sh" "${args[@]}" "$session_key"
}

run_stop() {
    local selector="${1:-}"
    local session_key

    if [ "${selector:-}" = "--help" ] || [ "${selector:-}" = "-h" ]; then
        exec bash "$ROOT_DIR/hooks/stop_claude.sh" --help
    fi

    if [ "$#" -gt 1 ]; then
        echo "❌ Too many selectors for stop." >&2
        exit 1
    fi

    session_key="$(resolve_session_key_for_action stop "$selector")"
    exec bash "$ROOT_DIR/hooks/stop_claude.sh" "$session_key"
}

COMMAND="${1:-}"

case "$COMMAND" in
    ""|--help|-h)
        print_help
        exit 0
        ;;
esac

shift

case "$COMMAND" in
    list)
        exec bash "$SCRIPT_DIR/list_sessions.sh" "$@"
        ;;
    status)
        run_status "$@"
        ;;
    reclaim)
        run_reclaim "$@"
        ;;
    takeover)
        run_takeover "$@"
        ;;
    stop)
        run_stop "$@"
        ;;
    *)
        echo "❌ Unknown command: $COMMAND" >&2
        print_help >&2
        exit 1
        ;;
esac
