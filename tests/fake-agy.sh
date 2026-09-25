#!/usr/bin/env bash
# Stand-in for agy: records each call, answers /usage and /model, writes a per-run log the way agy does and behaves per FAKE_AGY_MODE.
set -u

prompt_of() {
  while [ $# -gt 1 ]; do
    [ "$1" = "-p" ] && { printf '%s' "$2"; return 0; }
    shift
  done
}

has_arg() {
  local wanted=$1
  shift
  local arg
  for arg in "$@"; do
    [ "$arg" = "$wanted" ] && return 0
  done
  return 1
}

byte_length() {
  local LC_ALL=C
  printf '%s' "${#1}"
}

record_call() {
  local dir=${FAKE_AGY_CALLS:-} n=1
  [ -n "$dir" ] || return 0
  [ -d "$dir" ] || mkdir -p "$dir"
  while [ -e "$dir/$n.args" ]; do
    n=$((n + 1))
  done
  printf '%s\0' "$@" >"$dir/$n.args"
  printf 'MSYS_NO_PATHCONV=%s\nGIT_TERMINAL_PROMPT=%s\nGIT_SSH_COMMAND=%s\n' \
    "${MSYS_NO_PATHCONV:-}" "${GIT_TERMINAL_PROMPT:-}" "${GIT_SSH_COMMAND:-}" >"$dir/$n.env"
}

open_run_log() {
  local dir=${AGY_LOG_DIR:-$HOME/.gemini/antigravity-cli/log} stamp
  [ -d "$dir" ] || mkdir -p "$dir"
  printf -v stamp '%(%Y%m%d_%H%M%S)T' -1
  printf '%s/cli-%s_%s.log' "$dir" "$stamp" "$$"
}

answers_slash_command() {
  local prompt=$1
  shift
  case $prompt in
    /usage | /model) ! has_arg --disable-slash-commands "$@" ;;
    *) return 1 ;;
  esac
}

answer_slash_command() {
  case $1 in
    /usage) cat "${FAKE_AGY_USAGE:-/dev/null}"; exit "${FAKE_AGY_USAGE_EXIT:-0}" ;;
    /model) printf '%s\n' "${FAKE_AGY_DEFAULT_MODEL:-gemini-3.1-pro-high}" ;;
  esac
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

stash_a_change() {
  printf 'x\n' >delegate.txt
  git add delegate.txt
  git stash -q
}

main() {
  local prompt log
  prompt=$(prompt_of "$@")
  record_call "$@"
  log=$(open_run_log)
  printf 'I0917 13:10:00 main.go:40] Print mode: starting (promptLength=%s, outputFormat=text)\n' "$(byte_length "$prompt")" >>"$log"
  answers_slash_command "$prompt" "$@" && { answer_slash_command "$prompt"; return; }
  [ -n "${FAKE_AGY_PIDFILE:-}" ] && printf '%s' "$$" >"$FAKE_AGY_PIDFILE"
  case ${FAKE_AGY_MODE:-done} in
    quota) write_quota_errors "$log" 120; echo "partial" ;;
    quota-brief) write_quota_errors "$log" 3; echo "done" ;;
    quota-burst) for _ in 1 2 3; do quota_line >>"$log"; done; echo "done" ;;
    slow) write_progress "$log" 4; echo "done" ;;
    fail) echo "error: boom" >&2; exit 3 ;;
    git-commit) git commit -q --allow-empty -m x; echo "done" ;;
    git-hook) printf '#!/bin/sh\n' >"$(git rev-parse --git-path hooks)/pre-commit"; echo "done" ;;
    git-config) git config alias.x '!echo'; echo "done" ;;
    git-switch) git switch -q -c delegate; echo "done" ;;
    git-stash) stash_a_change; echo "done" ;;
    *) echo "done" ;;
  esac
}

main "$@"
