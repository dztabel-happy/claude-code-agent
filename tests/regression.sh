#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

assert_eq() {
    local expected="${1:?expected required}"
    local actual="${2:?actual required}"
    local message="${3:-assert_eq failed}"

    if [ "$expected" != "$actual" ]; then
        echo "ASSERT_EQ failed: $message" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        exit 1
    fi
}

assert_contains() {
    local needle="${1:?needle required}"
    local haystack_file="${2:?haystack file required}"

    if ! grep -Fq -- "$needle" "$haystack_file"; then
        echo "ASSERT_CONTAINS failed: '$needle' not found in $haystack_file" >&2
        exit 1
    fi
}

assert_not_contains() {
    local needle="${1:?needle required}"
    local haystack_file="${2:?haystack file required}"

    if grep -Fq -- "$needle" "$haystack_file"; then
        echo "ASSERT_NOT_CONTAINS failed: '$needle' unexpectedly found in $haystack_file" >&2
        exit 1
    fi
}

assert_file_mode() {
    local expected="${1:?expected mode required}"
    local path="${2:?path required}"
    local actual

    if actual="$(stat -f '%Lp' "$path" 2>/dev/null)"; then
        :
    else
        actual="$(stat -c '%a' "$path")"
    fi

    if [ "$expected" != "$actual" ]; then
        echo "ASSERT_FILE_MODE failed: $path" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        exit 1
    fi
}

test_takeover_preserves_route() {
    local runtime_dir tmux_session

    runtime_dir="$(mktemp -d)"
    tmux_session="claude-agent-regression-$$-route"

    tmux new-session -d -s "$tmux_session" 'sleep 60'
    mkdir -p "$runtime_dir/sessions"

    jq -n \
        --arg session_key "route-test" \
        --arg project_label "demo" \
        --arg cwd "/tmp/demo" \
        --arg tmux_session "$tmux_session" \
        '{
            session_key: $session_key,
            project_label: $project_label,
            cwd: $cwd,
            tmux_session: $tmux_session,
            launch_mode: "interactive",
            controller: "local",
            notify_mode: "off",
            status: "running",
            managed_by: "local",
            attached_clients: 0,
            tmux_exists: true,
            chat_id: "123",
            channel: "discord",
            agent_name: "ops-bot"
        }' > "$runtime_dir/sessions/route-test.json"

    OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        bash "$ROOT_DIR/runtime/takeover.sh" --no-wake route-test >/dev/null

    assert_eq "discord" "$(jq -r '.channel' "$runtime_dir/sessions/route-test.json")" "takeover should preserve channel"
    assert_eq "ops-bot" "$(jq -r '.agent_name' "$runtime_dir/sessions/route-test.json")" "takeover should preserve agent name"
    assert_eq "123" "$(jq -r '.chat_id' "$runtime_dir/sessions/route-test.json")" "takeover should preserve chat id"
    assert_eq "openclaw" "$(jq -r '.controller' "$runtime_dir/sessions/route-test.json")" "takeover should switch controller"
    assert_eq "attention" "$(jq -r '.notify_mode' "$runtime_dir/sessions/route-test.json")" "takeover default notify_mode should stay attention"

    tmux kill-session -t "$tmux_session" >/dev/null 2>&1 || true
    rm -rf "$runtime_dir"
}

test_selector_ambiguity_reports_multiple() {
    local runtime_dir stdout_file stderr_file rc

    runtime_dir="$(mktemp -d)"
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"
    mkdir -p "$runtime_dir/sessions"

    jq -n '{session_key:"a1", project_label:"same", cwd:"/tmp/one", tmux_session:"same-1", status:"running"}' > "$runtime_dir/sessions/a1.json"
    jq -n '{session_key:"a2", project_label:"same", cwd:"/tmp/two", tmux_session:"same-2", status:"running"}' > "$runtime_dir/sessions/a2.json"

    set +e
    OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        bash "$ROOT_DIR/runtime/session_status.sh" same >"$stdout_file" 2>"$stderr_file"
    rc=$?
    set -e

    assert_eq "2" "$rc" "ambiguous selector should exit 2"
    assert_contains "Multiple sessions match label 'same':" "$stderr_file"
    assert_contains "❌ Multiple managed Claude sessions match: same" "$stderr_file"
    assert_not_contains "No managed Claude session matches" "$stderr_file"
    assert_eq "0" "$(wc -c <"$stdout_file" | tr -d ' ')" "ambiguous selector should not print stdout"

    rm -f "$stdout_file" "$stderr_file"
    rm -rf "$runtime_dir"
}

test_hook_logs_are_private() {
    local runtime_dir log_file

    runtime_dir="$(mktemp -d)"
    log_file="$(
        OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
            PATH="/usr/bin:/bin" bash -lc "source '$ROOT_DIR/hooks/hook_common.sh'; hook_prepare_log_file stop"
    )"

    case "$log_file" in
        "$runtime_dir"/logs/*) ;;
        *)
            echo "ASSERT failed: log file not created under runtime dir: $log_file" >&2
            exit 1
            ;;
    esac

    assert_file_mode "600" "$log_file"

    rm -rf "$runtime_dir"
}

test_hook_wake_logs_real_result() {
    local fake_bin_dir log_file runtime_dir

    fake_bin_dir="$(mktemp -d)"
    runtime_dir="$(mktemp -d)"
    log_file="$(mktemp)"

    printf '%s\n' '#!/bin/bash' 'exit 1' > "$fake_bin_dir/openclaw"
    chmod +x "$fake_bin_dir/openclaw"

    OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        PATH="$fake_bin_dir:/usr/bin:/bin" bash -lc \
        "source '$ROOT_DIR/hooks/hook_common.sh'; hook_wake_openclaw '$log_file' wake-result-test openclaw main telegram 'wake message'"

    sleep 1

    assert_contains "Agent wake queued" "$log_file"
    assert_contains "Agent wake failed (exit=1)" "$log_file"
    assert_not_contains "Agent wake fired" "$log_file"

    rm -f "$log_file"
    rm -rf "$fake_bin_dir" "$runtime_dir"
}

test_hook_wake_deduplicates_by_session() {
    local fake_bin_dir log_file runtime_dir count_file

    fake_bin_dir="$(mktemp -d)"
    runtime_dir="$(mktemp -d)"
    log_file="$(mktemp)"
    count_file="$(mktemp)"

    printf '%s\n' \
        '#!/bin/bash' \
        "echo invoked >> '$count_file'" \
        'sleep 1' \
        'exit 0' > "$fake_bin_dir/openclaw"
    chmod +x "$fake_bin_dir/openclaw"

    OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        PATH="$fake_bin_dir:/usr/bin:/bin" bash -lc \
        "source '$ROOT_DIR/hooks/hook_common.sh'; hook_wake_openclaw '$log_file' wake-dedupe-test openclaw main telegram 'wake 1'; hook_wake_openclaw '$log_file' wake-dedupe-test openclaw main telegram 'wake 2' || true"

    sleep 2

    assert_eq "1" "$(wc -l <"$count_file" | tr -d ' ')" "duplicate wake should only invoke openclaw once"
    assert_contains "session already waking" "$log_file"

    rm -f "$log_file" "$count_file"
    rm -rf "$fake_bin_dir" "$runtime_dir"
}

test_hook_wake_deduplicates_across_processes() {
    local fake_bin_dir log_file runtime_dir invocation_dir i

    fake_bin_dir="$(mktemp -d)"
    runtime_dir="$(mktemp -d)"
    log_file="$(mktemp)"
    invocation_dir="$(mktemp -d)"

    printf '%s\n' \
        '#!/bin/bash' \
        "touch '$invocation_dir'/\"\$\$-\$RANDOM\"" \
        'exit 0' > "$fake_bin_dir/openclaw"
    chmod +x "$fake_bin_dir/openclaw"

    for i in $(seq 1 50); do
        OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
            PATH="$fake_bin_dir:/usr/bin:/bin" \
            bash -lc "source '$ROOT_DIR/hooks/hook_common.sh'; hook_wake_openclaw '$log_file' race-test openclaw main telegram 'wake $i' || true" &
    done
    wait
    sleep 2

    assert_eq "1" "$(find "$invocation_dir" -type f | wc -l | tr -d ' ')" "concurrent hooks should invoke openclaw once"
    assert_not_contains "No such file or directory" "$log_file"

    rm -f "$log_file"
    rm -rf "$fake_bin_dir" "$runtime_dir" "$invocation_dir"
}

test_hook_wake_uses_explicit_session_id() {
    local fake_bin_dir log_file runtime_dir args_file

    fake_bin_dir="$(mktemp -d)"
    runtime_dir="$(mktemp -d)"
    log_file="$(mktemp)"
    args_file="$(mktemp)"

    printf '%s\n' \
        '#!/bin/bash' \
        "printf '%s\n' \"\$*\" > '$args_file'" \
        'exit 0' > "$fake_bin_dir/openclaw"
    chmod +x "$fake_bin_dir/openclaw"

    OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        PATH="$fake_bin_dir:/usr/bin:/bin" bash -lc \
        "source '$ROOT_DIR/hooks/hook_common.sh'; hook_wake_openclaw '$log_file' route-check openclaw main telegram 'wake route'" >/dev/null

    sleep 2

    assert_contains "--session-id claude-code-agent-route-check" "$args_file"
    assert_contains "--agent main" "$args_file"

    rm -f "$log_file" "$args_file"
    rm -rf "$fake_bin_dir" "$runtime_dir"
}

test_task_completed_gate_blocks() {
    local runtime_dir project_dir stderr_file rc

    runtime_dir="$(mktemp -d)"
    project_dir="$(mktemp -d)"
    stderr_file="$(mktemp)"
    mkdir -p "$runtime_dir/sessions" "$project_dir/.openclaw"

    printf '%s\n' '#!/bin/bash' 'echo "tests failed for $OPENCLAW_TASK_SUBJECT"' 'exit 1' > "$project_dir/.openclaw/task_completed_gate.sh"
    chmod +x "$project_dir/.openclaw/task_completed_gate.sh"

    jq -n \
        --arg cwd "$project_dir" \
        '{
            session_key: "task-test",
            project_label: "demo",
            cwd: $cwd,
            tmux_session: "",
            launch_mode: "print",
            controller: "local",
            notify_mode: "off",
            status: "running",
            managed_by: "openclaw",
            attached_clients: 0,
            tmux_exists: false,
            chat_id: "",
            channel: "telegram",
            agent_name: "main"
        }' > "$runtime_dir/sessions/task-test.json"

    set +e
    printf '%s' '{"session_id":"sess-1","cwd":"'"$project_dir"'","task_id":"T-7","task_subject":"auth tests","teammate_name":"qa","team_name":"team-a"}' | \
        OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        OPENCLAW_HANDOFF_CAPABLE=1 \
        OPENCLAW_SESSION_KEY=task-test \
        OPENCLAW_TASK_COMPLETED_GATE=.openclaw/task_completed_gate.sh \
        bash "$ROOT_DIR/hooks/on_task_completed.sh" >/dev/null 2>"$stderr_file"
    rc=$?
    set -e

    assert_eq "2" "$rc" "quality gate should block task completion"
    assert_contains "tests failed for auth tests" "$stderr_file"
    assert_eq "task_completed_blocked" "$(jq -r '.last_event' "$runtime_dir/sessions/task-test.json")" "blocked gate should update last_event"

    rm -f "$stderr_file"
    rm -rf "$runtime_dir" "$project_dir"
}

test_task_completed_gate_is_opt_in() {
    local runtime_dir project_dir stderr_file rc

    runtime_dir="$(mktemp -d)"
    project_dir="$(mktemp -d)"
    stderr_file="$(mktemp)"
    mkdir -p "$runtime_dir/sessions" "$project_dir/.openclaw"

    printf '%s\n' '#!/bin/bash' 'echo "should not run"' 'exit 1' > "$project_dir/.openclaw/task_completed_gate.sh"
    chmod +x "$project_dir/.openclaw/task_completed_gate.sh"

    jq -n \
        --arg cwd "$project_dir" \
        '{
            session_key: "task-opt-in-test",
            project_label: "demo",
            cwd: $cwd,
            tmux_session: "",
            launch_mode: "print",
            controller: "local",
            notify_mode: "off",
            status: "running",
            managed_by: "openclaw",
            attached_clients: 0,
            tmux_exists: false,
            chat_id: "",
            channel: "telegram",
            agent_name: "main"
        }' > "$runtime_dir/sessions/task-opt-in-test.json"

    set +e
    printf '%s' '{"session_id":"sess-2","cwd":"'"$project_dir"'","task_id":"T-8","task_subject":"lint","teammate_name":"qa","team_name":"team-b"}' | \
        OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        OPENCLAW_HANDOFF_CAPABLE=1 \
        OPENCLAW_SESSION_KEY=task-opt-in-test \
        bash "$ROOT_DIR/hooks/on_task_completed.sh" >/dev/null 2>"$stderr_file"
    rc=$?
    set -e

    assert_eq "0" "$rc" "repo-local gate should not run unless explicitly enabled"
    assert_eq "task_completed" "$(jq -r '.last_event' "$runtime_dir/sessions/task-opt-in-test.json")" "task should pass without explicit gate opt-in"
    assert_eq "0" "$(wc -c <"$stderr_file" | tr -d ' ')" "stdout/stderr should stay empty without gate"

    rm -f "$stderr_file"
    rm -rf "$runtime_dir" "$project_dir"
}

test_run_claude_requires_print_mode() {
    local runtime_dir stderr_file stdout_file rc

    runtime_dir="$(mktemp -d)"
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"

    set +e
    OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        bash "$ROOT_DIR/hooks/run_claude.sh" "$ROOT_DIR" --model sonnet >"$stdout_file" 2>"$stderr_file"
    rc=$?
    set -e

    assert_eq "1" "$rc" "run_claude.sh should reject non-print mode invocations"
    assert_contains "requires Claude print mode" "$stdout_file"

    rm -f "$stdout_file" "$stderr_file"
    rm -rf "$runtime_dir"
}

test_run_claude_injects_managed_settings_overlay() {
    local runtime_dir fake_bin_dir capture_file workdir stdout_file stderr_file rc

    runtime_dir="$(mktemp -d)"
    fake_bin_dir="$(mktemp -d)"
    capture_file="$(mktemp)"
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"
    workdir="$(mktemp -d)"

    cat > "$fake_bin_dir/claude" <<EOF
#!/bin/bash
set -euo pipefail
SETTINGS_PATH=""
ARGS=()
while [ "\$#" -gt 0 ]; do
    case "\$1" in
        --settings)
            SETTINGS_PATH="\$2"
            shift 2
            ;;
        *)
            ARGS+=("\$1")
            shift
            ;;
    esac
done

printf 'settings=%s\n' "\$SETTINGS_PATH" > "$capture_file"
printf 'args=%s\n' "\${ARGS[*]}" >> "$capture_file"
printf 'session=%s\n' "\${OPENCLAW_OPENCLAW_SESSION_ID:-}" >> "$capture_file"
SETTINGS_PATH_FOR_CAPTURE="\$SETTINGS_PATH" CAPTURE_PATH_FOR_CAPTURE="$capture_file" python3 - <<'PY'
import json, os, pathlib
settings_path = pathlib.Path(os.environ["SETTINGS_PATH_FOR_CAPTURE"])
capture_path = pathlib.Path(os.environ["CAPTURE_PATH_FOR_CAPTURE"])
data = json.loads(settings_path.read_text())
capture_path.open("a").write("has_stop=%s\n" % ("Stop" in data.get("hooks", {})))
capture_path.open("a").write("has_agent_teams=%s\n" % (data.get("env", {}).get("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS") == "1"))
capture_path.open("a").write("custom_env=%s\n" % data.get("env", {}).get("TEST_ENV"))
PY
exit 0
EOF
    chmod +x "$fake_bin_dir/claude"

    set +e
    OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        PATH="$fake_bin_dir:$PATH" \
        bash -c "bash '$ROOT_DIR/hooks/run_claude.sh' '$workdir' -p --settings '{\"env\":{\"TEST_ENV\":\"present\"}}' 'Reply with exactly: ok'" >"$stdout_file" 2>"$stderr_file"
    rc=$?
    set -e

    assert_eq "0" "$rc" "run_claude should succeed with fake claude"
    assert_contains "settings=" "$capture_file"
    assert_contains "args=-p Reply with exactly: ok" "$capture_file"
    assert_contains "session=claude-code-agent-" "$capture_file"
    assert_contains "has_stop=True" "$capture_file"
    assert_contains "has_agent_teams=True" "$capture_file"
    assert_contains "custom_env=present" "$capture_file"

    rm -f "$capture_file" "$stdout_file" "$stderr_file"
    rm -rf "$runtime_dir" "$fake_bin_dir" "$workdir"
}

main() {
    test_takeover_preserves_route
    test_selector_ambiguity_reports_multiple
    test_hook_logs_are_private
    test_hook_wake_logs_real_result
    test_hook_wake_deduplicates_by_session
    test_hook_wake_deduplicates_across_processes
    test_hook_wake_uses_explicit_session_id
    test_task_completed_gate_blocks
    test_task_completed_gate_is_opt_in
    test_run_claude_requires_print_mode
    test_run_claude_injects_managed_settings_overlay
    echo "All regression tests passed."
}

main "$@"
