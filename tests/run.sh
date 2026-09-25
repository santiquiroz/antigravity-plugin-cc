#!/usr/bin/env bash
# Hermetic tests: fake agy, temporary HOME, no network, the real ~/.gemini is never read.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FORWARD="$ROOT/scripts/agy-forward.sh"
FAKE_AGY="$ROOT/tests/fake-agy.sh"
FIXTURES="$ROOT/tests/fixtures"
GIT_BIN=$(dirname "$(command -v git)")
FAILURES=0
DEFAULT_ABORT_AFTER=3
QUOTA_ERRORS_SLACK=5
DEFAULT_TEST_JOBS=6

fail() {
  printf '    FAIL: %s\n' "$*"
  return 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "$3: expected [$2], got [$1]"
}

assert_contains() {
  case $1 in
    *"$2"*) return 0 ;;
  esac
  fail "$3: [$2] not in [$1]"
}

assert_not_contains() {
  case $1 in
    *"$2"*) fail "$3: [$2] found in [$1]" ;;
  esac
}

install_fake_agy() {
  cp "$FAKE_AGY" "$HOME/bin/agy"
  chmod +x "$HOME/bin/agy"
}

new_sandbox() {
  HOME=$(mktemp -d)
  AGY_LOG_DIR="$HOME/.gemini/antigravity-cli/log"
  LOCALAPPDATA="$HOME/AppData/Local"
  FAKE_AGY_CALLS="$HOME/calls"
  FAKE_AGY_USAGE="$FIXTURES/usage-both-ok.txt"
  PATH="$HOME/bin:/usr/bin:/bin:$GIT_BIN"
  export HOME AGY_LOG_DIR LOCALAPPDATA FAKE_AGY_CALLS FAKE_AGY_USAGE PATH
  unset MSYS_NO_PATHCONV GIT_TERMINAL_PROMPT GIT_SSH_COMMAND AGY_QUOTA_ABORT_AFTER XDG_CONFIG_HOME
  isolate_git
  mkdir -p "$AGY_LOG_DIR" "$HOME/bin"
  install_fake_agy
  cp "$ROOT/docs/permissions.json" "$HOME/.gemini/antigravity-cli/settings.json"
  cd "$HOME" || return 1
}

isolate_git() {
  GIT_CEILING_DIRECTORIES=$(dirname "$HOME")
  GIT_CONFIG_NOSYSTEM=1
  GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=tester@example.invalid
  GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=tester@example.invalid
  export GIT_CEILING_DIRECTORIES GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
}

use_usage() {
  export FAKE_AGY_USAGE="$FIXTURES/usage-$1.txt"
}

call_count() {
  find "$FAKE_AGY_CALLS" -name '*.args' 2>/dev/null | wc -l | tr -d ' '
}

call_args() {
  local arg
  while IFS= read -r -d '' arg; do
    printf '%s\n' "$arg"
  done <"$FAKE_AGY_CALLS/$1.args"
}

call_has_arg() {
  local arg
  while IFS= read -r -d '' arg; do
    [ "$arg" = "$2" ] && return 0
  done <"$FAKE_AGY_CALLS/$1.args"
  return 1
}

call_arg_after() {
  local arg previous=""
  while IFS= read -r -d '' arg; do
    [ "$previous" = "$2" ] && { printf '%s' "$arg"; return 0; }
    previous=$arg
  done <"$FAKE_AGY_CALLS/$1.args"
  return 1
}

call_env() {
  grep "^$2=" "$FAKE_AGY_CALLS/$1.env" | cut -d = -f 2-
}

wait_for_file() {
  local path=$1 seconds=$2 i
  for i in $(seq "$seconds"); do
    [ -s "$path" ] && return 0
    sleep 1
  done
  return 1
}

prompt_of_length() {
  printf "%${1}s" "" | tr ' ' 'x'
}

write_foreign_log() {
  local path=$1 length=$2 i
  printf 'Print mode: starting (promptLength=%s, outputFormat=text)\n' "$length" >"$path"
  for i in 1 2 3 4 5; do
    printf 'RESOURCE_EXHAUSTED (code 429): Individual quota reached. Resets in 3h\n' >>"$path"
  done
}

write_foreign_logs_later() {
  sleep 1
  write_foreign_log "$AGY_LOG_DIR/cli-29990101_000001.log" 777
  write_foreign_log "$AGY_LOG_DIR/cli-29990101_000002.log" 778
}

write_old_logs() {
  local count=$1 i name
  for ((i = 1; i <= count; i++)); do
    printf -v name 'cli-19990101_%06d.log' "$i"
    printf 'Print mode: starting (promptLength=1, outputFormat=text)\n' >"$AGY_LOG_DIR/$name"
  done
}

own_quota_errors() {
  cat "$AGY_LOG_DIR"/cli-*_"$1".log | grep -c 'RESOURCE_EXHAUSTED'
}

# The fake agy writes one quota error per second of its own time, so their count measures how
# late the abort came independently of wall time, which a loaded machine stretches arbitrarily.
assert_aborted_early() {
  local rc=$1 pid=$2 errors
  assert_eq "$rc" 75 "exit code" || return 1
  errors=$(own_quota_errors "$pid")
  [ "$errors" -le $((DEFAULT_ABORT_AFTER + QUOTA_ERRORS_SLACK)) ] || fail "aborted after $errors quota errors" || return 1
  ! kill -0 "$pid" 2>/dev/null || fail "fake agy $pid still alive"
}

watch_quota_run() {
  bash "$FORWARD" watch "$FAKE_AGY" -p "$(prompt_of_length 500)" --model gemini-3.1-pro-high
}

test_quota_errors_abort_the_run_early() {
  local out rc
  export FAKE_AGY_MODE=quota FAKE_AGY_PIDFILE="$HOME/fake.pid"
  out=$(watch_quota_run)
  rc=$?
  assert_aborted_early "$rc" "$(cat "$FAKE_AGY_PIDFILE")" || return 1
  assert_contains "$out" "[antigravity-rescue] quota: RESOURCE_EXHAUSTED on gemini-3.1-pro-high (Individual quota reached, Resets in 10h)" "quota line"
}

test_quota_abort_stays_early_with_many_old_logs() {
  local rc
  export FAKE_AGY_MODE=quota FAKE_AGY_PIDFILE="$HOME/fake.pid"
  write_old_logs 200
  watch_quota_run >/dev/null
  rc=$?
  assert_aborted_early "$rc" "$(cat "$FAKE_AGY_PIDFILE")"
}

test_clean_run_passes_output_through() {
  local out rc
  export FAKE_AGY_MODE=done
  out=$(bash "$FORWARD" watch "$FAKE_AGY" -p "fix the build")
  rc=$?
  assert_eq "$rc" 0 "exit code" || return 1
  assert_eq "$out" "done" "stdout"
}

test_other_runs_quota_errors_are_ignored() {
  local prompt out rc writer
  prompt="fix the build"
  export FAKE_AGY_MODE=slow
  write_foreign_log "$AGY_LOG_DIR/cli-19990101_000000.log" "${#prompt}"
  write_foreign_logs_later &
  writer=$!
  out=$(bash "$FORWARD" watch "$FAKE_AGY" -p "$prompt")
  rc=$?
  wait "$writer"
  assert_eq "$rc" 0 "exit code" || return 1
  assert_eq "$out" "done" "stdout"
}

test_threshold_is_configurable() {
  local out rc
  export FAKE_AGY_MODE=quota-brief AGY_QUOTA_ABORT_AFTER=5
  out=$(bash "$FORWARD" watch "$FAKE_AGY" -p "fix the build")
  rc=$?
  assert_eq "$rc" 0 "exit code" || return 1
  assert_eq "$out" "done" "stdout"
}

test_run_that_already_finished_is_not_reported_as_quota() {
  local out rc
  export FAKE_AGY_MODE=quota-burst
  out=$(bash "$FORWARD" watch "$FAKE_AGY" -p "fix the build")
  rc=$?
  assert_eq "$rc" 0 "exit code" || return 1
  assert_eq "$out" "done" "stdout"
}

test_child_exit_code_is_preserved() {
  local rc
  export FAKE_AGY_MODE=fail
  bash "$FORWARD" watch "$FAKE_AGY" -p "fix the build" >/dev/null 2>&1
  rc=$?
  assert_eq "$rc" 3 "exit code"
}

test_terminating_the_forwarder_stops_agy() {
  local forwarder pid
  export FAKE_AGY_MODE=quota AGY_QUOTA_ABORT_AFTER=1000 FAKE_AGY_PIDFILE="$HOME/fake.pid"
  bash "$FORWARD" watch "$FAKE_AGY" -p "fix the build" >/dev/null 2>&1 &
  forwarder=$!
  wait_for_file "$FAKE_AGY_PIDFILE" 60 || fail "fake agy never started" || return 1
  pid=$(cat "$FAKE_AGY_PIDFILE")
  kill -TERM "$forwarder"
  wait "$forwarder"
  ! kill -0 "$pid" 2>/dev/null || fail "fake agy $pid still alive"
}

test_preflight_moves_to_claude_pool_when_gemini_is_empty() {
  local out rc
  use_usage gemini-empty
  out=$(bash "$FORWARD" preflight --effort high)
  rc=$?
  assert_eq "$rc" 0 "exit code" || return 1
  assert_contains "$out" "[antigravity-rescue] preflight: Gemini 0% (resets 2026-09-30 09:00); Claude/GPT 25% (resets 2026-10-01 14:30)" "gauges" || return 1
  assert_contains "$out" "[antigravity-rescue] Gemini pool at 0%, running on claude-sonnet-4-6 instead" "switch notice" || return 1
  assert_contains "$out" $'\nmodel: claude-sonnet-4-6\n' "model" || return 1
  assert_contains "$out" $'\neffort: ' "effort line" || return 1
  assert_not_contains "$out" "effort: high" "effort"
}

test_preflight_keeps_the_requested_model_when_its_pool_has_room() {
  local out rc
  use_usage both-ok
  out=$(bash "$FORWARD" preflight --model gemini-3.1-pro-high --effort high)
  rc=$?
  assert_eq "$rc" 0 "exit code" || return 1
  assert_not_contains "$out" "instead" "switch notice" || return 1
  assert_contains "$out" $'\nmodel: gemini-3.1-pro-high\neffort: high' "model and effort"
}

test_preflight_uses_the_default_model_pool() {
  local out
  use_usage claude-empty
  export FAKE_AGY_DEFAULT_MODEL=gpt-oss-120b-medium
  out=$(bash "$FORWARD" preflight)
  assert_contains "$out" "Claude/GPT pool at 0%, running on gemini-3.8-flash-low instead" "switch notice" || return 1
  assert_contains "$out" $'\nmodel: gemini-3.8-flash-low' "model"
}

test_preflight_switch_keeps_the_task_class() {
  local out
  use_usage gemini-empty
  out=$(bash "$FORWARD" preflight --model gemini-3.8-flash-medium)
  assert_contains "$out" $'\nmodel: gpt-oss-120b-medium' "mechanical" || return 1
  out=$(bash "$FORWARD" preflight --class hardest)
  assert_contains "$out" $'\nmodel: claude-opus-4-6-thinking' "hardest"
}

test_preflight_refuses_when_both_pools_are_exhausted() {
  local out rc n
  use_usage both-empty
  out=$(bash "$FORWARD" preflight --model claude-sonnet-4-6)
  rc=$?
  assert_eq "$rc" 69 "exit code" || return 1
  assert_contains "$out" "[antigravity-rescue] both Antigravity pools exhausted (Gemini 1% resets 2026-09-30 09:00; Claude/GPT 2% resets 2026-10-01 14:30)" "message" || return 1
  assert_not_contains "$out" "model:" "model line" || return 1
  for n in $(seq "$(call_count)"); do
    case $(call_arg_after "$n" -p) in
      /usage | /model) ;;
      *) fail "call $n ran a task: $(call_args "$n")" || return 1 ;;
    esac
  done
}

test_preflight_probes_keep_slash_commands_and_skip_msys_path_conversion() {
  local n
  bash "$FORWARD" preflight >/dev/null
  assert_eq "$(call_count)" 2 "probe calls" || return 1
  assert_eq "$(call_arg_after 1 -p)" "/usage" "first probe" || return 1
  assert_eq "$(call_arg_after 2 -p)" "/model" "second probe" || return 1
  for n in 1 2; do
    ! call_has_arg "$n" --disable-slash-commands || fail "probe $n has --disable-slash-commands" || return 1
    assert_eq "$(call_env "$n" MSYS_NO_PATHCONV)" 1 "probe $n MSYS_NO_PATHCONV" || return 1
  done
}

test_preflight_reads_windows_line_endings() {
  local out
  sed 's/$/\r/' "$FIXTURES/usage-gemini-empty.txt" >"$HOME/usage-crlf.txt"
  export FAKE_AGY_USAGE="$HOME/usage-crlf.txt"
  out=$(bash "$FORWARD" preflight)
  assert_contains "$out" "Gemini 0% (resets 2026-09-30 09:00); Claude/GPT 25% (resets 2026-10-01 14:30)" "gauges" || return 1
  assert_contains "$out" $'\nmodel: claude-sonnet-4-6' "model"
}

test_preflight_reports_an_unreadable_usage_verbatim() {
  local out rc
  use_usage auth-error
  export FAKE_AGY_USAGE_EXIT=1
  out=$(bash "$FORWARD" preflight)
  rc=$?
  assert_eq "$rc" 70 "exit code" || return 1
  assert_contains "$out" "error: authentication required: not logged into Antigravity" "agy output"
}

test_preflight_other_pool_checks_only_the_other_pool() {
  local out rc
  use_usage both-ok
  out=$(bash "$FORWARD" preflight --model gemini-3.1-pro-high --effort high --other-pool)
  rc=$?
  assert_eq "$rc" 0 "exit code" || return 1
  assert_contains "$out" $'\nmodel: claude-sonnet-4-6\neffort: ' "other pool model" || return 1
  assert_not_contains "$out" "effort: high" "effort" || return 1
  use_usage claude-empty
  out=$(bash "$FORWARD" preflight --model gemini-3.1-pro-high --other-pool)
  rc=$?
  assert_eq "$rc" 69 "exhausted other pool exit code" || return 1
  assert_contains "$out" "[antigravity-rescue] Claude/GPT pool at 0% (resets 2026-10-01 14:30), no other pool to rerun on" "message"
}

test_missing_agy_is_reported() {
  local out rc
  rm "$HOME/bin/agy"
  out=$(printf 'fix the build' | bash "$FORWARD" run)
  rc=$?
  assert_eq "$rc" 127 "exit code" || return 1
  assert_contains "$out" "antigravity-rescue: agy not found" "message"
}

settings_path() {
  printf '%s' "$HOME/.gemini/antigravity-cli/settings.json"
}

write_settings() {
  printf '%s\n' "$1" >"$(settings_path)"
}

permissions_without() {
  grep -v -F "$1" "$ROOT/docs/permissions.json" | sed 's/\(sudo.*"\),$/\1/'
}

assert_gate_refuses() {
  local out=$1 rc=$2
  assert_eq "$rc" 78 "exit code" || return 1
  assert_contains "$out" "antigravity-rescue: missing deny rules: " "message" || return 1
  assert_contains "$out" " — run /antigravity:setup" "setup hint" || return 1
  assert_eq "$(call_count)" 0 "agy calls"
}

test_run_refuses_without_a_settings_file() {
  local out rc
  rm "$(settings_path)"
  out=$(printf 'fix the build' | bash "$FORWARD" run)
  rc=$?
  assert_gate_refuses "$out" "$rc" || return 1
  assert_contains "$out" "git push, git reset, git clean, rm, rmdir, del, rd, Remove-Item, write_file(.git/)" "all rules listed"
}

test_run_refuses_an_empty_deny_list() {
  local out rc
  write_settings '{ "permissions": { "deny": [] } }'
  out=$(printf 'fix the build' | bash "$FORWARD" run)
  rc=$?
  assert_gate_refuses "$out" "$rc" || return 1
  assert_contains "$out" "missing deny rules: git push" "git push listed"
}

test_preflight_refuses_an_empty_deny_list() {
  local out rc
  write_settings '{ "permissions": { "deny": [] } }'
  out=$(bash "$FORWARD" preflight)
  rc=$?
  assert_gate_refuses "$out" "$rc"
}

test_run_names_the_single_missing_deny_rule() {
  local out rc
  permissions_without 'write_file(.git/)' >"$(settings_path)"
  out=$(printf 'fix the build' | bash "$FORWARD" run)
  rc=$?
  assert_gate_refuses "$out" "$rc" || return 1
  assert_contains "$out" "missing deny rules: write_file(.git/) — run" "only write_file listed"
}

test_run_ignores_critical_rules_outside_the_deny_list() {
  local out rc allow
  allow=$(sed -n '/"deny"/,/]/p' "$ROOT/docs/permissions.json" | sed '1s/"deny"/"allow"/')
  write_settings "{ \"permissions\": { $allow, \"deny\": [ $(grep -F 'sudo' "$ROOT/docs/permissions.json" | tr -d ' ,') ] } }"
  out=$(printf 'fix the build' | bash "$FORWARD" run)
  rc=$?
  assert_gate_refuses "$out" "$rc" || return 1
  assert_contains "$out" "missing deny rules: git push" "git push listed"
}

test_run_accepts_merged_rules_in_a_compact_crlf_settings_file() {
  local out rc
  { printf '{"theme":"dark","permissions":{"allow":[],"deny":['
    grep -o '"[a-z_]*(.*)"' "$ROOT/docs/permissions.json" | paste -s -d , -
    printf ']}}\r\n'
  } | sed 's/,/,\r\n/g' >"$(settings_path)"
  out=$(printf 'fix the build' | bash "$FORWARD" run)
  rc=$?
  assert_eq "$rc" 0 "exit code" || return 1
  assert_eq "$out" "done" "stdout" || return 1
  assert_eq "$(call_count)" 1 "agy calls"
}

test_run_forwards_the_fixed_flags() {
  local out rc
  out=$(printf 'fix the build' | bash "$FORWARD" run --model gemini-3.1-pro-high)
  rc=$?
  assert_eq "$rc" 0 "exit code" || return 1
  assert_eq "$out" "done" "stdout" || return 1
  assert_eq "$(call_count)" 1 "agy calls" || return 1
  assert_eq "$(call_arg_after 1 --add-dir)" "$PWD" "--add-dir" || return 1
  assert_eq "$(call_arg_after 1 --output-format)" "text" "--output-format" || return 1
  assert_eq "$(call_arg_after 1 --print-timeout)" "9m" "--print-timeout" || return 1
  assert_eq "$(call_arg_after 1 --model)" "gemini-3.1-pro-high" "--model" || return 1
  call_has_arg 1 --dangerously-skip-permissions || fail "no --dangerously-skip-permissions" || return 1
  call_has_arg 1 --disable-slash-commands || fail "no --disable-slash-commands" || return 1
  ! call_has_arg 1 --continue || fail "unexpected --continue" || return 1
  ! call_has_arg 1 --effort || fail "unexpected --effort"
}

test_run_sets_a_non_interactive_git_environment() {
  printf 'fix the build' | bash "$FORWARD" run >/dev/null
  assert_eq "$(call_env 1 GIT_TERMINAL_PROMPT)" 0 "GIT_TERMINAL_PROMPT" || return 1
  assert_eq "$(call_env 1 GIT_SSH_COMMAND)" "ssh -o BatchMode=yes" "GIT_SSH_COMMAND" || return 1
  assert_eq "$(call_env 1 MSYS_NO_PATHCONV)" "" "MSYS_NO_PATHCONV"
}

test_run_drops_effort_for_non_gemini_models() {
  printf 'fix the build' | bash "$FORWARD" run --model claude-opus-4-6-thinking --effort high >/dev/null
  assert_eq "$(call_arg_after 1 --model)" "claude-opus-4-6-thinking" "--model" || return 1
  ! call_has_arg 1 --effort || fail "--effort forwarded: $(call_args 1)"
}

test_run_keeps_effort_for_gemini_models() {
  printf 'fix the build' | bash "$FORWARD" run --model gemini-3.1-pro-high --effort high --continue >/dev/null
  assert_eq "$(call_arg_after 1 --effort)" "high" "--effort" || return 1
  call_has_arg 1 --continue || fail "no --continue"
}

test_run_passes_the_task_literally() {
  local task prompt
  task=$(cat "$FIXTURES/tricky-task.txt")
  bash "$FORWARD" run <"$FIXTURES/tricky-task.txt" >/dev/null
  prompt=$(call_arg_after 1 -p)
  assert_contains "$task" 'EOF_TASK' "fixture delimiter" || return 1
  assert_contains "$task" '$(whoami)' "fixture substitution" || return 1
  assert_eq "${prompt%$'\n\n'Constraints: *}" "$task" "task text" || return 1
  assert_contains "$prompt" $'\n\nConstraints: work directly in this workspace' "constraints" || return 1
  assert_contains "$prompt" "end with a short list of the files you touched." "constraints end"
}

test_run_rejects_an_empty_task() {
  local rc
  printf '  \n' | bash "$FORWARD" run >/dev/null 2>&1
  rc=$?
  assert_eq "$rc" 64 "exit code" || return 1
  assert_eq "$(call_count)" 0 "agy calls"
}

test_run_aborts_on_quota_errors_in_its_own_log() {
  local out rc
  export FAKE_AGY_MODE=quota AGY_QUOTA_ABORT_AFTER=1
  out=$(printf 'fix the build' | bash "$FORWARD" run --model claude-sonnet-4-6)
  rc=$?
  assert_eq "$rc" 75 "exit code" || return 1
  assert_contains "$out" "[antigravity-rescue] quota: RESOURCE_EXHAUSTED on claude-sonnet-4-6" "quota line"
}

new_repo() {
  git init -q "$HOME/repo" && git -C "$HOME/repo" commit -q --allow-empty -m initial
}

run_in_repo() {
  export FAKE_AGY_MODE=$1
  (cd "${2:-$HOME/repo}" && printf 'fix the build' | bash "$FORWARD" run)
}

assert_git_warning() {
  local out=$1 what=$2
  assert_contains "$out" "[antigravity-rescue] WARNING: " "warning prefix" || return 1
  assert_contains "$out" "$what" "what changed" || return 1
  assert_contains "$out" " — review before your next git command" "warning suffix"
}

test_run_warns_when_the_delegate_commits() {
  local out rc
  new_repo
  out=$(run_in_repo git-commit)
  rc=$?
  assert_eq "$rc" 0 "exit code" || return 1
  assert_git_warning "$out" "HEAD" || return 1
  assert_eq "$(git -C "$HOME/repo" rev-list --count HEAD)" 2 "commits left in place"
}

test_run_warns_when_the_delegate_writes_a_hook() {
  local out
  new_repo
  out=$(run_in_repo git-hook)
  assert_git_warning "$out" "hooks" || return 1
  assert_not_contains "$out" "HEAD" "HEAD warning" || return 1
  [ -f "$HOME/repo/.git/hooks/pre-commit" ] || fail "hook removed"
}

test_run_warns_when_the_delegate_changes_git_config() {
  local out
  new_repo
  out=$(run_in_repo git-config)
  assert_git_warning "$out" "config" || return 1
  assert_eq "$(git -C "$HOME/repo" config alias.x)" '!echo' "alias left in place"
}

test_run_warns_when_the_delegate_switches_branch() {
  local out
  new_repo
  out=$(run_in_repo git-switch)
  assert_git_warning "$out" "branch" || return 1
  assert_eq "$(git -C "$HOME/repo" symbolic-ref --short HEAD)" "delegate" "branch left in place"
}

test_run_warns_when_the_delegate_stashes() {
  local out
  new_repo
  out=$(run_in_repo git-stash)
  assert_git_warning "$out" "stash" || return 1
  assert_eq "$(git -C "$HOME/repo" stash list | wc -l | tr -d ' ')" 1 "stash left in place"
}

test_run_warns_about_a_hook_written_from_a_linked_worktree() {
  local out
  new_repo
  git -C "$HOME/repo" worktree add -q "$HOME/linked" 2>/dev/null
  out=$(run_in_repo git-hook "$HOME/linked")
  assert_git_warning "$out" "hooks" || return 1
  [ -f "$HOME/repo/.git/hooks/pre-commit" ] || fail "hook not in the common hooks dir"
}

test_run_that_leaves_git_alone_prints_no_warning() {
  local out rc
  new_repo
  out=$(run_in_repo done)
  rc=$?
  assert_eq "$rc" 0 "exit code" || return 1
  assert_eq "$out" "done" "stdout"
}

test_unknown_subcommand_is_a_usage_error() {
  local rc
  bash "$FORWARD" launch >/dev/null 2>&1
  rc=$?
  assert_eq "$rc" 64 "exit code"
}

run_test() {
  local name=$1 results=$2
  (new_sandbox && trap 'rm -rf "$HOME"' EXIT && "$name") >"$results/$name.out" 2>&1
  printf '%s' "$?" >"$results/$name.rc"
}

report_test() {
  local name=$1 results=$2
  printf '%s\n' "$name"
  cat "$results/$name.out"
  [ "$(cat "$results/$name.rc")" = 0 ] || return 1
  printf '    ok\n'
}

list_tests() {
  declare -F | awk '{print $3}' | grep '^test_'
}

test_jobs() {
  local n=${TEST_JOBS:-$DEFAULT_TEST_JOBS}
  case $n in
    '' | *[!0-9]* | 0) n=$DEFAULT_TEST_JOBS ;;
  esac
  printf '%s' "$n"
}

# Tests run in parallel because most of their time is spent waiting on the fake agy's sleeps,
# but capped: launching every test at once loads the machine enough to slow the watcher's polls.
main() {
  local name results jobs running=0
  results=$(mktemp -d)
  jobs=$(test_jobs)
  for name in $(list_tests); do
    [ "$running" -lt "$jobs" ] || { wait -n; running=$((running - 1)); }
    run_test "$name" "$results" &
    running=$((running + 1))
  done
  wait
  for name in $(list_tests); do
    report_test "$name" "$results" || FAILURES=$((FAILURES + 1))
  done
  rm -rf "$results"
  [ "$FAILURES" -eq 0 ] || { printf '%s test(s) failed\n' "$FAILURES"; exit 1; }
  printf 'all tests passed\n'
}

main
