# Multi-Agent Delegation Guide

How to make Claude Code delegate work to Antigravity CLI (this plugin) as a
frontier-capable second lane alongside a primary reasoning delegate (e.g. the
codex plugin's `codex-rescue`) and a mechanical delegate (e.g. the copilot
plugin's `copilot-rescue`) — so the main Claude thread stays focused on the work
only it can do. Claude Code stays the orchestrator.

## Which setup do you have?

This guide describes three common configurations:

- **Full 3-lane setup**: Claude Code orchestrates, a primary reasoning delegate
  (e.g. Codex) takes primary reasoning work, a mechanical delegate (e.g.
  Copilot) takes routine boilerplate, and Antigravity (this plugin) acts as a
  frontier-capable second lane for reasoning fallbacks, independent second
  opinions, and Flash fallbacks when mechanical quota runs out.
- **Antigravity + mechanical delegate (no Codex)**: Antigravity becomes the
  reasoning lane (running `gemini-3.1-pro-high` or `claude-opus-4-6-thinking`)
  for diagnosis, build fixing, and refactors, while the mechanical delegate
  handles boilerplate and specs.
- **Antigravity alone**: Antigravity takes both reasoning-shaped delegable work
  (on `gemini-3.1-pro-high`) and mechanical work (on `gemini-3.8-flash-low`).
  Everything on the never-delegate list stays inline with Claude.

## The core split

| Lane | Owns | Examples |
|---|---|---|
| **Primary reasoning delegate** (e.g. Codex) | Deep diagnosis, multi-step build fixing, architecture-adjacent code | Complex build errors after failed fixes, logic-bearing services, multi-file refactors changing control flow |
| **Antigravity (this plugin)** | Frontier fallback, second opinions, Flash mechanical fallback | Fallback when the primary reasoning delegate is quota-exhausted or busy; bounded second-opinion runs (review a diff, alternative fix, cross-check a diagnosis); mechanical work on Flash when the mechanical lane is out of quota |
| **Mechanical delegate** (e.g. Copilot) | Purely mechanical, zero-domain-context work | Simple CRUD/mapping test specs, mechanical renames across 3+ files, dead code / unused import cleanup, boilerplate shells |
| **Keep inline (never delegate)** | Tasks where the WHY lives in your conversation | Domain logic, business rules, architecture and feature design, refactors needing full codebase context |

Rule of thumb: if the delegate needs to understand *why*, keep it inline. If it
is self-contained reasoning or a second opinion, delegate to a frontier lane.
If it is pattern boilerplate, delegate to a mechanical or Flash lane.

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

- Before writing any code, decide the lane explicitly: primary reasoning
  delegate, Antigravity, mechanical delegate, or inline. Inline is only for
  tasks on the never-delegate list or trivial edits (<5 lines, 1 file) where
  coordinating a delegation costs more than doing it.
- The main thread acts as orchestrator and reviewer: define the subtask
  contract, launch the delegation in the background, review the diff when it
  returns. Never idle while a delegation runs — continue with the next
  subtask.

## The parallel pattern

```
Claude: writes SomeHandler (domain logic — inline, never delegated)
  → immediately launches reasoning delegate in background: "fix build errors in related module"
  → immediately launches /antigravity:rescue --background --model gemini-3.1-pro-high "diagnose and fix test runner timeout"
  → immediately launches /copilot:rescue --background "generate boilerplate tests for SomeHandler"
Claude: continues with the next task while delegations run
```

- WIP cap: 3–5 concurrent background delegations. Beyond that, coordination
  overhead and unreviewed compounding mistakes outweigh the parallelism gain.
- Kill-switch: after 3 stuck/failed iterations on the same delegated task,
  stop retrying that delegate. Hand it to the other lane once, or bring it
  back inline. Do not loop indefinitely.

## Safety model

Headless `agy` cannot prompt the user for tool approvals. Tools that require
confirmation are soft-denied unless `--dangerously-skip-permissions` is passed,
so the forwarder passes that flag on every invocation.

- User-configured `permissions.deny` rules still win under that flag
  (`Permission denied for command(...). Matches user-configured deny rule.`).
- `/antigravity:setup` merges the recommended deny list into
  `~/.gemini/antigravity-cli/settings.json`: `git push`, `git reset`, `git clean`,
  `rm`/`rmdir`/`del`/`rd`/`Remove-Item`, `sudo`, and `write_file(.git/)`.
- The `antigravity-rescue` subagent refuses to run without a `permissions.deny`
  block in settings.
- Deny rules are global: they also apply to interactive `agy` sessions.
- Under `--dangerously-skip-permissions`, web fetch, browser, and MCP tools are
  auto-approved. Never delegate tasks that process untrusted content.
- Pattern denies are best effort, like any CLI allow/deny list. Always review
  `git diff` before committing; the delegate leaves changes in the working
  tree and never commits.

## Quota fallback chain

Delegates hit rate limits and quota caps. Never let a quota error silently
kill a task.

**Detection:** scan `agy` output for `quota`, `rate limit`,
`RESOURCE_EXHAUSTED`, `429`, or `credits`. Authentication errors
(`authentication required` or `not logged into Antigravity`) indicate missing
credentials; run `/antigravity:setup` to re-authenticate.

**The chain:**

1. **Primary reasoning delegate quota out**: fail over to Antigravity on a
   frontier model (`gemini-3.1-pro-high` or `claude-opus-4-6-thinking`).
2. **Mechanical delegate quota out**: fail over to Antigravity on Flash
   (`gemini-3.8-flash-low` or `gemini-3.8-flash-medium`).
3. **Antigravity Gemini pool out**: the subagent itself reruns the task once on
   the Claude/GPT pool (`claude-sonnet-4-6`, `claude-opus-4-6-thinking` for the
   hardest reasoning, `gpt-oss-120b-medium` for mechanical work) and prefixes
   the result with `[antigravity-rescue] Gemini pool exhausted, reran on <slug>`.
   Pass it through; no action needed from the orchestrator.
4. **Both Antigravity pools out**: try the other delegate lane once if compatible;
   otherwise handle the task inline with Claude. Never retry an `agy` quota
   error in a loop.

Tell the user in one line when a fallback happened — which delegate failed and
which one picked it up, or that Claude took over inline. One line, no drama.

If every lane is exhausted in a session: stop auto-delegating for the rest of
the session, handle everything inline, and mention this once. Antigravity
quotas refresh on a 5-hour window (subject to a weekly ceiling on the free tier);
`/usage` inside an interactive `agy` session shows the remaining quota. The two pools (Gemini; Claude + GPT-OSS) are metered separately, each with its own weekly gauge in the Antigravity app under Settings → Models & Usage.

## Second opinions, not second drafts

Use Antigravity when a tricky change or ambiguous diagnosis benefits from an
independent, bounded pass. Feed it the same self-contained contract given to
the primary delegate, inspect both outputs, and let the orchestrator reconcile
the approaches. Never run two delegates on the same files at the same time —
coordinate sequential passes or run diff-only review passes so changes do not
collide in the working tree.
