#!/bin/bash
# Runtime helpers for managed Claude sessions.
# This file is intended to be sourced by other scripts.

session_store_runtime_dir() {
    printf '%s\n' "${OPENCLAW_CLAUDE_RUNTIME_DIR:-$HOME/.openclaw/runtime/claude-code-agent}"
}

session_store_sessions_dir() {
    printf '%s\n' "$(session_store_runtime_dir)/sessions"
}

session_store_settings_dir() {
    printf '%s\n' "$(session_store_runtime_dir)/settings"
}

session_store_now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

session_store_ensure_dirs() {
    mkdir -p "$(session_store_sessions_dir)" "$(session_store_settings_dir)"
}

session_store_slugify() {
    local input="${1:-}"

    input=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')
    input=$(printf '%s' "$input" | tr -cs 'a-z0-9._-' '-')
    input=$(printf '%s' "$input" | sed -E 's/^-+//; s/-+$//; s/-+/-/g')

    if [ -z "$input" ]; then
        input="session"
    fi

    printf '%s\n' "$input"
}

session_store_project_label_from_cwd() {
    local cwd="${1:-}"
    local base

    base=$(basename "$cwd" 2>/dev/null || true)
    session_store_slugify "$base"
}

session_store_session_file() {
    local session_key="${1:?session key required}"
    printf '%s/%s.json\n' "$(session_store_sessions_dir)" "$session_key"
}

session_store_settings_file() {
    local session_key="${1:?session key required}"
    printf '%s/%s.settings.json\n' "$(session_store_settings_dir)" "$session_key"
}

session_store_lock_dir() {
    local session_key="${1:?session key required}"
    printf '%s/.%s.lock\n' "$(session_store_sessions_dir)" "$session_key"
}

session_store_openclaw_session_id() {
    local session_key="${1:?session key required}"
    session_store_slugify "claude-code-agent-$session_key"
}

session_store_acquire_lock() {
    local session_key="${1:?session key required}"
    local lock_dir
    local attempt=0

    lock_dir=$(session_store_lock_dir "$session_key")
    session_store_ensure_dirs

    while ! mkdir "$lock_dir" 2>/dev/null; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 200 ]; then
            echo "Failed to acquire session lock: $session_key" >&2
            return 1
        fi
        sleep 0.05
    done
}

session_store_release_lock() {
    local session_key="${1:?session key required}"
    local lock_dir

    lock_dir=$(session_store_lock_dir "$session_key")
    rmdir "$lock_dir" 2>/dev/null || true
}

session_store_exists() {
    local session_key="${1:?session key required}"
    [ -f "$(session_store_session_file "$session_key")" ]
}

session_store_read() {
    local session_key="${1:?session key required}"
    local file

    file=$(session_store_session_file "$session_key")
    [ -f "$file" ] || return 1
    cat "$file"
}

session_store_write_json() {
    local session_key="${1:?session key required}"
    local json="${2:?json required}"
    local file
    local tmp

    session_store_ensure_dirs
    file=$(session_store_session_file "$session_key")
    tmp=$(mktemp "$(session_store_sessions_dir)/.${session_key}.XXXXXX")
    printf '%s\n' "$json" > "$tmp"
    mv "$tmp" "$file"
}

session_store_write_managed_settings() {
    local session_key="${1:?session key required}"
    local skill_dir="${2:?skill dir required}"
    local agent_teams_enabled="${OPENCLAW_ENABLE_AGENT_TEAMS:-0}"
    local file
    local tmp
    local json

    session_store_ensure_dirs
    file=$(session_store_settings_file "$session_key")
    tmp=$(mktemp "$(session_store_settings_dir)/.${session_key}.settings.XXXXXX")

    json=$(jq -n \
        --arg stop_cmd "bash \"$skill_dir/hooks/on_stop.sh\"" \
        --arg notify_cmd "bash \"$skill_dir/hooks/on_notification.sh\"" \
        --arg permission_cmd "bash \"$skill_dir/hooks/on_permission_request.sh\"" \
        --arg teammate_cmd "bash \"$skill_dir/hooks/on_teammate_idle.sh\"" \
        --arg task_cmd "bash \"$skill_dir/hooks/on_task_completed.sh\"" \
        --arg agent_teams_enabled "$agent_teams_enabled" \
        '{
            hooks: {
                Stop: [
                    {
                        hooks: [
                            {
                                type: "command",
                                command: $stop_cmd,
                                timeout: 15
                            }
                        ]
                    }
                ],
                Notification: [
                    {
                        matcher: "permission_prompt|idle_prompt",
                        hooks: [
                            {
                                type: "command",
                                command: $notify_cmd,
                                timeout: 15
                            }
                        ]
                    }
                ],
                PermissionRequest: [
                    {
                        matcher: "Bash",
                        hooks: [
                            {
                                type: "command",
                                command: $permission_cmd,
                                timeout: 15
                            }
                        ]
                    }
                ]
            }
        }
        | if $agent_teams_enabled == "1" then
            .env = {
                CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"
            }
            | .hooks.TeammateIdle = [
                {
                    hooks: [
                        {
                            type: "command",
                            command: $teammate_cmd,
                            timeout: 15
                        }
                    ]
                }
            ]
            | .hooks.TaskCompleted = [
                {
                    hooks: [
                        {
                            type: "command",
                            command: $task_cmd,
                            timeout: 600
                        }
                    ]
                }
            ]
          else
            .
          end') || return 1

    printf '%s\n' "$json" > "$tmp"
    mv "$tmp" "$file"
    chmod 600 "$file" 2>/dev/null || true
    printf '%s\n' "$file"
}

session_store_settings_arg_json() {
    local value="${1:-}"
    local base_dir="${2:-}"

    if [ -z "$value" ]; then
        printf '{}\n'
        return 0
    fi

    if [ -f "$value" ]; then
        jq -c '.' "$value"
        return $?
    fi

    if [ -n "$base_dir" ] && [ "${value#/}" = "$value" ] && [ -f "$base_dir/$value" ]; then
        jq -c '.' "$base_dir/$value"
        return $?
    fi

    printf '%s\n' "$value" | jq -c '.'
}

session_store_write_combined_settings() {
    local session_key="${1:?session key required}"
    local skill_dir="${2:?skill dir required}"
    local custom_settings="${3-}"
    local custom_base_dir="${4:-}"
    local file
    local tmp
    local managed_json
    local custom_json
    local combined_json

    session_store_ensure_dirs
    file=$(session_store_settings_file "$session_key")
    tmp=$(mktemp "$(session_store_settings_dir)/.${session_key}.settings.XXXXXX")

    managed_json="$(session_store_write_managed_settings "$session_key" "$skill_dir" >/dev/null && cat "$file")" || return 1
    custom_json="$(session_store_settings_arg_json "$custom_settings" "$custom_base_dir")" || return 1

    combined_json="$(jq -n \
        --argjson custom "$custom_json" \
        --argjson managed "$managed_json" \
        '
        def merge_hook_groups($a; $b):
            ((($a | keys_unsorted) + ($b | keys_unsorted)) | unique) as $keys
            | reduce $keys[] as $key ({}; .[$key] = (($a[$key] // []) + ($b[$key] // [])));

        $custom
        | .env = (($custom.env // {}) + ($managed.env // {}))
        | .hooks = merge_hook_groups(($custom.hooks // {}); ($managed.hooks // {}))
        ')" || return 1

    printf '%s\n' "$combined_json" > "$tmp"
    mv "$tmp" "$file"
    chmod 600 "$file" 2>/dev/null || true
    printf '%s\n' "$file"
}

session_store_remove_settings_file() {
    local session_key="${1:?session key required}"
    rm -f "$(session_store_settings_file "$session_key")"
}

session_store_merge() {
    local session_key="${1:?session key required}"
    local patch_json="${2:?patch json required}"
    local current='{}'
    local merged

    session_store_acquire_lock "$session_key" || return 1

    if session_store_exists "$session_key"; then
        current=$(session_store_read "$session_key") || {
            session_store_release_lock "$session_key"
            return 1
        }
    fi

    merged=$(jq -n \
        --argjson current "$current" \
        --argjson patch "$patch_json" \
        '$current + $patch') || {
        session_store_release_lock "$session_key"
        return 1
    }

    session_store_write_json "$session_key" "$merged" || {
        session_store_release_lock "$session_key"
        return 1
    }

    session_store_release_lock "$session_key"
}

session_store_attached_clients() {
    local tmux_session="${1:-}"

    if [ -z "$tmux_session" ]; then
        printf '0\n'
        return 0
    fi

    if ! command -v tmux >/dev/null 2>&1; then
        printf '0\n'
        return 0
    fi

    if ! tmux has-session -t "$tmux_session" 2>/dev/null; then
        printf '0\n'
        return 0
    fi

    tmux list-clients -t "$tmux_session" 2>/dev/null | awk 'END { print NR }'
}

session_store_tmux_exists() {
    local tmux_session="${1:-}"

    if [ -z "$tmux_session" ] || ! command -v tmux >/dev/null 2>&1; then
        return 1
    fi

    tmux has-session -t "$tmux_session" 2>/dev/null
}

session_store_pid_exists() {
    local pid="${1:-}"

    if [ -z "$pid" ]; then
        return 1
    fi

    case "$pid" in
        *[!0-9]*)
            return 1
            ;;
    esac

    kill -0 "$pid" 2>/dev/null
}

session_store_refresh_live_state() {
    local session_key="${1:?session key required}"
    local json
    local tmux_session
    local launch_mode
    local process_pid
    local status
    local attached_clients
    local tmux_exists="false"
    local process_running="false"
    local patch_json

    json=$(session_store_read "$session_key") || return 1
    tmux_session=$(printf '%s' "$json" | jq -r '.tmux_session // ""')
    launch_mode=$(printf '%s' "$json" | jq -r '.launch_mode // ""')
    process_pid=$(printf '%s' "$json" | jq -r '.process_pid // ""')
    status=$(printf '%s' "$json" | jq -r '.status // "running"')
    attached_clients=$(session_store_attached_clients "$tmux_session")

    if session_store_tmux_exists "$tmux_session"; then
        tmux_exists="true"
    fi

    if [ "$launch_mode" = "interactive" ] && [ "$tmux_exists" != "true" ] && [ "$status" = "running" ]; then
        status="stopped"
    fi

    if session_store_pid_exists "$process_pid"; then
        process_running="true"
    fi

    if [ "$launch_mode" = "print" ] && [ "$status" = "running" ] && [ "$process_running" != "true" ]; then
        status="stopped"
    fi

    patch_json=$(jq -n \
        --arg status "$status" \
        --arg tmux_exists "$tmux_exists" \
        --arg process_running "$process_running" \
        --argjson attached_clients "$attached_clients" \
        '{
            status: $status,
            tmux_exists: ($tmux_exists == "true"),
            process_running: ($process_running == "true"),
            attached_clients: $attached_clients
        }')

    session_store_merge "$session_key" "$patch_json" >/dev/null
}

session_store_list_keys() {
    local dir
    local file

    session_store_ensure_dirs
    dir=$(session_store_sessions_dir)

    shopt -s nullglob
    for file in "$dir"/*.json; do
        basename "$file" .json
    done
    shopt -u nullglob
}

session_store_list_json() {
    local include_stopped="${1:-0}"
    local first=1
    local session_key
    local json
    local status

    printf '['
    while IFS= read -r session_key; do
        [ -n "$session_key" ] || continue
        session_store_refresh_live_state "$session_key" >/dev/null 2>&1 || true
        json=$(session_store_read "$session_key") || continue
        status=$(printf '%s' "$json" | jq -r '.status // "running"')

        if [ "$include_stopped" != "1" ] && [ "$status" != "running" ]; then
            continue
        fi

        if [ "$first" -eq 0 ]; then
            printf ','
        fi
        first=0
        printf '%s' "$json"
    done < <(session_store_list_keys)
    printf ']\n'
}

session_store_describe() {
    local session_key="${1:?session key required}"
    local json

    json=$(session_store_read "$session_key") || return 1
    printf '%s\n' "$(printf '%s' "$json" | jq -r '[.session_key, .project_label, .controller, .notify_mode, (.attached_clients|tostring), .cwd] | @tsv')"
}

session_store_next_tmux_session() {
    local base_session="${1:?base session required}"
    local candidate="$base_session"
    local index=2

    while session_store_tmux_exists "$candidate"; do
        candidate="${base_session}-${index}"
        index=$((index + 1))
    done

    printf '%s\n' "$candidate"
}

session_store_resolve_selector() {
    local selector="${1:-}"
    local session_key
    local json
    local project_label
    local tmux_session
    local cwd
    local cwd_base
    local label_matches=()
    local base_matches=()

    [ -n "$selector" ] || return 1

    while IFS= read -r session_key; do
        [ -n "$session_key" ] || continue
        session_store_refresh_live_state "$session_key" >/dev/null 2>&1 || true
        json=$(session_store_read "$session_key") || continue

        project_label=$(printf '%s' "$json" | jq -r '.project_label // ""')
        tmux_session=$(printf '%s' "$json" | jq -r '.tmux_session // ""')
        cwd=$(printf '%s' "$json" | jq -r '.cwd // ""')
        cwd_base=""
        if [ -n "$cwd" ]; then
            cwd_base=$(basename "$cwd" 2>/dev/null || true)
        fi

        if [ "$session_key" = "$selector" ] || [ "$tmux_session" = "$selector" ] || [ "$cwd" = "$selector" ]; then
            printf '%s\n' "$session_key"
            return 0
        fi

        if [ "$project_label" = "$selector" ]; then
            label_matches+=("$session_key")
        fi

        if [ -n "$cwd_base" ] && [ "$cwd_base" = "$selector" ]; then
            base_matches+=("$session_key")
        fi
    done < <(session_store_list_keys)

    if [ "${#label_matches[@]}" -eq 1 ]; then
        printf '%s\n' "${label_matches[0]}"
        return 0
    fi

    if [ "${#base_matches[@]}" -eq 1 ]; then
        printf '%s\n' "${base_matches[0]}"
        return 0
    fi

    if [ "${#label_matches[@]}" -gt 1 ]; then
        echo "Multiple sessions match label '$selector':" >&2
        for session_key in "${label_matches[@]}"; do
            session_store_describe "$session_key" >&2 || true
        done
        return 2
    fi

    if [ "${#base_matches[@]}" -gt 1 ]; then
        echo "Multiple sessions match cwd basename '$selector':" >&2
        for session_key in "${base_matches[@]}"; do
            session_store_describe "$session_key" >&2 || true
        done
        return 2
    fi

    return 1
}

session_store_resolve_selector_checked() {
    local selector="${1:-}"
    local session_key
    local rc
    local errexit_was_set=0

    case $- in
        *e*) errexit_was_set=1 ;;
    esac

    set +e
    session_key="$(session_store_resolve_selector "$selector")"
    rc=$?
    if [ "$errexit_was_set" -eq 1 ]; then
        set -e
    fi

    if [ "$rc" -eq 0 ]; then
        printf '%s\n' "$session_key"
        return 0
    fi

    case "$rc" in
        2)
            echo "❌ Multiple managed Claude sessions match: $selector" >&2
            ;;
        *)
            echo "❌ No managed Claude session matches: $selector" >&2
            ;;
    esac

    return "$rc"
}
