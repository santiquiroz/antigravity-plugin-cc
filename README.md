# antigravity-plugin-cc

Delegate coding tasks from [Claude Code](https://claude.com/claude-code) to
[Google Antigravity CLI](https://antigravity.google/docs/cli/overview) (`agy`)
in headless mode. Claude Code stays the orchestrator — it writes the domain
logic, defines each subtask contract, and reviews the diffs — while the
Antigravity delegate does the delegated work agentically: it reads and edits
files and runs build/test/git commands in your repo itself.

> Lea esto en español: [README.es.md](README.es.md)

## When it helps

Antigravity is worth a delegation when the job fits one of its own strengths:

- **Model choice per call.** `agy` runs Gemini 3.1 Pro, Gemini 3.8 Flash,
  Claude Sonnet 4.6, Claude Opus 4.6 Thinking and GPT-OSS 120B, selectable per
  call with `--model` (and `--effort` for Gemini slugs). Reasoning-shaped work
  — diagnosis, build fixing, refactors, second opinions — goes to a frontier
  model; mechanical work — specs, renames, boilerplate — to a cheap Flash
  model.
- **Its own quota.** Antigravity meters Gemini models on one weekly quota and
  Claude + GPT-OSS models on a separate one, independent of any other tool you
  use. Both gauges can be read for free at any time with `agy -p "/usage"` (no
  agent turn, no quota spent), and the subagent reads them before every run,
  switching pools on its own when the requested one is empty.
- **An agentic delegate.** It reads and edits files and runs build/test/git
  commands in your repo itself — hand it self-contained tasks (one spec file,
  one build fix, one diagnosis) and review the diff when it returns.

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

## Setup

Then, once per machine:

```
/antigravity:setup
```

Setup locates the binary (PATH or the known install dirs), checks the version
floor, reads both quota gauges and the default model for free (`/usage`,
`/model`) before any paid probe, checks authentication on a pool that has room,
merges the deny rules this plugin relies on into
`~/.gemini/antigravity-cli/settings.json` (asking first), and verifies they
bite with a harmless, network-free `rm -f` probe. With both pools out it skips
the two model probes (`skipped: quota`); a probe that ends in a quota error or
an interrupted stream is reported as `inconclusive (quota)`, never as "deny
rules not applied".

The deny list is mandatory, not optional: headless `agy` cannot prompt, so
every run passes `--dangerously-skip-permissions`, and the user-configured
`permissions.deny` rules in that file are what still win under the flag. The
subagent refuses to run (exit 78,
`missing deny rules: <names> — run /antigravity:setup`) unless every critical
rule is present. See the Safety model below for the exact list.

## Usage

Explicit delegation:

```
/antigravity:rescue diagnose why `npm test` fails in src/services/user-mapper.spec.ts and fix the spec
/antigravity:rescue --background --model gemini-3.8-flash-low generate boilerplate specs for src/services/user-mapper.ts (signatures pasted below) ...
/antigravity:rescue --read-only --model claude-opus-4-6-thinking second opinion: review the diff of HEAD for race conditions
```

### Flags and limits

Put the flags first, then the task text (the command recognises them anywhere
in the request, but keeping them up front stops them being read as part of the
task).

- `--wait` (default) — foreground. Claude Code blocks on a single `agy` call
  and shows nothing until it returns; a run can take up to 9 minutes with no
  visible progress. In a regular run, interrupting it (Esc / Ctrl+C) rolls
  nothing back: whatever agy had already edited stays in your working tree —
  run `git diff` before doing anything else. Use `--read-only` to isolate a
  review from your working tree.
- `--background` — Claude Code dispatches the subagent in the background and
  keeps working; the output is relayed to you when the run completes. Use it
  for anything that may take more than a minute.
- `--model <slug>` / `--effort low|medium|high` — see "Two quota pools" below.
- `--read-only` — runs `agy` in a throwaway git worktree based on a `git stash create` snapshot of your staged and unstaged tracked changes (untracked files are not included). The script lists attempted edits and discards them, keeping your working tree untouched even if the model edits files.

Every run is capped at 9 minutes (`--print-timeout 9m`). At the cap `agy`
exits 0 with the output so far and an `[agy] print timeout` line (kept from
stderr and appended to the result); the edits made until then are already in
your working tree. Exit 0 therefore does not mean the task finished — read the
output and `git diff`. Size tasks to fit: one spec file, one build fix, one
diagnosis.

**Resuming.** `--continue` is not a `/antigravity:rescue` flag; the subagent
adds it on its own when your request clearly continues prior Antigravity work
in this repo (wording like "continue", "keep going", "resume", e.g.
`/antigravity:rescue continue the previous task: <one-line recap of what was left>`).
`agy --continue` resumes the most recent conversation for the active
workspace, so it can also pick up an interactive `agy` session you ran in the
same repo — if you have used `agy` there since, restate the task in full
instead. It is never added on the automatic pool switch.

### Proactive delegation

The `antigravity-rescue` agent's description tells Claude Code to use it on its
own for bounded, delegable work — a diagnosis, a second opinion, mechanical
work on Flash — so once the plugin is installed it can fire in any Claude Code
session without you typing the command. That run sends the task text to
Google's models and lets them read and edit files in the current repository
with edits auto-approved (the deny list still applies). What stands between
that and your working tree is Claude Code's own permission system: the
subagent's only tool is `Bash`, so in the default (and `acceptEdits`)
permission mode you approve the command that launches `agy` before it runs —
unless you have allowlisted that command or answered "don't ask again" — while
under bypass mode / `--dangerously-skip-permissions` it runs unprompted. There
is no enforced switch that limits the agent to `/antigravity:rescue` (the
command dispatches the same subagent), so if you want delegation only when you
ask for it: skip the CLAUDE.md snippet below, keep the Bash prompt on, and add
this line to your `~/.claude/CLAUDE.md` — it is an instruction Claude Code
follows, not a permission rule:

```
Never launch antigravity:antigravity-rescue on your own; use it only when I invoke /antigravity:rescue explicitly.
```

To make proactive delegation routine instead, paste the block from
[docs/claude-md-snippet.md](docs/claude-md-snippet.md) into your `CLAUDE.md`
and adjust its triggers to your setup.
[docs/delegation-guide.md](docs/delegation-guide.md) collects orchestration
notes (background dispatch, WIP caps, quota fallbacks).

### Two quota pools

Antigravity meters **Gemini models** on one weekly quota and **Claude + GPT-OSS
models** on a separate one (Antigravity app → Settings → Models & Usage shows
both gauges; with only the CLI installed, `agy -p "/usage"` prints them — see
below). The subagent treats them as two pools inside the same CLI:

| Task class | Gemini pool | Claude/GPT pool |
|---|---|---|
| mechanical (specs, renames, boilerplate) | `gemini-3.8-flash-low` / `-medium` | `gpt-oss-120b-medium` |
| diagnosis, build fixing, refactor | `gemini-3.1-pro-high` | `claude-sonnet-4-6` |
| second opinion, hardest reasoning | `gemini-3.1-pro-high` | `claude-opus-4-6-thinking` |
| nothing passed | agy's configured default — `agy -p "/model"` prints it; `/model <name>` in an interactive session changes it | — |

Before every run the subagent reads both gauges with a free
`agy -p "/usage"` (no agent turn, no quota spent) and picks the pool: if the
pool of the requested model is at 2 % or less and the other has room, it runs
the task on the other pool's equivalent and starts the output with
`[antigravity-rescue] <pool> pool at NN%, running on <slug> instead`; if both
pools are out it does not run at all and returns
`[antigravity-rescue] both Antigravity pools exhausted (...)` with the reset
times. This matters because an exhausted pool does not fail fast: agy retries
with backoff (`RESOURCE_EXHAUSTED (code 429)` in `cli.log`) until the print
timeout, then reports `status: ERROR` / `The stream was interrupted` — nine
minutes lost per attempt and no quota word in the output. The gauge alone is
not enough (it can be stale, and a per-model 429 never shows there), so
`scripts/agy-forward.sh` also watches the run's own log: at 3
`RESOURCE_EXHAUSTED` lines (`AGY_QUOTA_ABORT_AFTER` changes the count) it stops
that `agy` process and returns
`[antigravity-rescue] quota: RESOURCE_EXHAUSTED on <slug> (<reason>, Resets in <time>)`
with exit 75 within seconds. The subagent then reruns once on the other pool
when `/usage` shows it has room; the same applies if the timeout signature
appears anyway. Pass `--model claude-sonnet-4-6` (or say the
Gemini pool is low) to start on the second pool directly.

### Check quota and model from the CLI

Print mode answers the read-only slash commands itself — no agent turn, no
quota spent, no conversation left behind (agy ≥ 1.1.11):

```bash
agy -p "/usage"                        # one line per pool: name, "Weekly Limit Remaining", % left, reset time (/quota is an alias)
agy -p "/usage" --output-format json   # same data under command.data.groups[].buckets[].remaining_fraction / reset_time
agy -p "/model"                        # the default slug used when no --model is passed
agy -p "/help"                         # every command print mode answers this way
agy models                             # valid slugs (plain text only)
```

`/credits` is a different gauge — purchasable credits and an upgrade link — not
the two weekly pools.

Two traps: (1) do **not** add `--disable-slash-commands` to these calls — with
it the text falls through to the model, which answers as if the command had
run, and that turn spends quota; this is why the forwarder runs the preflight
without the flag and the task with it. (2) In Git Bash — which is what the
Claude Code Bash tool is on Windows — MSYS path conversion rewrites the
argument `/usage` into `C:/Program Files/Git/usage` before agy sees it, and
that too becomes a quota-spending agent turn. Prefix the call with
`MSYS_NO_PATHCONV=1` there, or run it from PowerShell/cmd.

Which model a delegation used: the slug you passed with `--model`, otherwise
what `agy -p "/model"` prints (or the pool switch announced in the first line
of the output). Neither the text nor the JSON result of a run carries a
per-run model field.

`--effort low|medium|high` only applies to Gemini slugs; Claude and GPT-OSS
slugs carry their effort in the name and agy rejects the flag for them.
`agy models` prints the current slugs; an unknown slug exits 1 immediately.

### What the forwarder actually runs

The subagent makes two separate foreground Bash calls to
`scripts/agy-forward.sh`, and two more only after a quota signature. Each is
its own call: a nine-minute run plus a preflight would not fit under the Bash
tool's 10-minute ceiling, and the subagent never uses `run_in_background`.

```bash
# 1. Free preflight (timeout 120000 ms): deny gate, both gauges, pool and model
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agy-forward.sh" preflight [--model <slug>] [--effort low|medium|high] [--class mechanical|reasoning|hardest]

# 2. The run (foreground, timeout 600000 ms), with the model and effort the preflight printed
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agy-forward.sh" run [--model <slug>] [--effort <level>] [--continue] <<'EOF_TASK'
<your task, verbatim>
EOF_TASK

# 3. Only after a quota signature from the run: preflight again (timeout 120000 ms,
#    --other-pool after exit 75) and, if it moved to the other pool, one rerun of
#    step 2 on that model (timeout 600000 ms, without --continue)
```

`run` appends the constraints paragraph and executes:

```bash
GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" agy -p "<your task>

Constraints: work directly in this workspace following the instructions above. Do not invoke other AI CLIs (claude, codex, copilot, gemini, ollama). Do not commit, push, switch branches or delete files. If a command is denied by policy, stop and report it — do not look for another way to run it. Leave your changes in the working tree and end with a short list of the files you touched." \
  --add-dir "$PWD" \
  --dangerously-skip-permissions \
  --disable-slash-commands \
  --output-format text \
  --print-timeout 9m \
  [--model <slug>] [--effort <level>, Gemini slugs only] [--continue]
```

stdout is returned verbatim, plus any stderr line starting with `jetski:` or
`[agy]` (soft-denied actions, print-timeout partial output, fatal errors). The
quota watchdog finds this run's log in `~/.gemini/antigravity-cli/log/` (the
`cli-*.log` created after the launch whose `promptLength` matches the task, so
`/usage` probes and other sessions' runs are ignored) and aborts only its own
`agy` process. After a quota abort, `preflight --other-pool` checks only the
other pool before the single rerun.

When the working directory is a git repository, `run` also takes a read-only
snapshot of its git metadata before and after `agy`: `HEAD`, the current
branch, the number of stash entries, `.git/config` (plus `config.worktree`)
and the hooks directory (`git rev-parse --git-path hooks`, so linked worktrees
and `core.hooksPath` are covered). For each one that changed it appends
`[antigravity-rescue] WARNING: <what changed> — review before your next git command`
to the output. It never reverts anything. A hook or alias the delegate wrote
runs on your next `git commit`, so read the warning before you run one. Only
the repository's own config is watched: an alias or setting written with
`git config --global` (`~/.gitconfig`) is not reported.
`bash tests/run.sh` exercises all of this against a fake `agy` and a
temporary `HOME`, without network.

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
| `command(regex:.*\bgit\s+reset\b.*)` / `git\s+clean` | discarding work via `reset`/`clean` (`checkout --`, `restore` and `stash` are not denied, see below) |
| `command(regex:.*\brm\b.*)` / `rmdir` / `del` / `erase` / `rd` / `ri` / `Remove-Item` / `find … -delete` | deleting files (POSIX, cmd and PowerShell spellings) |
| `command(regex:.*\bsudo\b.*)` | privilege escalation |
| `write_file(.git/)` | editing repository metadata |

The regexes use `\b` so `transform`, `perform`, `delete` and friends are not
caught, and they are deliberately **unanchored** so `xargs rm`, `git rm` and
`sh -c "rm …"` are caught too. The cost is a false positive when a file name
is itself a blocked word (`cat rm.txt`); the delegate then reports the denial
and stops, which is the safe failure. The subagent **refuses to run** (exit 78,
`missing deny rules: <names> — run /antigravity:setup`) unless the settings
file's `permissions.deny` list holds every critical rule above: `git push`,
`git reset`, `git clean`, `rm`, `rmdir`, `del`, `rd`, `Remove-Item` and
`write_file(.git/)`. An empty or partial list does not pass.

What this does **not** cover — know it before delegating:

- The deny list is global: those commands are also blocked in your own
  interactive `agy` sessions. That is intended (they are destructive or
  shared-state commands), and you can edit the file, but the forwarder's
  safety depends on it.
- Under `--dangerously-skip-permissions`, web fetch (`read_url`), browser and
  MCP tools are auto-approved too. Do not delegate tasks that process
  untrusted content. Adding `read_url(*)` / `mcp(*)` to `permissions.deny`
  blocks only agy's built-in web and MCP tools; shell commands such as `curl`,
  `wget`, `Invoke-WebRequest`, `npm install` or `pip install` stay
  auto-approved, so the delegate is never fully offline unless you deny those
  too (which also breaks builds that need them).
- Pattern denies are best effort, like any CLI allow/deny list — a command
  spelled unusually can slip past.
- The constraints paragraph in the prompt (`Do not commit, push, switch
  branches or delete files`) is a request to the model, not a rule. Of it,
  only `push` and the `rm` family are actually denied: `git commit`,
  `git checkout`, `git switch`, `git restore`, `git stash` and `git rebase` are
  not, so a delegate that ignores the prompt can commit, or discard your
  uncommitted changes. Shell commands can also write `.git/hooks/*` or run
  `git config` (`core.hooksPath`, an alias): `write_file(.git/)` only covers
  agy's file tool, and a planted hook runs on your next `git commit`. `run`
  warns when `HEAD`, the branch, the stash list, the git config or the hooks
  changed during the run, but it does not undo anything. Commit or stash your
  own work before delegating, and review `git log` and `git stash list` as
  well as `git diff`. To enforce it,
  add `command(regex:.*\bgit\s+(commit|checkout|switch|restore|stash|rebase)\b.*)`
  to `permissions.deny` — global, so it also blocks those commands in your
  interactive `agy` sessions.
- `--add-dir "$PWD"` registers the repo as the workspace for agy's own file
  tools; it is not a sandbox. Shell commands run as your OS user with your
  environment and can reach any path on disk (`~/.ssh`, `.env`, credential
  stores). The delegate edits your live working tree, not a copy — do not edit
  the same files while a `--background` run is in flight. For repos holding
  secrets, or tasks touching untrusted input, run the delegate under a
  separate OS user or in a container.

## Configuration

Everything the plugin needs beyond the install lives in three places:

- The deny rules in `~/.gemini/antigravity-cli/settings.json`
  (`permissions.deny`), merged by `/antigravity:setup` from
  [docs/permissions.json](docs/permissions.json). Required: the subagent
  refuses to run without every critical rule (see the Safety model).
- agy's own default model: `agy -p "/model"` prints it, `/model <name>` in an
  interactive session changes it. It is used whenever a delegation passes no
  `--model`.
- `AGY_QUOTA_ABORT_AFTER` (default 3): how many `RESOURCE_EXHAUSTED` lines in
  the run's own log abort it early with exit 75.

Not yet: an agy custom agent profile
(`~/.gemini/config/agents/<name>/agent.md`) to restrict tools per invocation
instead of relying on the global deny list. Issues and PRs welcome if you have
validated the frontmatter for that.

### What's in the plugin

| Piece | Purpose |
|---|---|
| `agents/antigravity-rescue.md` | Thin forwarder subagent — runs the script's preflight and run, output returned verbatim |
| `/antigravity:rescue` | Delegate a task explicitly (`--background`, `--wait`, `--model`, `--effort`, `--read-only`) |
| `/antigravity:setup` | Locate binary, version floor, auth probe, merge + verify deny rules, list models |
| `scripts/agy-forward.sh` | `preflight`: locates `agy`, deny gate, both gauges, pool and model. `run`: fixed flags, constraints paragraph, `agy`, aborted early when its own log shows repeated `RESOURCE_EXHAUSTED`, then a warning for each change to `HEAD`, branch, stash, git config or hooks |
| `tests/run.sh` | Hermetic tests for the script (fake `agy` in `tests/fake-agy.sh`, `/usage` fixtures in `tests/fixtures/`, temporary `HOME`) |
| `docs/permissions.json` | The deny rules setup merges |
| `docs/claude-md-snippet.md` | Ready-to-paste CLAUDE.md block |
| `docs/delegation-guide.md` | Orchestration notes (background dispatch, WIP caps, quota fallbacks) |

## Troubleshooting

The expensive trap first: a pool at 0 % does not fail fast. `agy` retries with
backoff until the print timeout and then reports `status: ERROR` /
`The stream was interrupted` with no quota word — nine minutes lost per
attempt. That is why the forwarder reads both gauges before every run, aborts
on the run's own `RESOURCE_EXHAUSTED` lines within seconds (exit 75), and
reruns once on the other pool. The rest of the verified traps:

| Symptom (agy 1.1.28) | Handling |
|---|---|
| Headless runs do not trust the current directory; reads are soft-denied | `--add-dir "$PWD"` on every call |
| A soft-denied action yields empty stdout and a stderr notice | stderr lines starting with `jetski:` / `[agy]` are appended to the result |
| A task starting with `/` is expanded as a slash command | `--disable-slash-commands` on the task run (never on the `/usage` / `/model` probes) |
| `--print-timeout` returns partial output with exit 0 | pinned to 9m, under the Bash tool ceiling, so a long turn degrades instead of being killed — exit 0 does not mean the task finished, read the output and `git diff` |
| Installer may leave `agy` off PATH (seen on Windows: binary in `%LOCALAPPDATA%\agy\bin` and `~/.gemini/bin`, neither on PATH) | subagent and setup resolve those dirs themselves; setup offers `agy install` |
| An exhausted pool does not fail fast: agy retries with backoff until the print timeout, then reports `status: ERROR` / `The stream was interrupted` with no quota word | the forwarder reads both gauges with `agy -p "/usage"` (free) before every run and picks the pool; both pools out → it returns immediately without running. If the run still hits `RESOURCE_EXHAUSTED` (stale gauge, per-model 429), `scripts/agy-forward.sh` sees it in the run's own log and aborts within seconds with exit 75 |
| `agy -p "/usage"` in Git Bash becomes a paid model turn (MSYS rewrites `/usage` into a Windows path) | `MSYS_NO_PATHCONV=1` on every print-mode slash command |
| `--effort` is rejected for Claude and GPT-OSS slugs | the flag is only forwarded with Gemini slugs |
| `agy` edits files even when the task asked only for a review (seen in testing) | pass `--read-only`: the run happens in a throwaway worktree built from a `git stash create` snapshot, the attempted edits are listed and discarded, and your tree stays untouched |
| Exit 1 with `authentication required` / `not logged into Antigravity` | run `agy` once interactively (browser sign-in) and then rerun `/antigravity:setup` |
| `/credits` looks like the quota gauge | it shows purchasable credits and an upgrade link, not the two weekly pools |

## Using it with other delegates

This plugin assumes no place in a lineup: if you run several delegation
plugins, the order — which delegate handles what, and where a task goes when
one reports quota or auth errors — is yours to define in your `CLAUDE.md`. This
plugin's side of the contract: pool switches are announced in the first output
line, both pools out returns
`[antigravity-rescue] both Antigravity pools exhausted (...)` without running
anything, and auth failures name themselves — so whatever calls it can route
the task to another delegate or take it inline.

Related projects with the same command/subagent shape: [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) (whose structure inspired this plugin), [copilot-plugin-cc](https://github.com/santiquiroz/copilot-plugin-cc), [ollama-plugin-cc](https://github.com/santiquiroz/ollama-plugin-cc) and [bipolar-plugin-cc](https://github.com/santiquiroz/bipolar-plugin-cc).

## License

[MIT](LICENSE)

Not affiliated with Google, OpenAI, GitHub, or Anthropic.
