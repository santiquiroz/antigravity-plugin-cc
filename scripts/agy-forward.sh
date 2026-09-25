#!/usr/bin/env bash
# Usage:
#   agy-forward.sh preflight [--model <slug>] [--effort low|medium|high] [--class mechanical|reasoning|hardest] [--other-pool]
#   agy-forward.sh run [--model <slug>] [--effort low|medium|high] [--continue] <task on stdin>
#   agy-forward.sh watch <agy-binary> [agy args...]
set -u

readonly USAGE_EXIT=64
readonly POOLS_EXHAUSTED_EXIT=69
readonly PREFLIGHT_FAILED_EXIT=70
readonly QUOTA_EXIT=75
readonly UNSAFE_EXIT=78
readonly NOT_FOUND_EXIT=127
readonly EXHAUSTED_PERCENT=2
readonly DEFAULT_ABORT_AFTER=3
readonly POLL_STEP=0.25
readonly POLLS_PER_WATCH=8
readonly LOG_DIR=${AGY_LOG_DIR:-$HOME/.gemini/antigravity-cli/log}
readonly SLUG_PATTERN='(gemini|claude|gpt)-[A-Za-z0-9._-]+'
readonly SETTINGS_FILE="$HOME/.gemini/antigravity-cli/settings.json"
readonly CONSTRAINTS="Constraints: work directly in this workspace following the instructions above. Do not invoke other AI CLIs (claude, codex, copilot, gemini, ollama). Do not commit, push, switch branches or delete files. If a command is denied by policy, stop and report it — do not look for another way to run it. Leave your changes in the working tree and end with a short list of the files you touched."
CHILD_PID=""
AGY=""
GEMINI_PERCENT=""
GEMINI_RESET=""
CLAUDE_GPT_PERCENT=""
CLAUDE_GPT_RESET=""
OPT_MODEL=""
OPT_EFFORT=""
OPT_CLASS=""
OPT_OTHER_POOL=0
OPT_CONTINUE=0

usage_error() {
  printf 'agy-forward.sh: %s\n' "$1" >&2
  exit "$USAGE_EXIT"
}

is_one_of() {
  local value=$1 candidate
  shift
  for candidate in "$@"; do
    [ "$value" = "$candidate" ] && return 0
  done
  return 1
}

set_option() {
  case $1 in
    --model) OPT_MODEL=$2 ;;
    --effort) is_one_of "$2" low medium high || usage_error "--effort must be low, medium or high"; OPT_EFFORT=$2 ;;
    --class) is_one_of "$2" mechanical reasoning hardest || usage_error "--class must be mechanical, reasoning or hardest"; OPT_CLASS=$2 ;;
  esac
}

parse_options() {
  while [ $# -gt 0 ]; do
    case $1 in
      --model | --effort | --class)
        [ $# -ge 2 ] || usage_error "$1 needs a value"
        set_option "$1" "$2"
        shift 2
        ;;
      --other-pool) OPT_OTHER_POOL=1; shift ;;
      --continue) OPT_CONTINUE=1; shift ;;
      *) usage_error "unknown option: $1" ;;
    esac
  done
}

agy_candidates() {
  local appdata=${LOCALAPPDATA:-}
  appdata=${appdata//\\//}
  [ -n "$appdata" ] && printf '%s\n' "$appdata/agy/bin/agy.exe"
  printf '%s\n' "$HOME/.gemini/bin/agy.exe" "$HOME/.gemini/bin/agy" "$HOME/.local/bin/agy"
}

find_agy() {
  local candidate
  command -v agy 2>/dev/null && return 0
  while IFS= read -r candidate; do
    [ -f "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  done < <(agy_candidates)
  return 1
}

require_agy() {
  AGY=$(find_agy) && return 0
  echo "antigravity-rescue: agy not found — run /antigravity:setup"
  return "$NOT_FOUND_EXIT"
}

# Name|exact JSON text of each rule from docs/permissions.json that the gate requires.
readonly CRITICAL_DENY_RULES=(
  'git push|command(regex:.*\\bgit\\s+push\\b.*)'
  'git reset|command(regex:.*\\bgit\\s+reset\\b.*)'
  'git clean|command(regex:.*\\bgit\\s+clean\\b.*)'
  'rm|command(regex:.*\\brm\\b.*)'
  'rmdir|command(regex:.*\\brmdir\\b.*)'
  'del|command(regex:.*\\bdel\\b.*)'
  'rd|command(regex:.*\\brd\\b.*)'
  'Remove-Item|command(regex:.*\\bRemove-Item\\b.*)'
  'write_file(.git/)|write_file(.git/)'
)
readonly DENY_LIST_PATTERN='"deny"[[:space:]]*:[[:space:]]*\[[^]]*\]'

# Builtins only: forking grep per rule costs seconds on a loaded Windows machine.
deny_lists() {
  local text="" lists=""
  [ -r "$SETTINGS_FILE" ] && IFS= read -r -d '' text <"$SETTINGS_FILE"
  text=${text//[$'\r\n']/}
  while [[ $text =~ $DENY_LIST_PATTERN ]]; do
    lists+=${BASH_REMATCH[0]}
    text=${text#*"${BASH_REMATCH[0]}"}
  done
  printf '%s' "$lists"
}

missing_deny_rules() {
  local lists=$1 entry missing=""
  for entry in "${CRITICAL_DENY_RULES[@]}"; do
    [[ $lists == *"\"${entry#*|}\""* ]] || missing="${missing:+$missing, }${entry%%|*}"
  done
  printf '%s' "$missing"
}

# Headless agy needs --dangerously-skip-permissions; user deny rules are what still wins under it.
require_deny_rules() {
  local missing
  missing=$(missing_deny_rules "$(deny_lists)")
  [ -z "$missing" ] && return 0
  echo "antigravity-rescue: missing deny rules: $missing — run /antigravity:setup"
  return "$UNSAFE_EXIT"
}

# Without MSYS_NO_PATHCONV, Git Bash rewrites "/usage" into a Windows path and agy sends it to the model as a paid turn.
slash_probe() {
  local out
  out=$(MSYS_NO_PATHCONV=1 "$AGY" -p "$1" --output-format text --print-timeout 30s)
  printf '%s' "${out//$'\r'/}"
}

default_model() {
  [[ $(slash_probe /model) =~ $SLUG_PATTERN ]] && printf '%s' "${BASH_REMATCH[0]}"
}

pool_label() {
  case $1 in
    gemini) printf 'Gemini' ;;
    *) printf 'Claude/GPT' ;;
  esac
}

pool_gauge() {
  printf '%s\n' "$1" | awk -F '\t' -v pool="$2" '
    { name = tolower($1); sub(/^[[:space:]]+/, "", name) }
    index(name, pool) != 1 { next }
    {
      for (i = 2; i <= NF; i++) {
        if ($i !~ /^[[:space:]]*[0-9.]+%[[:space:]]*$/) continue
        percent = $i; gsub(/[[:space:]%]/, "", percent)
        reset = (i < NF) ? $(i + 1) : ""; gsub(/^[[:space:]]+|[[:space:]]+$/, "", reset)
        printf "%d\t%s\n", percent, reset
        exit
      }
    }'
}

percent_of() {
  case $1 in
    gemini) printf '%s' "$GEMINI_PERCENT" ;;
    *) printf '%s' "$CLAUDE_GPT_PERCENT" ;;
  esac
}

reset_of() {
  case $1 in
    gemini) printf '%s' "$GEMINI_RESET" ;;
    *) printf '%s' "$CLAUDE_GPT_RESET" ;;
  esac
}

read_usage() {
  local usage
  usage=$(slash_probe /usage)
  IFS=$'\t' read -r GEMINI_PERCENT GEMINI_RESET < <(pool_gauge "$usage" gemini)
  IFS=$'\t' read -r CLAUDE_GPT_PERCENT CLAUDE_GPT_RESET < <(pool_gauge "$usage" claude)
  [ -n "$GEMINI_PERCENT" ] && [ -n "$CLAUDE_GPT_PERCENT" ] && return 0
  printf '[antigravity-rescue] preflight failed: agy -p "/usage" did not show both quota pools:\n%s\n' "$usage"
  return "$PREFLIGHT_FAILED_EXIT"
}

is_exhausted() {
  [ "$(percent_of "$1")" -le "$EXHAUSTED_PERCENT" ]
}

is_gemini_slug() {
  case $1 in
    gemini-*) return 0 ;;
  esac
  return 1
}

# agy's documented default is a Gemini model, so an unreadable default counts as the Gemini pool.
pool_of() {
  case $1 in
    '' | gemini-*) printf 'gemini' ;;
    *) printf 'claude-gpt' ;;
  esac
}

other_pool() {
  case $1 in
    gemini) printf 'claude-gpt' ;;
    *) printf 'gemini' ;;
  esac
}

class_of_slug() {
  case $1 in
    *flash* | gpt-oss*) printf 'mechanical' ;;
    claude-opus*) printf 'hardest' ;;
    *) printf 'reasoning' ;;
  esac
}

task_class() {
  [ -n "$OPT_CLASS" ] && { printf '%s' "$OPT_CLASS"; return 0; }
  class_of_slug "$1"
}

equivalent_slug() {
  case $1:$2 in
    gemini:mechanical) printf 'gemini-3.8-flash-low' ;;
    gemini:*) printf 'gemini-3.1-pro-high' ;;
    claude-gpt:mechanical) printf 'gpt-oss-120b-medium' ;;
    claude-gpt:hardest) printf 'claude-opus-4-6-thinking' ;;
    *) printf 'claude-sonnet-4-6' ;;
  esac
}

print_gauges() {
  printf '[antigravity-rescue] preflight: Gemini %s%% (resets %s); Claude/GPT %s%% (resets %s)\n' \
    "$GEMINI_PERCENT" "$GEMINI_RESET" "$CLAUDE_GPT_PERCENT" "$CLAUDE_GPT_RESET"
}

print_choice() {
  local model=$1 effort=$2
  is_gemini_slug "$model" || effort=""
  printf 'model: %s\neffort: %s\n' "$model" "$effort"
}

report_both_exhausted() {
  printf '[antigravity-rescue] both Antigravity pools exhausted (Gemini %s%% resets %s; Claude/GPT %s%% resets %s)\n' \
    "$GEMINI_PERCENT" "$GEMINI_RESET" "$CLAUDE_GPT_PERCENT" "$CLAUDE_GPT_RESET"
  return "$POOLS_EXHAUSTED_EXIT"
}

switch_pool() {
  local from=$1 model=$2 slug
  slug=$(equivalent_slug "$(other_pool "$from")" "$(task_class "$model")")
  printf '[antigravity-rescue] %s pool at %s%%, running on %s instead\n' "$(pool_label "$from")" "$(percent_of "$from")" "$slug"
  print_choice "$slug" ""
}

choose_pool() {
  local model=$1 pool
  pool=$(pool_of "$model")
  is_exhausted "$pool" || { print_choice "$model" "$OPT_EFFORT"; return 0; }
  is_exhausted "$(other_pool "$pool")" && { report_both_exhausted; return; }
  switch_pool "$pool" "$model"
}

# After a mid-run quota abort the run's own pool is known to be out, whatever its gauge says.
choose_other_pool() {
  local model=$1 target
  target=$(other_pool "$(pool_of "$model")")
  is_exhausted "$target" || { print_choice "$(equivalent_slug "$target" "$(task_class "$model")")" ""; return 0; }
  printf '[antigravity-rescue] %s pool at %s%% (resets %s), no other pool to rerun on\n' \
    "$(pool_label "$target")" "$(percent_of "$target")" "$(reset_of "$target")"
  return "$POOLS_EXHAUSTED_EXIT"
}

preflight() {
  local model
  require_agy || return
  require_deny_rules || return
  read_usage || return
  model=${OPT_MODEL:-$(default_model)}
  print_gauges
  [ "$OPT_OTHER_POOL" = 1 ] && { choose_other_pool "$model"; return; }
  choose_pool "$model"
}

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

sleep_while_running() {
  local pid=$1 i
  for ((i = 0; i < POLLS_PER_WATCH; i++)); do
    sleep "$POLL_STEP"
    kill -0 "$pid" 2>/dev/null || return 1
  done
}

watch_child() {
  local pid=$1 existing=$2 bytes=$3 chars=$4 model=$5 log="" threshold
  threshold=$(abort_threshold)
  # A run that ends on its own keeps its own output and exit code, even with quota lines in its log.
  while sleep_while_running "$pid"; do
    [ -n "$log" ] || log=$(find_own_log "$existing" "$bytes" "$chars") || log=""
    quota_exhausted "$log" "$threshold" || continue
    stop_child "$pid"
    report_quota "$log" "$model"
    return "$QUOTA_EXIT"
  done
  wait "$pid"
}

watch_command() {
  [ $# -ge 1 ] || usage_error "watch needs the agy binary"
  local existing lengths model
  existing=$(list_run_logs)
  lengths=$(prompt_lengths -p "$@") || lengths=""
  model=$(arg_after --model "$@") || model="the default model"
  trap 'stop_child "$CHILD_PID"; exit 143' TERM INT HUP
  "$@" &
  CHILD_PID=$!
  [ -n "$lengths" ] || { wait "$CHILD_PID"; return; }
  # shellcheck disable=SC2086
  watch_child "$CHILD_PID" "$existing" $lengths "$model"
}

run_task() {
  local task prompt args
  task=$(cat)
  [ -n "${task//[[:space:]]/}" ] || usage_error "no task on stdin"
  require_agy || return
  require_deny_rules || return
  prompt=$(printf '%s\n\n%s' "$task" "$CONSTRAINTS")
  args=(-p "$prompt" --add-dir "$PWD" --dangerously-skip-permissions --disable-slash-commands --output-format text --print-timeout 9m)
  [ -n "$OPT_MODEL" ] && args+=(--model "$OPT_MODEL")
  [ -n "$OPT_EFFORT" ] && is_gemini_slug "$OPT_MODEL" && args+=(--effort "$OPT_EFFORT")
  [ "$OPT_CONTINUE" = 1 ] && args+=(--continue)
  export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes"
  watch_command "$AGY" "${args[@]}"
}

main() {
  local command=${1:-}
  [ $# -gt 0 ] && shift
  case $command in
    preflight) parse_options "$@"; preflight ;;
    run) parse_options "$@"; run_task ;;
    watch) watch_command "$@" ;;
    *) usage_error "usage: agy-forward.sh preflight|run|watch [options]" ;;
  esac
}

main "$@"
