#!/usr/bin/env bash
# Usage: agy-forward.sh <agy-binary> <agy args...>
# Runs agy and aborts it as soon as its own run log shows repeated RESOURCE_EXHAUSTED errors.
set -u

readonly QUOTA_EXIT=75
readonly DEFAULT_ABORT_AFTER=3
readonly WATCH_INTERVAL=2
readonly LOG_DIR=${AGY_LOG_DIR:-$HOME/.gemini/antigravity-cli/log}
CHILD_PID=""

abort_threshold() {
  local n=${AGY_QUOTA_ABORT_AFTER:-$DEFAULT_ABORT_AFTER}
  case $n in
    '' | *[!0-9]* | 0) n=$DEFAULT_ABORT_AFTER ;;
  esac
  printf '%s' "$n"
}

arg_after() {
  local flag=$1
  shift
  while [ $# -gt 1 ]; do
    [ "$1" = "$flag" ] && { printf '%s' "$2"; return 0; }
    shift
  done
  return 1
}

byte_length() {
  local LC_ALL=C
  printf '%s' "${#1}"
}

char_length() {
  local LC_ALL=C.UTF-8
  printf '%s' "${#1}"
}

# agy logs promptLength without saying whether it counts bytes or characters, so accept both.
prompt_lengths() {
  local flag=$1
  shift
  while [ $# -gt 1 ]; do
    [ "$1" = "$flag" ] && { printf '%s %s' "$(byte_length "$2")" "$(char_length "$2")"; return 0; }
    shift
  done
  return 1
}

list_run_logs() {
  local log
  for log in "$LOG_DIR"/cli-*.log; do
    [ -e "$log" ] && printf '%s\n' "$log"
  done
}

is_new_log() {
  local log=$1 existing=$2
  [ -e "$log" ] || return 1
  ! printf '%s\n' "$existing" | grep -Fxq -- "$log"
}

logged_prompt_length() {
  local line
  line=$(grep -o -m 1 'Print mode: starting (promptLength=[0-9]*' "$1" 2>/dev/null)
  printf '%s' "${line##*=}"
}

is_prompt_length() {
  local n=$1 bytes=$2 chars=$3
  [ -n "$n" ] && { [ "$n" = "$bytes" ] || [ "$n" = "$chars" ]; }
}

# /usage and /model probes and runs from other sessions share the log dir; only a log created
# after our launch whose prompt length matches ours belongs to this run.
find_own_log() {
  local existing=$1 bytes=$2 chars=$3 log
  for log in "$LOG_DIR"/cli-*.log; do
    is_new_log "$log" "$existing" || continue
    is_prompt_length "$(logged_prompt_length "$log")" "$bytes" "$chars" && { printf '%s' "$log"; return 0; }
  done
  return 1
}

quota_error_count() {
  grep -c 'RESOURCE_EXHAUSTED' "$1" 2>/dev/null
}

trim_reason() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:].,;]*$//' | cut -c 1-160
}

quota_summary() {
  local log=$1 detail resets reason
  detail=$(grep 'RESOURCE_EXHAUSTED' "$log" | tail -n 1)
  detail=${detail#*RESOURCE_EXHAUSTED}
  detail=${detail#*): }
  resets=$(printf '%s' "$detail" | grep -o 'Resets in [0-9A-Za-z.]*' | head -n 1)
  resets=${resets%.}
  reason=$(trim_reason "${detail%%Resets in*}")
  [ -n "$resets" ] && reason="${reason:+$reason, }$resets"
  printf '%s' "$reason"
}

report_quota() {
  local log=$1 model=$2
  printf '[antigravity-rescue] quota: RESOURCE_EXHAUSTED on %s (%s)\n' "$model" "$(quota_summary "$log")"
}

stop_child() {
  local pid=$1 i
  [ -n "$pid" ] || return 0
  kill -TERM "$pid" 2>/dev/null || return 0
  for i in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.3
  done
  kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  return 0
}

quota_exhausted() {
  local log=$1 threshold=$2 count
  [ -n "$log" ] || return 1
  count=$(quota_error_count "$log")
  [ "${count:-0}" -ge "$threshold" ]
}

watch_child() {
  local pid=$1 existing=$2 bytes=$3 chars=$4 model=$5 log="" threshold
  threshold=$(abort_threshold)
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$WATCH_INTERVAL"
    # A run that ended on its own during the sleep keeps its own output and exit code.
    kill -0 "$pid" 2>/dev/null || break
    [ -n "$log" ] || log=$(find_own_log "$existing" "$bytes" "$chars") || log=""
    quota_exhausted "$log" "$threshold" || continue
    stop_child "$pid"
    report_quota "$log" "$model"
    return "$QUOTA_EXIT"
  done
  wait "$pid"
}

main() {
  [ $# -ge 1 ] || { echo "usage: agy-forward.sh <agy-binary> [agy args...]" >&2; exit 64; }
  local existing lengths model
  existing=$(list_run_logs)
  lengths=$(prompt_lengths -p "$@") || lengths=""
  model=$(arg_after --model "$@") || model="the default model"
  trap 'stop_child "$CHILD_PID"; exit 143' TERM INT HUP
  "$@" &
  CHILD_PID=$!
  [ -n "$lengths" ] || { wait "$CHILD_PID"; exit; }
  # shellcheck disable=SC2086
  watch_child "$CHILD_PID" "$existing" $lengths "$model"
}

main "$@"
