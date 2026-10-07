# CLAUDE.md snippet

Paste the block below into your `~/.claude/CLAUDE.md` (or a project
`CLAUDE.md`) to make Claude Code delegate to Antigravity proactively. Adjust
the triggers to your setup. See
[docs/delegation-guide.md](delegation-guide.md) for the full notes.

```markdown
# Antigravity CLI delegation (antigravity plugin)

Antigravity (`agy`) runs frontier models for reasoning (Gemini 3.1 Pro,
Claude Sonnet/Opus 4.6) and cheap Flash models for mechanical work (Gemini
3.8 Flash, GPT-OSS 120B) on its own Google quota, selectable per call.
Subagent `antigravity:antigravity-rescue`; commands `/antigravity:rescue`,
`/antigravity:setup`. The delegate is agentic: it reads and edits files and
runs build/test/git commands in the repo, with edits auto-approved and a
global deny list blocking destructive commands.

| Trigger | Action |
|---|---|
| Reasoning-shaped task — build fixing, multi-file refactor, root-cause diagnosis | `antigravity:antigravity-rescue` in background, `--model gemini-3.1-pro-high` or `--model claude-opus-4-6-thinking` for the hardest cases |
| Mechanical task — specs, renames, boilerplate, cleanup | `antigravity:antigravity-rescue` in background, `--model gemini-3.8-flash-low` |
| Review or second opinion where the working tree must stay untouched — review a diff, cross-check a diagnosis | `antigravity:antigravity-rescue` in background with `--read-only`, frontier model (runs in a throwaway worktree; attempted edits are listed and discarded) |
| Output starts with `[antigravity-rescue] ... pool at NN%, running on ...` | The subagent read both gauges (free `agy -p "/usage"`) and switched pools; pass the result through |
| Output starts with `[antigravity-rescue] both Antigravity pools exhausted` or shows an auth error | Nothing ran. Stop and report it so the user can choose another route, and say so once |

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
- Two weekly quota pools: Gemini, and Claude + GPT-OSS. The subagent checks
  both before every run and picks the pool that has room; to see them
  yourself: `MSYS_NO_PATHCONV=1 agy -p "/usage"` (free). Pin a pool with
  `--model claude-sonnet-4-6` (reasoning),
  `--model claude-opus-4-6-thinking` (hardest reasoning) or
  `--model gpt-oss-120b-medium` (mechanical). `--effort` only with Gemini
  slugs.
- Launch in the background and keep working. WIP cap 3–5 concurrent
  delegations. Kill-switch: 3 failed iterations on the same task → stop
  retrying and bring it back inline.
- If several delegates are in use, the order — which delegate handles what —
  is defined by the user here in this file.
```
