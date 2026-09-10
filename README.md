# antigravity-plugin-cc

Delegate coding tasks from [Claude Code](https://claude.com/claude-code) to
[Google Antigravity CLI](https://antigravity.google/docs/cli/overview) (`agy`)
in headless mode.

Claude Code stays the orchestrator — it writes the domain logic, defines each
subtask contract, and reviews the diffs. Antigravity is a **frontier-capable
second lane with its own quota**: `agy` runs Gemini 3.1 Pro, Gemini 3.8
Flash, Claude Sonnet 4.6, Claude Opus 4.6 Thinking and GPT-OSS 120B,
selectable per call, and the delegate is agentic — it reads and edits files
and runs build/test/git commands in your repo itself. Use it when your primary
reasoning delegate (e.g. Codex) is out of credits, when a bounded task
deserves an independent second opinion, or on a Flash model for mechanical
work when your mechanical lane (e.g. Copilot) is out of quota.

Inspired by the structure of [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc)
and sibling of [copilot-plugin-cc](https://github.com/santiquiroz/copilot-plugin-cc),
[ollama-plugin-cc](https://github.com/santiquiroz/ollama-plugin-cc) and
[bipolar-plugin-cc](https://github.com/santiquiroz/bipolar-plugin-cc).
**Not affiliated with Google, OpenAI, GitHub, or Anthropic.**

> Lea esto en español: [README.es.md](README.es.md)

## Where it sits in a delegation chain

| Tier | Delegate | Good for |
|---|---|---|
| trivial | [ollama-plugin-cc](https://github.com/santiquiroz/ollama-plugin-cc) | one-shot text transforms on a small local model |
| medium (local) | [bipolar-plugin-cc](https://github.com/santiquiroz/bipolar-plugin-cc) | bounded agentic tasks on a big local model |
| mechanical | [copilot-plugin-cc](https://github.com/santiquiroz/copilot-plugin-cc) | boilerplate, renames, simple specs, cleanup |
| **frontier, second lane** | **antigravity-plugin-cc (this)** | Codex fallback, second opinions, mechanical work on Flash when Copilot is out |
| frontier, primary | Codex / your main reasoning delegate | architecture-adjacent implementation, deep diagnosis |

Only the lanes you install exist; the plugin works alone too.

## Requirements

- Claude Code
- [Antigravity CLI](https://antigravity.google/docs/cli/install) ≥ **1.1.28**,
  signed in once interactively (Google account — free tier has a weekly
  ceiling with 5-hour refresh windows; Google AI Pro/Ultra plans raise it).
  Windows: `irm https://antigravity.google/cli/install.ps1 | iex` —
  macOS/Linux: `curl -fsSL https://antigravity.google/cli/install.sh | bash`

## Install

In Claude Code:

```
/plugin marketplace add santiquiroz/antigravity-plugin-cc
/plugin install antigravity@antigravity-plugin-cc
```

Then, once per machine:

```
/antigravity:setup
```

Setup locates the binary (PATH or the known install dirs), checks the version
floor and authentication, merges the deny rules this plugin relies on into
`~/.gemini/antigravity-cli/settings.json` (asking first), verifies they bite
with a `git push --dry-run` probe, and lists the available models.

## Usage

Explicit delegation:

```
/antigravity:rescue diagnose why `npm test` fails in src/services/user-mapper.spec.ts and fix the spec
/antigravity:rescue --background --model gemini-3.8-flash-low generate boilerplate specs for src/services/user-mapper.ts (signatures pasted below) ...
/antigravity:rescue --model claude-opus-4-6-thinking second opinion: review the diff of HEAD for race conditions, report only, do not edit
```

Proactive delegation: the `antigravity-rescue` agent describes itself so Claude
Code picks it on its own when the triggers match. To wire it into your own
delegation rules, paste the block from
[docs/claude-md-snippet.md](docs/claude-md-snippet.md) into your `CLAUDE.md`.
The multi-lane split, the parallel pattern, WIP caps and the quota fallback
chain live in [docs/delegation-guide.md](docs/delegation-guide.md).

### Two quota pools

Antigravity meters **Gemini models** on one weekly quota and **Claude + GPT-OSS
models** on a separate one (Antigravity app → Settings → Models & Usage shows
both gauges). The subagent treats them as two lanes inside the same CLI:

| Task class | Gemini pool | Claude/GPT pool |
|---|---|---|
| mechanical (specs, renames, boilerplate) | `gemini-3.8-flash-low` / `-medium` | `gpt-oss-120b-medium` |
| diagnosis, build fixing, refactor | `gemini-3.1-pro-high` | `claude-sonnet-4-6` |
| second opinion, hardest reasoning | `gemini-3.1-pro-high` | `claude-opus-4-6-thinking` |
| nothing passed | agy's configured default (`/model <name>` in an interactive session) | — |

When a run on a Gemini model dies on quota (`quota`, `rate limit`,
`RESOURCE_EXHAUSTED`, `429`, `weekly limit`), the subagent reruns the same task
**once** on the Claude/GPT pool and prefixes the result with
`[antigravity-rescue] Gemini pool exhausted, reran on <slug>`. A run already on
the Claude/GPT pool that hits quota is returned verbatim: both pools are out.
Pass `--model claude-sonnet-4-6` (or say the Gemini pool is low) to start on
the second pool directly.

`--effort low|medium|high` only applies to Gemini slugs; Claude and GPT-OSS
slugs carry their effort in the name and agy rejects the flag for them.
`agy models` prints the current slugs; an unknown slug exits 1 immediately.

## What the forwarder actually runs

```bash
TASK=$(cat <<'EOF_TASK'
<your task, verbatim>

Constraints: work directly in this workspace following the instructions above. Do not invoke other AI CLIs (claude, codex, copilot, gemini, ollama). Do not commit, push, switch branches or delete files. If a command is denied by policy, stop and report it — do not look for another way to run it. Leave your changes in the working tree and end with a short list of the files you touched.
EOF_TASK
)
GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" agy -p "$TASK" \
  --add-dir "$PWD" \
  --dangerously-skip-permissions \
  --disable-slash-commands \
  --output-format text \
  --print-timeout 9m \
  [--model <slug>] [--effort low|medium|high] [--continue]
```

One foreground call, stdout returned verbatim, plus any stderr line starting
with `jetski:` or `[agy]` (soft-denied actions, print-timeout partial output,
fatal errors).

## Safety model

Facts about headless `agy` this plugin is built on (verified on 1.1.28):

- Headless mode cannot prompt. Any tool that would need approval is
  **soft-denied**: the run continues, exits 0, prints a `jetski:` notice on
  stderr and lists it under `denied_actions` in JSON output. Without
  `--dangerously-skip-permissions` even `git status` is denied, so the
  forwarder always passes that flag.
- User-configured **`permissions.deny` rules still win under that flag**
  (`Permission denied for command(...). Matches user-configured deny rule.`).
- Deny > Ask > Allow. Rules live in `~/.gemini/antigravity-cli/settings.json`
  and are global — there is no per-invocation settings flag.

So `/antigravity:setup` merges this deny list ([docs/permissions.json](docs/permissions.json)):

| Rule | Blocks |
|---|---|
| `command(regex:.*\bgit\s+push\b.*)` | pushing to shared state |
| `command(regex:.*\bgit\s+reset\b.*)` / `git\s+clean` | discarding work |
| `command(regex:.*\brm\b.*)` / `rmdir` / `del` / `erase` / `rd` / `ri` / `Remove-Item` / `find … -delete` | deleting files (POSIX, cmd and PowerShell spellings) |
| `command(regex:.*\bsudo\b.*)` | privilege escalation |
| `write_file(.git/)` | editing repository metadata |

The regexes use `\b` so `transform`, `perform`, `delete` and friends are not
caught, and they are deliberately **unanchored** so `xargs rm`, `git rm` and
`sh -c "rm …"` are caught too. The cost is a false positive when a file name
is itself a blocked word (`cat rm.txt`); the delegate then reports the denial
and stops, which is the safe failure. The subagent **refuses to run** if the
settings file has no `permissions.deny` block.

What this does **not** cover — know it before delegating:

- The deny list is global: those commands are also blocked in your own
  interactive `agy` sessions. That is intended (they are destructive or
  shared-state commands), and you can edit the file, but the forwarder's
  safety depends on it.
- Under `--dangerously-skip-permissions`, web fetch (`read_url`), browser and
  MCP tools are auto-approved too. Do not delegate tasks that process
  untrusted content, and add `read_url(*)` / `mcp(*)` to `permissions.deny`
  if you never want the delegate online.
- Pattern denies are best effort, like any CLI allow/deny list — a command
  spelled unusually can slip past. Review `git diff` before committing; the
  delegate never commits.
- `--add-dir "$PWD"` registers the repo as the workspace so agy's own
  workspace scoping applies; the delegate still runs with your user's
  privileges.

## Known agy behaviours this plugin works around

| Behaviour (agy 1.1.28) | Handling |
|---|---|
| Headless runs do not trust the current directory; reads are soft-denied | `--add-dir "$PWD"` on every call |
| A soft-denied action yields empty stdout and a stderr notice | stderr lines starting with `jetski:` / `[agy]` are appended to the result |
| A task starting with `/` is expanded as a slash command | `--disable-slash-commands` |
| `--print-timeout` returns partial output with exit 0 | pinned to 9m, under the Bash tool ceiling, so a long turn degrades instead of being killed |
| Installer may leave `agy` off PATH (seen on Windows: binary in `%LOCALAPPDATA%\agy\bin` and `~/.gemini/bin`, neither on PATH) | subagent and setup resolve those dirs themselves; setup offers `agy install` |
| `/usage` and `/credits` are interactive only; no headless quota check | setup tells you where to look; a Gemini quota error triggers one rerun on the Claude/GPT pool, a Claude/GPT quota error is returned verbatim |
| `--effort` is rejected for Claude and GPT-OSS slugs | the flag is only forwarded with Gemini slugs |

## What's in the plugin

| Piece | Purpose |
|---|---|
| `agents/antigravity-rescue.md` | Thin forwarder subagent — one `agy -p` call, output returned verbatim |
| `/antigravity:rescue` | Delegate a task explicitly (`--background`, `--wait`, `--model`, `--effort`) |
| `/antigravity:setup` | Locate binary, version floor, auth probe, merge + verify deny rules, list models |
| `docs/permissions.json` | The deny rules setup merges |
| `docs/claude-md-snippet.md` | Ready-to-paste CLAUDE.md block |
| `docs/delegation-guide.md` | Multi-lane orchestration guide |

## Not yet

- Codex CLI skill variant (the sibling plugins ship one).
- An agy custom agent profile (`~/.gemini/config/agents/<name>/agent.md`) to
  restrict tools per invocation instead of relying on the global deny list.
  Issues and PRs welcome if you have validated the frontmatter for that.

## License

[MIT](LICENSE)
