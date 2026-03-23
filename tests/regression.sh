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

wait_for_contains() {
    local needle="${1:?needle required}"
    local haystack_file="${2:?haystack file required}"
    local attempts="${3:-50}"
    local delay="${4:-0.1}"
    local i

    for i in $(seq 1 "$attempts"); do
        if grep -Fq -- "$needle" "$haystack_file" 2>/dev/null; then
            return 0
        fi
        sleep "$delay"
    done

    echo "WAIT_FOR_CONTAINS failed: '$needle' not found in $haystack_file" >&2
    exit 1
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

test_selector_accepts_openclaw_session_id() {
    local runtime_dir stdout_file rc

    runtime_dir="$(mktemp -d)"
    stdout_file="$(mktemp)"
    mkdir -p "$runtime_dir/sessions"

    jq -n \
        --arg session_key "route-test" \
        --arg openclaw_session_id "claude-code-agent-route-test" \
        '{session_key: $session_key, project_label: "demo", cwd: "/tmp/demo", tmux_session: "demo-tmux", status: "running", openclaw_session_id: $openclaw_session_id}' \
        > "$runtime_dir/sessions/route-test.json"

    set +e
    OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        bash "$ROOT_DIR/runtime/session_status.sh" --json claude-code-agent-route-test >"$stdout_file"
    rc=$?
    set -e

    assert_eq "0" "$rc" "openclaw_session_id selector should resolve"
    assert_eq "route-test" "$(jq -r '.session_key' "$stdout_file")" "resolved session should match"

    rm -f "$stdout_file"
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

    wait_for_contains "Agent wake queued" "$log_file"
    wait_for_contains "Agent wake failed (exit=1)" "$log_file"
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

test_wrapper_help_outputs() {
    local tmp rc

    tmp="$(mktemp)"

    set +e
    bash "$ROOT_DIR/hooks/start_claude.sh" --help >"$tmp"
    rc=$?
    set -e
    assert_eq "0" "$rc" "start_claude --help should succeed"
    assert_contains "Start an interactive managed Claude Code session in tmux." "$tmp"
    assert_contains "--agent-teams" "$tmp"

    set +e
    bash "$ROOT_DIR/hooks/run_claude.sh" --help >"$tmp"
    rc=$?
    set -e
    assert_eq "0" "$rc" "run_claude --help should succeed"
    assert_contains "Run a one-shot managed Claude Code job in print mode." "$tmp"
    assert_contains "This wrapper requires Claude print mode" "$tmp"

    set +e
    bash "$ROOT_DIR/runtime/start_local_claude.sh" --help >"$tmp"
    rc=$?
    set -e
    assert_eq "0" "$rc" "start_local_claude --help should succeed"
    assert_contains "Start a managed Claude Code session under local control" "$tmp"
    assert_contains "runtime/takeover.sh later" "$tmp"

    set +e
    bash "$ROOT_DIR/runtime/takeover.sh" --help >"$tmp"
    rc=$?
    set -e
    assert_eq "0" "$rc" "takeover --help should succeed"
    assert_contains "Hand a managed Claude session over to OpenClaw." "$tmp"
    assert_contains "Selector resolution order:" "$tmp"

    set +e
    bash "$ROOT_DIR/hooks/stop_claude.sh" --help >"$tmp"
    rc=$?
    set -e
    assert_eq "0" "$rc" "stop_claude --help should succeed"
    assert_contains "Stop a managed Claude tmux session" "$tmp"

    set +e
    bash "$ROOT_DIR/runtime/reclaim.sh" --help >"$tmp"
    rc=$?
    set -e
    assert_eq "0" "$rc" "reclaim --help should succeed"
    assert_contains "Return a managed Claude session to local control." "$tmp"

    set +e
    bash "$ROOT_DIR/runtime/list_sessions.sh" --help >"$tmp"
    rc=$?
    set -e
    assert_eq "0" "$rc" "list_sessions --help should succeed"
    assert_contains "List managed Claude sessions from the local runtime store." "$tmp"

    set +e
    bash "$ROOT_DIR/runtime/session_status.sh" --help >"$tmp"
    rc=$?
    set -e
    assert_eq "0" "$rc" "session_status --help should succeed"
    assert_contains "Show details for one managed Claude session." "$tmp"

    set +e
    bash "$ROOT_DIR/runtime/control_session.sh" --help >"$tmp"
    rc=$?
    set -e
    assert_eq "0" "$rc" "control_session --help should succeed"
    assert_contains "Control managed Claude sessions through one entrypoint." "$tmp"
    assert_contains "Auto-selection order when selector is omitted:" "$tmp"

    rm -f "$tmp"
}

test_control_session_auto_reclaim_prefers_single_openclaw_session() {
    local runtime_dir tmux_openclaw tmux_local

    runtime_dir="$(mktemp -d)"
    tmux_openclaw="claude-agent-regression-$$-ctrl-openclaw"
    tmux_local="claude-agent-regression-$$-ctrl-local"

    tmux new-session -d -s "$tmux_openclaw" 'sleep 60'
    tmux new-session -d -s "$tmux_local" 'sleep 60'
    mkdir -p "$runtime_dir/sessions"

    jq -n \
        --arg session_key "openclaw-test" \
        --arg project_label "demo-openclaw" \
        --arg cwd "/tmp/demo-openclaw" \
        --arg tmux_session "$tmux_openclaw" \
        '{
            session_key: $session_key,
            project_label: $project_label,
            cwd: $cwd,
            tmux_session: $tmux_session,
            launch_mode: "interactive",
            controller: "openclaw",
            notify_mode: "attention",
            permission_policy: "safe",
            status: "running",
            managed_by: "openclaw",
            attached_clients: 0,
            tmux_exists: true,
            chat_id: "",
            channel: "telegram",
            agent_name: "main"
        }' > "$runtime_dir/sessions/openclaw-test.json"

    jq -n \
        --arg session_key "local-test" \
        --arg project_label "demo-local" \
        --arg cwd "/tmp/demo-local" \
        --arg tmux_session "$tmux_local" \
        '{
            session_key: $session_key,
            project_label: $project_label,
            cwd: $cwd,
            tmux_session: $tmux_session,
            launch_mode: "interactive",
            controller: "local",
            notify_mode: "off",
            permission_policy: "off",
            status: "running",
            managed_by: "local",
            attached_clients: 0,
            tmux_exists: true,
            chat_id: "",
            channel: "telegram",
            agent_name: "main"
        }' > "$runtime_dir/sessions/local-test.json"

    OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        bash "$ROOT_DIR/runtime/control_session.sh" reclaim >/dev/null

    assert_eq "local" "$(jq -r '.controller' "$runtime_dir/sessions/openclaw-test.json")" "control_session reclaim should target the single openclaw-controlled session"
    assert_eq "local" "$(jq -r '.controller' "$runtime_dir/sessions/local-test.json")" "control_session reclaim should not touch unrelated local session"

    tmux kill-session -t "$tmux_openclaw" >/dev/null 2>&1 || true
    tmux kill-session -t "$tmux_local" >/dev/null 2>&1 || true
    rm -rf "$runtime_dir"
}

test_control_session_reports_ambiguity_without_selector() {
    local runtime_dir tmux_one tmux_two stdout_file stderr_file rc

    runtime_dir="$(mktemp -d)"
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"
    tmux_one="claude-agent-regression-$$-ctrl-amb-1"
    tmux_two="claude-agent-regression-$$-ctrl-amb-2"

    tmux new-session -d -s "$tmux_one" 'sleep 60'
    tmux new-session -d -s "$tmux_two" 'sleep 60'
    mkdir -p "$runtime_dir/sessions"

    jq -n \
        --arg session_key "local-a" \
        --arg project_label "demo-a" \
        --arg cwd "/tmp/demo-a" \
        --arg tmux_session "$tmux_one" \
        '{session_key: $session_key, project_label: $project_label, cwd: $cwd, tmux_session: $tmux_session, launch_mode: "interactive", controller: "local", notify_mode: "off", status: "running", managed_by: "local", attached_clients: 0, tmux_exists: true}' \
        > "$runtime_dir/sessions/local-a.json"

    jq -n \
        --arg session_key "local-b" \
        --arg project_label "demo-b" \
        --arg cwd "/tmp/demo-b" \
        --arg tmux_session "$tmux_two" \
        '{session_key: $session_key, project_label: $project_label, cwd: $cwd, tmux_session: $tmux_session, launch_mode: "interactive", controller: "local", notify_mode: "off", status: "running", managed_by: "local", attached_clients: 0, tmux_exists: true}' \
        > "$runtime_dir/sessions/local-b.json"

    set +e
    OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        bash "$ROOT_DIR/runtime/control_session.sh" takeover --no-wake >"$stdout_file" 2>"$stderr_file"
    rc=$?
    set -e

    assert_eq "2" "$rc" "control_session should refuse ambiguous auto-selection"
    assert_contains "Multiple running managed Claude sessions are eligible for 'takeover'." "$stderr_file"
    assert_contains "Running managed Claude sessions:" "$stderr_file"
    assert_eq "0" "$(wc -c <"$stdout_file" | tr -d ' ')" "ambiguous control_session takeover should not print stdout"

    tmux kill-session -t "$tmux_one" >/dev/null 2>&1 || true
    tmux kill-session -t "$tmux_two" >/dev/null 2>&1 || true
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
capture_path.open("a").write("has_permission_request=%s\n" % ("PermissionRequest" in data.get("hooks", {})))
capture_path.open("a").write("has_teammate_idle=%s\n" % ("TeammateIdle" in data.get("hooks", {})))
capture_path.open("a").write("has_task_completed=%s\n" % ("TaskCompleted" in data.get("hooks", {})))
capture_path.open("a").write("permission_request_matcher=%s\n" % data.get("hooks", {}).get("PermissionRequest", [{}])[0].get("matcher"))
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
    assert_contains "has_permission_request=True" "$capture_file"
    assert_contains "has_teammate_idle=False" "$capture_file"
    assert_contains "has_task_completed=False" "$capture_file"
    assert_contains "permission_request_matcher=Bash" "$capture_file"
    assert_contains "has_agent_teams=False" "$capture_file"
    assert_contains "custom_env=present" "$capture_file"

    rm -f "$capture_file" "$stdout_file" "$stderr_file"
    rm -rf "$runtime_dir" "$fake_bin_dir" "$workdir"
}

test_run_claude_opt_in_agent_teams_overlay() {
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
while [ "\$#" -gt 0 ]; do
    case "\$1" in
        --settings)
            SETTINGS_PATH="\$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

SETTINGS_PATH_FOR_CAPTURE="\$SETTINGS_PATH" CAPTURE_PATH_FOR_CAPTURE="$capture_file" python3 - <<'PY'
import json, os, pathlib
settings_path = pathlib.Path(os.environ["SETTINGS_PATH_FOR_CAPTURE"])
capture_path = pathlib.Path(os.environ["CAPTURE_PATH_FOR_CAPTURE"])
data = json.loads(settings_path.read_text())
capture_path.open("w").write("has_agent_teams=%s\n" % (data.get("env", {}).get("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS") == "1"))
capture_path.open("a").write("has_teammate_idle=%s\n" % ("TeammateIdle" in data.get("hooks", {})))
capture_path.open("a").write("has_task_completed=%s\n" % ("TaskCompleted" in data.get("hooks", {})))
PY
exit 0
EOF
    chmod +x "$fake_bin_dir/claude"

    set +e
    OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        PATH="$fake_bin_dir:$PATH" \
        bash -c "bash '$ROOT_DIR/hooks/run_claude.sh' '$workdir' --agent-teams -p 'Reply with exactly: ok'" >"$stdout_file" 2>"$stderr_file"
    rc=$?
    set -e

    assert_eq "0" "$rc" "run_claude should support explicit Agent Teams opt-in"
    assert_contains "has_agent_teams=True" "$capture_file"
    assert_contains "has_teammate_idle=True" "$capture_file"
    assert_contains "has_task_completed=True" "$capture_file"

    rm -f "$capture_file" "$stdout_file" "$stderr_file"
    rm -rf "$runtime_dir" "$fake_bin_dir" "$workdir"
}

test_takeover_enables_safe_permission_policy() {
    local runtime_dir tmux_session

    runtime_dir="$(mktemp -d)"
    tmux_session="claude-agent-regression-$$-perm"

    tmux new-session -d -s "$tmux_session" 'sleep 60'
    mkdir -p "$runtime_dir/sessions"

    jq -n \
        --arg session_key "perm-test" \
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
            permission_policy: "off",
            status: "running",
            managed_by: "local",
            attached_clients: 0,
            tmux_exists: true,
            chat_id: "",
            channel: "telegram",
            agent_name: "main"
        }' > "$runtime_dir/sessions/perm-test.json"

    OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        bash "$ROOT_DIR/runtime/takeover.sh" --no-wake perm-test >/dev/null

    assert_eq "safe" "$(jq -r '.permission_policy' "$runtime_dir/sessions/perm-test.json")" "takeover should enable safe permission policy"

    tmux kill-session -t "$tmux_session" >/dev/null 2>&1 || true
    rm -rf "$runtime_dir"
}

test_reclaim_disables_permission_policy() {
    local runtime_dir tmux_session

    runtime_dir="$(mktemp -d)"
    tmux_session="claude-agent-regression-$$-reclaim"

    tmux new-session -d -s "$tmux_session" 'sleep 60'
    mkdir -p "$runtime_dir/sessions"

    jq -n \
        --arg session_key "reclaim-test" \
        --arg project_label "demo" \
        --arg cwd "/tmp/demo" \
        --arg tmux_session "$tmux_session" \
        '{
            session_key: $session_key,
            project_label: $project_label,
            cwd: $cwd,
            tmux_session: $tmux_session,
            launch_mode: "interactive",
            controller: "openclaw",
            notify_mode: "attention",
            permission_policy: "safe",
            status: "running",
            managed_by: "openclaw",
            attached_clients: 0,
            tmux_exists: true,
            chat_id: "",
            channel: "telegram",
            agent_name: "main"
        }' > "$runtime_dir/sessions/reclaim-test.json"

    OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        bash "$ROOT_DIR/runtime/reclaim.sh" reclaim-test >/dev/null

    assert_eq "off" "$(jq -r '.permission_policy' "$runtime_dir/sessions/reclaim-test.json")" "reclaim should disable permission policy"

    tmux kill-session -t "$tmux_session" >/dev/null 2>&1 || true
    rm -rf "$runtime_dir"
}

test_permission_request_auto_allows_safe_bash() {
    local runtime_dir stdout_file

    runtime_dir="$(mktemp -d)"
    stdout_file="$(mktemp)"
    mkdir -p "$runtime_dir/sessions"

    jq -n \
        '{
            session_key: "perm-allow",
            project_label: "demo",
            cwd: "/tmp/demo",
            tmux_session: "claude-demo",
            launch_mode: "interactive",
            controller: "openclaw",
            notify_mode: "attention",
            permission_policy: "safe",
            status: "running",
            managed_by: "openclaw",
            attached_clients: 0,
            tmux_exists: true,
            chat_id: "",
            channel: "telegram",
            agent_name: "main"
        }' > "$runtime_dir/sessions/perm-allow.json"

    printf '%s' '{"session_id":"sess-safe","cwd":"/tmp/demo","permission_mode":"default","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"git status --short","description":"Inspect working tree"}}' | \
        OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        OPENCLAW_HANDOFF_CAPABLE=1 \
        OPENCLAW_SESSION_KEY=perm-allow \
        bash "$ROOT_DIR/hooks/on_permission_request.sh" >"$stdout_file"

    assert_eq "allow" "$(jq -r '.hookSpecificOutput.decision.behavior' "$stdout_file")" "safe bash should be auto-allowed"
    assert_eq "session" "$(jq -r '.hookSpecificOutput.decision.updatedPermissions[0].destination' "$stdout_file")" "allow should be session-scoped"
    assert_eq "git status --short" "$(jq -r '.hookSpecificOutput.decision.updatedPermissions[0].rules[0].ruleContent' "$stdout_file")" "exact command should be cached"
    assert_eq "auto_allow" "$(jq -r '.last_permission_decision' "$runtime_dir/sessions/perm-allow.json")" "session metadata should record auto allow"

    rm -f "$stdout_file"
    rm -rf "$runtime_dir"
}

test_permission_request_auto_denies_dangerous_bash() {
    local runtime_dir stdout_file fake_bin_dir args_file

    runtime_dir="$(mktemp -d)"
    stdout_file="$(mktemp)"
    fake_bin_dir="$(mktemp -d)"
    args_file="$(mktemp)"
    mkdir -p "$runtime_dir/sessions"

    printf '%s\n' \
        '#!/bin/bash' \
        "printf '%s\n' \"\$*\" > '$args_file'" \
        'exit 0' > "$fake_bin_dir/openclaw"
    chmod +x "$fake_bin_dir/openclaw"

    jq -n \
        '{
            session_key: "perm-deny",
            project_label: "demo",
            cwd: "/tmp/demo",
            tmux_session: "claude-demo",
            launch_mode: "interactive",
            controller: "openclaw",
            notify_mode: "attention",
            permission_policy: "safe",
            status: "running",
            managed_by: "openclaw",
            attached_clients: 0,
            tmux_exists: true,
            chat_id: "",
            channel: "telegram",
            agent_name: "main"
        }' > "$runtime_dir/sessions/perm-deny.json"

    printf '%s' '{"session_id":"sess-danger","cwd":"/tmp/demo","permission_mode":"default","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf node_modules","description":"Remove dependencies"}}' | \
        OPENCLAW_CLAUDE_RUNTIME_DIR="$runtime_dir" \
        OPENCLAW_HANDOFF_CAPABLE=1 \
        OPENCLAW_SESSION_KEY=perm-deny \
        PATH="$fake_bin_dir:/usr/bin:/bin" \
        bash "$ROOT_DIR/hooks/on_permission_request.sh" >"$stdout_file"

    sleep 2

    assert_eq "deny" "$(jq -r '.hookSpecificOutput.decision.behavior' "$stdout_file")" "dangerous bash should be auto-denied"
    assert_contains "--session-id claude-code-agent-perm-deny" "$args_file"
    assert_eq "auto_deny" "$(jq -r '.last_permission_decision' "$runtime_dir/sessions/perm-deny.json")" "session metadata should record auto deny"

    rm -f "$stdout_file" "$args_file"
    rm -rf "$runtime_dir" "$fake_bin_dir"
}

main() {
    test_takeover_preserves_route
    test_takeover_enables_safe_permission_policy
    test_reclaim_disables_permission_policy
    test_selector_ambiguity_reports_multiple
    test_selector_accepts_openclaw_session_id
    test_hook_logs_are_private
    test_hook_wake_logs_real_result
    test_hook_wake_deduplicates_by_session
    test_hook_wake_deduplicates_across_processes
    test_hook_wake_uses_explicit_session_id
    test_task_completed_gate_blocks
    test_task_completed_gate_is_opt_in
    test_wrapper_help_outputs
    test_control_session_auto_reclaim_prefers_single_openclaw_session
    test_control_session_reports_ambiguity_without_selector
    test_run_claude_requires_print_mode
    test_run_claude_injects_managed_settings_overlay
    test_run_claude_opt_in_agent_teams_overlay
    test_permission_request_auto_allows_safe_bash
    test_permission_request_auto_denies_dangerous_bash
    echo "All regression tests passed."
}

main "$@"
