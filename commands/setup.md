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

Step 3 — Authentication probe

```bash
"$AGY" -p "Reply with exactly one word: ready" --output-format text --print-timeout 60s --disable-slash-commands
```

- stdout `ready`, exit 0 → authenticated and working.
- exit 1 with `authentication required` or `not logged into Antigravity` on stderr → tell the user to run `agy` once interactively (browser sign-in; over SSH it prints a URL and asks for a code) and then rerun `/antigravity:setup`.
- A message mentioning quota, rate limit, `RESOURCE_EXHAUSTED` or credits → report that the Antigravity quota is currently exhausted; remaining quota is visible with `/usage` inside an interactive `agy` session.

Step 4 — Deny rules (the safety net)

Headless `agy` cannot prompt, so the subagent runs it with `--dangerously-skip-permissions`; user-configured `permissions.deny` rules still win under that flag. Read `~/.gemini/antigravity-cli/settings.json` (it may not exist yet) and compare `permissions.deny` with the list in `${CLAUDE_PLUGIN_ROOT}/docs/permissions.json`.

- Every rule present → OK.
- Missing or partial → `AskUserQuestion` once: `Merge the recommended deny rules (Recommended)`, `Show me the rules first`, `Skip`. On merge: add only the missing entries to `permissions.deny`, keep every other key and existing rule untouched, create the file if absent, and write valid JSON (backslashes in the regex rules must stay escaped as `\\b` and `\\s` in the file). Tell the user these rules are global — they also block those commands in interactive `agy` sessions, which is intended: they only cover destructive or shared-state commands (`git push`, `git reset`, `git clean`, `rm`/`rmdir`/`del`/`rd`/`Remove-Item`, `sudo`, writes under `.git/`).
- Skipped → say plainly that the subagent will refuse to run until a `permissions.deny` block exists.

Step 5 — Verify the deny rules bite (only if Step 4 ended OK)

```bash
"$AGY" -p "Run exactly this shell command and print its output: git push --dry-run origin HEAD. If it is blocked, reply BLOCKED and quote the reason." --add-dir "$PWD" --dangerously-skip-permissions --disable-slash-commands --output-format text --print-timeout 90s
```

Expected: `BLOCKED` with `Matches user-configured deny rule`. Anything else → report that the deny rules are not being applied and stop recommending delegation until fixed.

Step 6 — Models

```bash
"$AGY" models
```

List them and note the picks the subagent suggests: `gemini-3.8-flash-low|medium` for mechanical work, `gemini-3.1-pro-high` or `claude-opus-4-6-thinking` for diagnosis and reasoning. With no `--model` passed, agy uses its configured default (`/model <name>` inside an interactive session changes it).

Step 7 — Consolidated report

One short block: binary path and on-PATH state, version vs the 1.1.28 floor, auth state, deny-rule state and the Step 5 result, and how to delegate (`/antigravity:rescue <task>`, or let the `antigravity-rescue` subagent fire proactively).
