#!/bin/bash
# Start a handoff-capable local Claude session and attach immediately.
# Usage: ./start_local_claude.sh [--label LABEL] [--session SESSION_NAME] <workdir> [claude args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$SCRIPT_DIR/../hooks"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/session_store.sh"

LABEL=""
SESSION=""
WORKDIR=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --label)
            LABEL="${2:?--label requires a value}"
            shift 2
            ;;
        --session)
            SESSION="${2:?--session requires a value}"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--label LABEL] [--session SESSION_NAME] <workdir> [claude args...]"
            exit 0
            ;;
        *)
            WORKDIR="$1"
            shift
            break
            ;;
    esac
done

if [ -z "$WORKDIR" ]; then
    echo "❌ Usage: $0 [--label LABEL] [--session SESSION_NAME] <workdir> [claude args...]"
    exit 1
fi

CLAUDE_ARGS=("$@")

if [ ! -d "$WORKDIR" ]; then
    echo "❌ Directory not found: $WORKDIR"
    exit 1
fi

if [ -z "$LABEL" ]; then
    LABEL="$(session_store_project_label_from_cwd "$WORKDIR")"
fi
LABEL="$(session_store_slugify "$LABEL")"

if [ -z "$SESSION" ]; then
    BASE_SESSION="claude-$LABEL"
    SESSION="$(session_store_next_tmux_session "$BASE_SESSION")"
else
    SESSION="$(session_store_slugify "$SESSION")"
fi

SESSION_KEY="$(session_store_slugify "$SESSION")"

OPENCLAW_CONTROLLER=local \
OPENCLAW_NOTIFY_MODE=off \
OPENCLAW_MANAGED_BY=local \
OPENCLAW_PROJECT_LABEL="$LABEL" \
OPENCLAW_SESSION_KEY="$SESSION_KEY" \
bash "$HOOKS_DIR/start_claude.sh" "$SESSION" "$WORKDIR" "${CLAUDE_ARGS[@]}"

echo ""
echo "Attaching to $SESSION ..."
exec tmux attach -t "$SESSION"
