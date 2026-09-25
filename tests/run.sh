#!/usr/bin/env bash
# Hermetic tests: fake agy, temporary HOME, no network, the real ~/.gemini is never read.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FORWARD="$ROOT/scripts/agy-forward.sh"
FAKE_AGY="$ROOT/tests/fake-agy.sh"
FAILURES=0

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

new_sandbox() {
  HOME=$(mktemp -d)
  AGY_LOG_DIR="$HOME/.gemini/antigravity-cli/log"
  export HOME AGY_LOG_DIR
  mkdir -p "$AGY_LOG_DIR"
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

test_quota_errors_abort_the_run_early() {
  local prompt out rc start elapsed pid
  prompt=$(prompt_of_length 500)
  export FAKE_AGY_MODE=quota FAKE_AGY_PIDFILE="$HOME/fake.pid"
  start=$SECONDS
  out=$(bash "$FORWARD" "$FAKE_AGY" -p "$prompt" --model gemini-3.1-pro-high)
  rc=$?
  elapsed=$((SECONDS - start))
  pid=$(cat "$FAKE_AGY_PIDFILE")
  assert_eq "$rc" 75 "exit code" || return 1
  [ "$elapsed" -lt 15 ] || fail "took ${elapsed}s" || return 1
  assert_contains "$out" "[antigravity-rescue] quota: RESOURCE_EXHAUSTED on gemini-3.1-pro-high (Individual quota reached, Resets in 10h)" "quota line" || return 1
  ! kill -0 "$pid" 2>/dev/null || fail "fake agy $pid still alive"
}

test_clean_run_passes_output_through() {
  local out rc
  export FAKE_AGY_MODE=done
  out=$(bash "$FORWARD" "$FAKE_AGY" -p "fix the build")
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
  out=$(bash "$FORWARD" "$FAKE_AGY" -p "$prompt")
  rc=$?
  wait "$writer"
  assert_eq "$rc" 0 "exit code" || return 1
  assert_eq "$out" "done" "stdout"
}

test_threshold_is_configurable() {
  local out rc
  export FAKE_AGY_MODE=quota-brief AGY_QUOTA_ABORT_AFTER=5
  out=$(bash "$FORWARD" "$FAKE_AGY" -p "fix the build")
  rc=$?
  assert_eq "$rc" 0 "exit code" || return 1
  assert_eq "$out" "done" "stdout"
}

test_run_that_already_finished_is_not_reported_as_quota() {
  local out rc
  export FAKE_AGY_MODE=quota-burst
  out=$(bash "$FORWARD" "$FAKE_AGY" -p "fix the build")
  rc=$?
  assert_eq "$rc" 0 "exit code" || return 1
  assert_eq "$out" "done" "stdout"
}

test_child_exit_code_is_preserved() {
  local rc
  export FAKE_AGY_MODE=fail
  bash "$FORWARD" "$FAKE_AGY" -p "fix the build" >/dev/null 2>&1
  rc=$?
  assert_eq "$rc" 3 "exit code"
}

test_terminating_the_forwarder_stops_agy() {
  local forwarder pid
  export FAKE_AGY_MODE=quota AGY_QUOTA_ABORT_AFTER=1000 FAKE_AGY_PIDFILE="$HOME/fake.pid"
  bash "$FORWARD" "$FAKE_AGY" -p "fix the build" >/dev/null 2>&1 &
  forwarder=$!
  wait_for_file "$FAKE_AGY_PIDFILE" 60 || fail "fake agy never started" || return 1
  pid=$(cat "$FAKE_AGY_PIDFILE")
  kill -TERM "$forwarder"
  wait "$forwarder"
  ! kill -0 "$pid" 2>/dev/null || fail "fake agy $pid still alive"
}

run_test() {
  local name=$1
  printf '%s\n' "$name"
  if (new_sandbox && trap 'rm -rf "$HOME"' EXIT && "$name"); then
    printf '    ok\n'
  else
    FAILURES=$((FAILURES + 1))
  fi
}

main() {
  local name
  for name in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$name"
  done
  [ "$FAILURES" -eq 0 ] || { printf '%s test(s) failed\n' "$FAILURES"; exit 1; }
  printf 'all tests passed\n'
}

main
