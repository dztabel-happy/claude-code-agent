#!/bin/bash
# Common helpers for Claude hook scripts.

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HOOKS_DIR/../runtime/session_store.sh"

hook_private_dir() {
    local kind="${1:?directory kind required}"
    local dir

    dir="$(session_store_runtime_dir)/$kind"
    mkdir -p "$dir"
    chmod 700 "$dir" 2>/dev/null || true
    printf '%s\n' "$dir"
}

hook_prepare_log_file() {
    local name="${1:?log name required}"
    local dir
    local file
    local old_umask

    dir="$(hook_private_dir logs)"
    file="$dir/${name}.log"

    if [ -L "$file" ]; then
        echo "Refusing to use symlink log file: $file" >&2
        return 1
    fi

    if [ ! -e "$file" ]; then
        old_umask="$(umask)"
        umask 077
        : > "$file"
        umask "$old_umask"
    fi
    chmod 600 "$file" 2>/dev/null || true

    printf '%s\n' "$file"
}

hook_log() {
    local log_file="${1:?log file required}"
    shift

    if [ -L "$log_file" ]; then
        return 1
    fi
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$log_file"
}

hook_managed_session_key() {
    if [ "${OPENCLAW_HANDOFF_CAPABLE:-0}" != "1" ]; then
        return 1
    fi

    if [ -z "${OPENCLAW_SESSION_KEY:-}" ]; then
        return 1
    fi

    if ! session_store_exists "$OPENCLAW_SESSION_KEY"; then
        return 1
    fi

    printf '%s\n' "$OPENCLAW_SESSION_KEY"
}

hook_load_session_json() {
    local session_key="${1:?session key required}"
    session_store_refresh_live_state "$session_key" >/dev/null 2>&1 || true
    session_store_read "$session_key"
}

hook_should_notify_user() {
    local notify_mode="${1:-off}"
    local importance="${2:-routine}"
    local attached_clients="${3:-0}"

    if [ "$attached_clients" -gt 0 ]; then
        return 1
    fi

    case "$notify_mode" in
        live)
            return 0
            ;;
        attention)
            [ "$importance" = "important" ]
            return
            ;;
        *)
            return 1
            ;;
    esac
}

hook_send_user_message() {
    local log_file="${1:?log file required}"
    local channel="${2:-telegram}"
    local chat_id="${3:-}"
    local message="${4:-}"

    if [ -z "$chat_id" ] || [ "$chat_id" = "YOUR_CHAT_ID" ]; then
        hook_log "$log_file" "Channel notify skipped (chat_id missing)"
        return 1
    fi

    if openclaw message send --channel "$channel" --target "$chat_id" --message "$message" --silent 2>>"$log_file"; then
        hook_log "$log_file" "Channel notify sent"
        return 0
    fi

    hook_log "$log_file" "Channel notify failed"
    return 1
}

hook_wake_lock_dir() {
    local session_key="${1:?session key required}"
    printf '%s/%s.lock\n' "$(hook_private_dir wake-locks)" "$session_key"
}

hook_now_epoch() {
    date +%s
}

hook_path_mtime_epoch() {
    local path="${1:?path required}"

    if stat -f '%m' "$path" >/dev/null 2>&1; then
        stat -f '%m' "$path"
        return 0
    fi

    if stat -c '%Y' "$path" >/dev/null 2>&1; then
        stat -c '%Y' "$path"
        return 0
    fi

    return 1
}

hook_wake_dedupe_seconds() {
    local starting_grace_seconds="${OPENCLAW_WAKE_LOCK_STARTING_GRACE_SECONDS:-5}"
    local min_hold_seconds="${OPENCLAW_WAKE_LOCK_MIN_HOLD_SECONDS:-1}"
    local dedupe_seconds="${OPENCLAW_WAKE_LOCK_DEDUPE_SECONDS:-$starting_grace_seconds}"

    if [ "$dedupe_seconds" -lt "$min_hold_seconds" ] 2>/dev/null; then
        dedupe_seconds="$min_hold_seconds"
    fi

    printf '%s\n' "$dedupe_seconds"
}

hook_write_private_file() {
    local path="${1:?path required}"
    local content="${2-}"
    local dir
    local old_umask

    dir="$(dirname "$path")"
    [ -d "$dir" ] || return 1

    old_umask="$(umask)"
    umask 077
    printf '%s\n' "$content" > "$path"
    umask "$old_umask"
    chmod 600 "$path" 2>/dev/null || true
}

hook_read_file() {
    local path="${1:?path required}"
    [ -f "$path" ] || return 1
    cat "$path"
}

hook_release_wake_lock() {
    local lock_dir="${1:?lock dir required}"
    local expected_token="${2-}"
    local current_token=""

    [ -d "$lock_dir" ] || return 0

    if [ -f "$lock_dir/token" ]; then
        current_token="$(hook_read_file "$lock_dir/token" 2>/dev/null || true)"
        [ -n "$current_token" ] || return 1
        [ "$current_token" = "$expected_token" ] || return 1
    else
        [ -z "$expected_token" ] || return 1
    fi

    rm -rf "$lock_dir"
}

hook_finalize_wake_lock() {
    local lock_dir="${1:?lock dir required}"
    local expected_token="${2:?expected token required}"
    local created_at=""
    local created_source=""
    local now
    local age=0
    local dedupe_seconds

    dedupe_seconds="$(hook_wake_dedupe_seconds)"

    if [ -f "$lock_dir/created_at" ]; then
        created_at="$(hook_read_file "$lock_dir/created_at" 2>/dev/null || true)"
    fi

    if [ -n "$created_at" ] && [ "$created_at" -eq "$created_at" ] 2>/dev/null; then
        created_source="$created_at"
    else
        created_source="$(hook_path_mtime_epoch "$lock_dir" 2>/dev/null || true)"
    fi

    now="$(hook_now_epoch)"
    if [ -n "$created_source" ] && [ "$created_source" -eq "$created_source" ] 2>/dev/null; then
        age=$((now - created_source))
        if [ "$age" -lt 0 ]; then
            age=0
        fi
    fi

    if [ "$age" -lt "$dedupe_seconds" ]; then
        sleep "$((dedupe_seconds - age))"
    fi

    hook_release_wake_lock "$lock_dir" "$expected_token"
}

hook_mark_wake_lock_published() {
    local lock_dir="${1:?lock dir required}"
    local expected_token="${2:?expected token required}"

    hook_write_private_file "$lock_dir/published" "$expected_token"
}

hook_wait_for_wake_publish() {
    local lock_dir="${1:?lock dir required}"
    local expected_token="${2:?expected token required}"
    local attempts=0
    local max_attempts="${OPENCLAW_WAKE_LOCK_PUBLISH_WAIT_ATTEMPTS:-20}"
    local published_token=""

    while [ "$attempts" -lt "$max_attempts" ]; do
        [ -d "$lock_dir" ] || return 1

        if [ -f "$lock_dir/published" ]; then
            published_token="$(hook_read_file "$lock_dir/published" 2>/dev/null || true)"
            [ "$published_token" = "$expected_token" ] && return 0
        fi

        attempts=$((attempts + 1))
        sleep 0.05
    done

    return 1
}

hook_write_wake_lock_metadata() {
    local lock_dir="${1:?lock dir required}"
    local token="${2:?token required}"
    local state="${3:?state required}"
    local owner_pid="${4:-}"
    local wake_pid="${5:-}"
    local created_at="${6:-}"

    [ -d "$lock_dir" ] || return 1
    if [ -f "$lock_dir/token" ]; then
        local current_token
        current_token="$(hook_read_file "$lock_dir/token" 2>/dev/null || true)"
        [ -n "$current_token" ] && [ "$current_token" != "$token" ] && return 1
    fi

    hook_write_private_file "$lock_dir/token" "$token" || return 1

    if [ -n "$owner_pid" ]; then
        hook_write_private_file "$lock_dir/owner_pid" "$owner_pid" || return 1
    fi

    if [ -n "$wake_pid" ]; then
        hook_write_private_file "$lock_dir/wake_pid" "$wake_pid" || return 1
    else
        rm -f "$lock_dir/wake_pid"
    fi

    if [ -n "$created_at" ]; then
        hook_write_private_file "$lock_dir/created_at" "$created_at" || return 1
    fi

    hook_write_private_file "$lock_dir/state" "$state" || return 1
}

hook_acquire_wake_lock() {
    local session_key="${1:?session key required}"
    local log_file="${2:?log file required}"
    local lock_dir
    local token
    local existing_token=""
    local state=""
    local owner_pid=""
    local wake_pid=""
    local created_at=""
    local created_source=""
    local now
    local age=0
    local starting_grace_seconds="${OPENCLAW_WAKE_LOCK_STARTING_GRACE_SECONDS:-5}"
    local dedupe_seconds

    dedupe_seconds="$(hook_wake_dedupe_seconds)"

    lock_dir="$(hook_wake_lock_dir "$session_key")"
    token="${session_key}-$$-$RANDOM-$(hook_now_epoch)"

    if mkdir "$lock_dir" 2>/dev/null; then
        chmod 700 "$lock_dir" 2>/dev/null || true
        hook_write_wake_lock_metadata "$lock_dir" "$token" "starting" "$$" "" "$(hook_now_epoch)"
        printf '%s\t%s\n' "$lock_dir" "$token"
        return 0
    fi

    if [ -f "$lock_dir/token" ]; then
        existing_token="$(hook_read_file "$lock_dir/token" 2>/dev/null || true)"
    fi

    if [ -f "$lock_dir/state" ]; then
        state="$(hook_read_file "$lock_dir/state" 2>/dev/null || true)"
    fi
    if [ -f "$lock_dir/owner_pid" ]; then
        owner_pid="$(hook_read_file "$lock_dir/owner_pid" 2>/dev/null || true)"
    fi
    if [ -f "$lock_dir/wake_pid" ]; then
        wake_pid="$(hook_read_file "$lock_dir/wake_pid" 2>/dev/null || true)"
    fi
    if [ -f "$lock_dir/created_at" ]; then
        created_at="$(hook_read_file "$lock_dir/created_at" 2>/dev/null || true)"
    fi

    if [ -n "$created_at" ] && [ "$created_at" -eq "$created_at" ] 2>/dev/null; then
        created_source="$created_at"
    else
        created_source="$(hook_path_mtime_epoch "$lock_dir" 2>/dev/null || true)"
    fi

    now="$(hook_now_epoch)"
    if [ -n "$created_source" ] && [ "$created_source" -eq "$created_source" ] 2>/dev/null; then
        age=$((now - created_source))
        if [ "$age" -lt 0 ]; then
            age=0
        fi
    fi

    if session_store_pid_exists "$wake_pid"; then
        hook_log "$log_file" "OpenClaw wake skipped (session already waking, pid=$wake_pid)"
        return 1
    fi

    if [ "$state" = "running" ] && [ "$age" -lt "$dedupe_seconds" ]; then
        hook_log "$log_file" "OpenClaw wake skipped (session wake cooling down, age=${age}s)"
        return 1
    fi

    if [ "$state" = "starting" ] || [ -z "$state" ]; then
        if session_store_pid_exists "$owner_pid"; then
            hook_log "$log_file" "OpenClaw wake skipped (session wake starting, owner_pid=$owner_pid)"
            return 1
        fi
        if [ "$age" -lt "$starting_grace_seconds" ]; then
            hook_log "$log_file" "OpenClaw wake skipped (session wake metadata pending, age=${age}s)"
            return 1
        fi
    fi

    if ! hook_release_wake_lock "$lock_dir" "$existing_token"; then
        hook_log "$log_file" "OpenClaw wake skipped (failed to reclaim wake lock)"
        return 1
    fi

    if mkdir "$lock_dir" 2>/dev/null; then
        chmod 700 "$lock_dir" 2>/dev/null || true
        hook_write_wake_lock_metadata "$lock_dir" "$token" "starting" "$$" "" "$(hook_now_epoch)"
        printf '%s\t%s\n' "$lock_dir" "$token"
        return 0
    fi

    hook_log "$log_file" "OpenClaw wake skipped (failed to acquire wake lock)"
    return 1
}

hook_wake_openclaw() {
    local log_file="${1:?log file required}"
    local session_key="${2:?session key required}"
    local controller="${3:-local}"
    local agent_name="${4:-main}"
    local channel="${5:-telegram}"
    local message="${6:-}"
    local openclaw_session_id
    local wake_pid
    local lock_dir
    local lock_token
    local lock_info

    if [ "$controller" != "openclaw" ]; then
        hook_log "$log_file" "OpenClaw wake skipped (controller=$controller)"
        return 1
    fi

    if [ -z "$agent_name" ]; then
        hook_log "$log_file" "OpenClaw wake skipped (agent_name missing)"
        return 1
    fi

    if ! command -v openclaw >/dev/null 2>&1; then
        hook_log "$log_file" "OpenClaw wake failed (openclaw not found)"
        return 1
    fi

    openclaw_session_id="${OPENCLAW_OPENCLAW_SESSION_ID:-$(session_store_openclaw_session_id "$session_key")}"

    lock_info="$(hook_acquire_wake_lock "$session_key" "$log_file")" || return 1
    IFS=$'\t' read -r lock_dir lock_token <<< "$lock_info"

    (
        trap 'hook_wait_for_wake_publish "$lock_dir" "$lock_token" || true; hook_finalize_wake_lock "$lock_dir" "$lock_token"' EXIT
        if openclaw agent --agent "$agent_name" --session-id "$openclaw_session_id" --message "$message" --deliver --channel "$channel" --timeout 120 >>"$log_file" 2>&1; then
            hook_log "$log_file" "Agent wake completed"
        else
            local rc=$?
            hook_log "$log_file" "Agent wake failed (exit=$rc)"
        fi
    ) &
    wake_pid=$!
    if ! hook_write_wake_lock_metadata "$lock_dir" "$lock_token" "running" "$$" "$wake_pid"; then
        hook_log "$log_file" "Agent wake lock publish skipped (lock changed before publish)"
        return 1
    fi
    hook_mark_wake_lock_published "$lock_dir" "$lock_token" || {
        hook_log "$log_file" "Agent wake lock publish marker skipped (lock changed before publish)"
        return 1
    }
    hook_log "$log_file" "Agent wake queued (pid $wake_pid)"
    return 0
}
