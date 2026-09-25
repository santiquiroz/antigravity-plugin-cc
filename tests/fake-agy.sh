#!/usr/bin/env bash
# Stand-in for agy: writes a per-run log the way agy does and behaves per FAKE_AGY_MODE.
set -u

prompt_of() {
  while [ $# -gt 1 ]; do
    [ "$1" = "-p" ] && { printf '%s' "$2"; return 0; }
    shift
  done
}

byte_length() {
  local LC_ALL=C
  printf '%s' "${#1}"
}

open_run_log() {
  local dir=${AGY_LOG_DIR:-$HOME/.gemini/antigravity-cli/log}
  mkdir -p "$dir"
  printf '%s/cli-%s_%s.log' "$dir" "$(date +%Y%m%d_%H%M%S)" "$$"
}

quota_line() {
  printf 'E0917 13:10:01 retry.go:88] RESOURCE_EXHAUSTED (code 429): Individual quota reached. Resets in 10h\n'
}

write_quota_errors() {
  local log=$1 count=$2 i
  for i in $(seq "$count"); do
    quota_line >>"$log"
    sleep 1
  done
}

write_progress() {
  local log=$1 seconds=$2 i
  for i in $(seq "$seconds"); do
    printf 'I0917 13:10:01 agent.go:12] step %s\n' "$i" >>"$log"
    sleep 1
  done
}

main() {
  local prompt log
  prompt=$(prompt_of "$@")
  [ -n "${FAKE_AGY_PIDFILE:-}" ] && printf '%s' "$$" >"$FAKE_AGY_PIDFILE"
  log=$(open_run_log)
  printf 'I0917 13:10:00 main.go:40] Print mode: starting (promptLength=%s, outputFormat=text)\n' "$(byte_length "$prompt")" >>"$log"
  case ${FAKE_AGY_MODE:-done} in
    quota) write_quota_errors "$log" 120; echo "partial" ;;
    quota-brief) write_quota_errors "$log" 3; echo "done" ;;
    quota-burst) for _ in 1 2 3; do quota_line >>"$log"; done; echo "done" ;;
    slow) write_progress "$log" 4; echo "done" ;;
    fail) echo "error: boom" >&2; exit 3 ;;
    *) echo "done" ;;
  esac
}

main "$@"
