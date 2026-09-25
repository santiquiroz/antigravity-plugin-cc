---
description: Check that Google Antigravity CLI (agy) is installed, on PATH, authenticated, and carries the deny rules this plugin relies on
argument-hint: ""
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

Run these steps in order and finish with one consolidated status block. Never print token or credential values.

Step 1 — Locate the binary

```bash
AGY=$(command -v agy 2>/dev/null || ls "${LOCALAPPDATA//\\//}/agy/bin/agy.exe" "$HOME/.gemini/bin/agy.exe" "$HOME/.gemini/bin/agy" "$HOME/.local/bin/agy" 2>/dev/null | head -1); echo "${AGY:-NOT FOUND}"
```

- Not found → use `AskUserQuestion` exactly once with two options: `Install Antigravity CLI (Recommended)` and `Skip for now`. Install commands: Windows PowerShell `irm https://antigravity.google/cli/install.ps1 | iex`; macOS/Linux `curl -fsSL https://antigravity.google/cli/install.sh | bash`. Rerun Step 1 afterwards. If the user skips, jump to the report.
- Found only through a fallback path (`command -v agy` failed) → report that `agy` is not on PATH and offer to run `"$AGY" install`, which appends the install dir to the shell profile / user PATH (new shells only). The subagent resolves the fallback paths itself, so delegation works either way.

Step 2 — Version gate

```bash
"$AGY" --version
```

Floor: **1.1.28** — headless runs return partial output on `--print-timeout` instead of failing, and denied tool actions are reported with a stable stderr marker. Older → recommend `agy update` and continue the checks.

Step 3 — Models and quota (before any paid probe)

```bash
"$AGY" models
MSYS_NO_PATHCONV=1 "$AGY" -p "/usage" --output-format text --print-timeout 30s
MSYS_NO_PATHCONV=1 "$AGY" -p "/model" --output-format text --print-timeout 30s
```

The two `-p` calls are answered by print mode itself (read-only slash commands, agy ≥ 1.1.11): no agent turn, no quota spent. `MSYS_NO_PATHCONV=1` stops Git Bash from rewriting `/usage` into a Windows path (which would send it to the model as a paid turn). `/usage` prints one line per weekly pool — Gemini models, and Claude + GPT-OSS models — with the percentage left and the reset time; `/model` prints the default slug used when no `--model` is passed. They run before Steps 4 and 6 because those probes are model turns: on a pool at 0 % agy does not fail fast, it retries until the print timeout and ends with `status: ERROR` / `The stream was interrupted`, which says nothing about auth or deny rules.

Pick the probe model for Steps 4 and 6 from the gauges: Gemini above 2 % → `gemini-3.8-flash-low`; otherwise Claude/GPT above 2 % → `gpt-oss-120b-medium`; both at 2 % or less → skip Steps 4 and 6 and mark both `skipped: quota` with the reset times. `/usage` output mentioning `authentication required` or `not logged into Antigravity` → handle it as the Step 4 auth failure and skip Steps 4 and 6. `/usage` unreadable for any other reason → no probe model (agy's default) and note that the probe results may be inconclusive. Steps 4 and 6 write it literally in place of `<probe-model>` (shell variables do not survive between Bash calls) and drop `--model <probe-model>` when there is none.

List the models and note the picks the subagent suggests, by quota pool (Gemini models and Claude + GPT-OSS models are metered on separate weekly quotas): Gemini pool `gemini-3.8-flash-low|medium` for mechanical work and `gemini-3.1-pro-high` for reasoning; Claude/GPT pool `gpt-oss-120b-medium` for mechanical work, `claude-sonnet-4-6` for reasoning and `claude-opus-4-6-thinking` for the hardest cases. `--effort` is only accepted with Gemini slugs. With no `--model` passed, agy uses its configured default (`/model <name>` inside an interactive session changes it). The subagent runs the same `/usage` preflight before every delegation and picks the pool that has room; a pool at 0 % does not fail fast (agy retries with backoff until the print timeout), which is why the preflight exists.

Step 4 — Authentication probe (skip when Step 3 marked it `skipped: quota`)

```bash
"$AGY" -p "Reply with exactly one word: ready" --model <probe-model> --output-format text --print-timeout 60s --disable-slash-commands
```

- stdout `ready`, exit 0 → authenticated and working.
- exit 1 with `authentication required` or `not logged into Antigravity` on stderr → tell the user to run `agy` once interactively (browser sign-in; over SSH it prints a URL and asks for a code) and then rerun `/antigravity:setup`.
- A message mentioning quota, rate limit, `RESOURCE_EXHAUSTED` or credits, or `status: ERROR` / `The stream was interrupted` / `[agy] print timeout` → auth `inconclusive (quota)`: the probe model's pool is out even if the gauge showed room (per-model 429s never show there). Report the Step 3 gauges.

Step 5 — Deny rules (the safety net)

Headless `agy` cannot prompt, so the subagent runs it with `--dangerously-skip-permissions`; user-configured `permissions.deny` rules still win under that flag. Read `~/.gemini/antigravity-cli/settings.json` (it may not exist yet) and compare `permissions.deny` with the list in `${CLAUDE_PLUGIN_ROOT}/docs/permissions.json`.

- Every rule present → OK.
- Missing or partial → `AskUserQuestion` once: `Merge the recommended deny rules (Recommended)`, `Show me the rules first`, `Skip`. On merge: add only the missing entries to `permissions.deny`, keep every other key and existing rule untouched, create the file if absent, and write valid JSON (backslashes in the regex rules must stay escaped as `\\b` and `\\s` in the file). Tell the user these rules are global — they also block those commands in interactive `agy` sessions, which is intended: they only cover destructive or shared-state commands (`git push`, `git reset`, `git clean`, `rm`/`rmdir`/`del`/`rd`/`Remove-Item`, `sudo`, writes under `.git/`).
- Skipped → say plainly that the subagent will refuse to run until `permissions.deny` holds the critical rules (`git push`, `git reset`, `git clean`, `rm`, `rmdir`, `del`, `rd`, `Remove-Item`, `write_file(.git/)`).

Step 6 — Verify the deny rules bite (only if Step 5 ended OK and Step 3 did not mark it `skipped: quota`)

The probe command deletes a file that does not exist and touches no network, so it is harmless even if the rule does not bite; the git variables keep any git call from prompting for credentials.

```bash
GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes' "$AGY" -p "Run exactly this shell command and print its output: rm -f ./.agy-deny-probe-nonexistent. If it is blocked, reply BLOCKED and quote the reason." --model <probe-model> --add-dir "$PWD" --dangerously-skip-permissions --disable-slash-commands --output-format text --print-timeout 90s
```

- `BLOCKED` with `Matches user-configured deny rule` → the deny rules are applied.
- `status: ERROR`, `The stream was interrupted`, `[agy] print timeout`, or a message mentioning quota, rate limit, `RESOURCE_EXHAUSTED` or credits → `inconclusive (quota)`: the model never ran the command, so this says nothing about the deny rules. Report it with the reset time and suggest rerunning `/antigravity:setup` after it; do not report the rules as not applied.
- Anything else (the command ran, or it was refused without the deny-rule marker) → report that the deny rules are not being applied and stop recommending delegation until fixed.

Step 7 — Consolidated report

One short block: binary path and on-PATH state, version vs the 1.1.28 floor, auth state (or `skipped: quota` / `inconclusive (quota)`), deny-rule state and the Step 6 result (`BLOCKED`, `not applied`, `inconclusive (quota)` or `skipped: quota`), both quota gauges with their reset times and the default model, and how to delegate (`/antigravity:rescue <task>`, or let the `antigravity-rescue` subagent fire proactively).
