# CLAUDE.md snippet

Paste the block below into your `~/.claude/CLAUDE.md` (or a project
`CLAUDE.md`) to make Claude Code delegate to Antigravity proactively. Adjust
the trigger table to the lanes you actually run — the block assumes a primary
reasoning delegate (e.g. the codex plugin) and a mechanical delegate (e.g. the
copilot plugin) already exist, and slots Antigravity in as the second frontier
lane. See [docs/delegation-guide.md](delegation-guide.md) for the full split.

```markdown
# Antigravity CLI delegation (antigravity plugin)

Antigravity (`agy`) is a frontier-capable second lane with its own Google
quota — Gemini 3.1 Pro, Gemini 3.8 Flash, Claude Sonnet/Opus 4.6, GPT-OSS
120B, selectable per call. Subagent `antigravity:antigravity-rescue`;
commands `/antigravity:rescue`, `/antigravity:setup`. The delegate is
agentic: it reads and edits files and runs build/test/git commands in the
repo, with edits auto-approved and a global deny list blocking destructive
commands.

| Trigger | Action |
|---|---|
| Primary reasoning delegate (e.g. Codex) is quota-exhausted or busy and the task needs reasoning — build fixing after a failed attempt, multi-file refactor, root-cause diagnosis | `antigravity:antigravity-rescue` in background, `--model gemini-3.1-pro-high` or `--model claude-opus-4-6-thinking` |
| Bounded task where an independent second opinion is worth one run — review a diff, propose an alternative fix, cross-check a diagnosis | `antigravity:antigravity-rescue` in background, frontier model |
| Mechanical lane (e.g. Copilot) is quota-exhausted and the task is mechanical — specs, renames, boilerplate, cleanup | `antigravity:antigravity-rescue` in background, `--model gemini-3.8-flash-low` |
| agy reports quota on the Gemini pool | The subagent already reran once on the Claude/GPT pool (Sonnet 4.6 / Opus 4.6 Thinking / GPT-OSS 120B, separate weekly quota); pass the result through |
| agy reports quota on the Claude/GPT pool too, or an auth error | Do not retry. Fall back to the next lane or inline, and say so once |

Never delegate: domain logic, business rules, architecture decisions,
anything where the WHY lives in this conversation.

Rules:
- The task text must be self-contained — file paths, signatures, acceptance
  criteria. The delegate does not see this conversation.
- Delegate edits are auto-approved inside the repo. Review `git diff` before
  committing; the orchestrator owns the commit.
- Run `/antigravity:setup` once per machine. It merges deny rules (`git
  push`/`reset`/`clean`, `rm`/`del`/`Remove-Item`, `sudo`, writes under
  `.git/`) into `~/.gemini/antigravity-cli/settings.json`; the subagent
  refuses to run without them.
- Two weekly quota pools: Gemini, and Claude + GPT-OSS. When the Gemini
  gauge is low, start on the second pool: `--model claude-sonnet-4-6`
  (reasoning), `--model claude-opus-4-6-thinking` (hardest reasoning) or
  `--model gpt-oss-120b-medium` (mechanical). `--effort` only with Gemini
  slugs.
- Launch in the background and keep working. WIP cap 3–5 concurrent
  delegations. Kill-switch: 3 failed iterations on the same task → stop
  retrying that lane.
```
