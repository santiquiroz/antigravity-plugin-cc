# Multi-Agent Delegation Guide

How to make Claude Code delegate work to Antigravity CLI (this plugin) — a
frontier-capable delegate with its own Google quota — so the main Claude
thread stays focused on the work only it can do. Claude Code stays the
orchestrator.

## What to delegate

| Work | Where it goes | Examples |
|---|---|---|
| Reasoning-shaped, self-contained | Antigravity on a frontier model | Root-cause diagnosis, build fixing, multi-file refactors changing control flow |
| Independent second pass | Antigravity on a frontier model (`--read-only` for reviews) | Review a diff, alternative fix, cross-check a diagnosis |
| Mechanical, zero-domain-context | Antigravity on Flash | Simple CRUD/mapping test specs, mechanical renames across 3+ files, dead code / unused import cleanup, boilerplate shells |
| Keep inline (never delegate) | Tasks where the WHY lives in your conversation | Domain logic, business rules, architecture and feature design, refactors needing full codebase context |

Rule of thumb: if the delegate needs to understand *why*, keep it inline. If it
is self-contained reasoning or a second pass, delegate it on a frontier model.
If it is pattern boilerplate, delegate it on Flash.

## Choosing a model per task

Antigravity meters **Gemini models** on one weekly quota and **Claude + GPT-OSS
models** on a separate one (Antigravity app → Settings → Models & Usage shows
both gauges). Pick the model by task class and by which pool has room:

| Task class | Gemini pool | Claude/GPT pool |
|---|---|---|
| mechanical (specs, renames, boilerplate) | `gemini-3.8-flash-low` / `-medium` | `gpt-oss-120b-medium` |
| diagnosis, build fixing, refactor | `gemini-3.1-pro-high` | `claude-sonnet-4-6` |
| second opinion, hardest reasoning | `gemini-3.1-pro-high` | `claude-opus-4-6-thinking` |
| nothing passed | agy's configured default (`/model <name>` in an interactive session) | — |

`--effort low|medium|high` only applies to Gemini slugs; agy rejects the flag
for Claude and GPT-OSS models, whose effort is part of the slug.

Run `agy models` to print the full list of available model slugs. Passing an
unknown slug exits 1 immediately with the list of valid models.

## The default-delegate discipline

- Before writing any code, decide explicitly: Antigravity or inline. Inline is
  only for tasks on the never-delegate list or trivial edits (<5 lines, 1 file)
  where coordinating a delegation costs more than doing it.
- The main thread acts as orchestrator and reviewer: define the subtask
  contract, launch the delegation in the background, review the diff when it
  returns. Never idle while a delegation runs — continue with the next
  subtask.

## The parallel pattern

```
Claude: writes SomeHandler (domain logic — inline, never delegated)
  → immediately launches /antigravity:rescue --background --model gemini-3.1-pro-high "diagnose and fix test runner timeout"
  → immediately launches /antigravity:rescue --background --model gemini-3.8-flash-low "generate boilerplate tests for SomeHandler"
Claude: continues with the next task while delegations run
```

- WIP cap: 3–5 concurrent background delegations. Beyond that, coordination
  overhead and unreviewed compounding mistakes outweigh the parallelism gain.
- Kill-switch: after 3 stuck/failed iterations on the same delegated task,
  stop retrying and bring it back inline. Do not loop indefinitely.

## Safety model

Headless `agy` cannot prompt the user for tool approvals. Tools that require
confirmation are soft-denied unless `--dangerously-skip-permissions` is passed,
so the forwarder passes that flag on every invocation.

- User-configured `permissions.deny` rules still win under that flag
  (`Permission denied for command(...). Matches user-configured deny rule.`).
- `/antigravity:setup` merges the recommended deny list into
  `~/.gemini/antigravity-cli/settings.json`: `git push`, `git reset`, `git clean`,
  `rm`/`rmdir`/`del`/`rd`/`Remove-Item`, `sudo`, and `write_file(.git/)`.
- The `antigravity-rescue` subagent refuses to run (exit 78) unless
  `permissions.deny` holds every critical rule: `git push`, `git reset`,
  `git clean`, `rm`, `rmdir`, `del`, `rd`, `Remove-Item` and
  `write_file(.git/)`.
- Deny rules are global: they also apply to interactive `agy` sessions.
- Under `--dangerously-skip-permissions`, web fetch, browser, and MCP tools are
  auto-approved. Never delegate tasks that process untrusted content.
- Pattern denies are best effort, like any CLI allow/deny list. Always review
  `git diff` before committing; the delegate leaves changes in the working
  tree and is told not to commit — prompt text, not a deny rule; check `git log` and `git stash list` too.
- After each run in a git repository the forwarder compares `HEAD`, the
  branch, the stash count, the repository's git config (not `~/.gitconfig`)
  and the hooks directory with a
  snapshot taken before it, and appends
  `[antigravity-rescue] WARNING: <what changed> — review before your next git command`
  for each change. It is read-only and reverts nothing. Act on it before your
  next git command: a hook or alias the delegate planted runs on your next
  `git commit`.

## Quota handling

Delegated runs hit rate limits and quota caps. Never let a quota error silently
kill a task.

**Detection:** scan `agy` output for `quota`, `rate limit`,
`RESOURCE_EXHAUSTED`, `429`, or `credits`. Authentication errors
(`authentication required` or `not logged into Antigravity`) indicate missing
credentials; run `/antigravity:setup` to re-authenticate.

**How the subagent handles it:**

- Before every run it reads both weekly gauges with a free `agy -p "/usage"`
  and runs on the pool that has room (`claude-sonnet-4-6`,
  `claude-opus-4-6-thinking` for the hardest reasoning, `gpt-oss-120b-medium`
  for mechanical work; or the Gemini equivalents when the Claude/GPT pool is
  the empty one), announcing the switch in the first output line. Pass it
  through; no action needed from the orchestrator.
- When both pools are out it returns `[antigravity-rescue] both Antigravity
  pools exhausted` without running: stop and report it so the user can choose
  another route. Never retry an `agy` quota error in a loop.

Tell the user in one line when a fallback happened — which pool picked the task
up, or that the task did not run. One line, no drama.

If quota is exhausted in a session: stop auto-delegating for the rest of the
session, handle everything inline, and mention this once. Antigravity quotas
refresh on a 5-hour window (subject to a weekly ceiling on the free tier);
`MSYS_NO_PATHCONV=1 agy -p "/usage"` prints the remaining quota per pool for free (also `/usage` inside an interactive session). The two pools (Gemini; Claude + GPT-OSS) are metered separately, each with its own weekly gauge in the Antigravity app under Settings → Models & Usage.

## Second opinions, not second drafts

Use Antigravity when a tricky change or ambiguous diagnosis benefits from an
independent, bounded pass — for reviews, `--read-only` runs it in a throwaway
worktree so the working tree stays untouched. Never run two delegations on the
same files at the same time — coordinate sequential passes or run diff-only
review passes so changes do not collide in the working tree.

## Using it with other delegates

This plugin assumes no place in a lineup: if you run several delegation
plugins, the order — which delegate handles what, and where a task goes when
one reports quota or auth errors — is yours to define in your `CLAUDE.md`.
