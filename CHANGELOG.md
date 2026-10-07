# Changelog

## 0.5.1 — 2026-10-07

- Docs stand on their own, without a multi-lane setup: both READMEs rewritten
  (no "second lane", "when Codex/Copilot is out of quota" or lane ranking) with
  When it helps, Configuration, Troubleshooting and Using it with other
  delegates sections; the delegation guide and CLAUDE.md snippet rewritten the
  same way; the `antigravity-rescue` description and body, the command
  fallbacks and the plugin/marketplace descriptions made neutral. No behavior
  change.

## 0.5.0 — 2026-09-30

- Add `run --read-only`: agy runs in a throwaway git worktree of a `git stash create` snapshot, so a review cannot touch the caller's working tree even when the model edits files anyway (it did in testing). Attempted edits are listed and discarded; links are unlinked before the worktree is removed so a Windows junction's target is never deleted.

## 0.4.0 — 2026-09-26

- Quota watchdog: the forward now goes through `scripts/agy-forward.sh`, which
  runs `agy` in the background, finds that run's own log (the `cli-*.log`
  created after the launch whose `promptLength` matches the task) and, at 3
  `RESOURCE_EXHAUSTED` lines (`AGY_QUOTA_ABORT_AFTER`), stops only that `agy`
  process and exits 75 with
  `[antigravity-rescue] quota: RESOURCE_EXHAUSTED on <slug> (<reason>, Resets in <time>)`.
  The 0.3.0 preflight did not prevent three nine-minute burns on 2026-09-17
  (agy 1.2.5: `/usage` refresh failing, per-model 429s the weekly gauge does
  not show); the watchdog does not depend on the gauge. The subagent reruns
  once on the other pool on that line.
- The forwarding logic moved from the subagent prompt into
  `scripts/agy-forward.sh`, so it no longer depends on an LLM re-reading prose
  on every call. `preflight` locates `agy`, applies the deny-rule gate, reads
  `/usage` and `/model` (with `MSYS_NO_PATHCONV=1`, without
  `--disable-slash-commands`) and prints both gauges plus the chosen `model:`
  and `effort:` (pool switch at 2 % or less, both pools out → exit 69,
  unreadable `/usage` → exit 70; `--other-pool` checks only the other pool
  after a mid-run quota abort). `run` reads the task from stdin, appends the
  constraints paragraph and adds the fixed flags, forwarding `--effort` only
  with `gemini-` slugs. The subagent now just calls the two subcommands and
  applies the result rules.
- `tests/run.sh`: hermetic tests with a fake `agy` (records its arguments and
  environment, answers `/usage` from `tests/fixtures/` and `/model`) and a
  temporary `HOME`; the tests run in parallel, at most 6 at a time
  (`TEST_JOBS`), and the quota abort tests count the `RESOURCE_EXHAUSTED`
  lines the fake `agy` wrote before it was stopped instead of timing the run
  with the wall clock, which a loaded machine stretches past any fixed limit.
- The watchdog notices that `agy` exited within 0.25 s instead of waiting out
  its 2 s log check.
- The watchdog tells the logs that existed before the launch, or that started
  with another prompt length, apart with shell builtins and reads each new log
  once, instead of piping every old `cli-*.log` through `grep` on every 2 s
  check: with a few hundred old logs under a loaded Git Bash each check took
  minutes and the early abort came too late.
- The deny gate now requires each critical rule from `docs/permissions.json`
  (`git push`, `git reset`, `git clean`, `rm`, `rmdir`, `del`, `rd`,
  `Remove-Item`, `write_file(.git/)`) inside `permissions.deny`, instead of
  the bare word `"deny"` anywhere in the file: `"deny": []`, a partial list or
  the rules under another key used to pass and still run with
  `--dangerously-skip-permissions`. It exits 78 with
  `antigravity-rescue: missing deny rules: <names> — run /antigravity:setup`.
- Post-run git guard: in a git repository `run` snapshots `HEAD`, the branch,
  the stash count, `.git/config` (plus `config.worktree`) and the hooks
  directory (`git rev-parse --git-path hooks`, so linked worktrees and
  `core.hooksPath` count) before and after `agy`, and appends
  `[antigravity-rescue] WARNING: <what changed> — review before your next git command`
  for each change. Read-only; nothing is reverted. The deny list does not stop
  `git commit`/`switch`/`stash`, `git config` or a hook written from the
  shell, and a planted hook runs on the orchestrator's next `git commit`.
- `.gitattributes` keeps `*.sh` at LF so bash runs them with
  `core.autocrlf=true`.
- The subagent prompt states one Bash call budget: preflight (120000 ms), run
  (600000 ms) and, only after a quota signature, a second preflight plus one
  rerun, each as its own foreground call. 0.3.0 asked for the preflight "in the
  same Bash call as the forward" and for "exactly one foreground Bash call",
  which contradicted the decision between them and the rerun, and nine minutes
  of run plus two preflights could pass the 10-minute Bash ceiling.
- `/antigravity:setup` reads `/usage` and `/model` before its two paid probes
  and runs them on a pool above 2 % (`gemini-3.8-flash-low` or
  `gpt-oss-120b-medium`), or skips them as `skipped: quota` when both pools are
  out. The deny probe is now `rm -f ./.agy-deny-probe-nonexistent` with
  `GIT_TERMINAL_PROMPT=0` and `GIT_SSH_COMMAND='ssh -o BatchMode=yes'` instead
  of `git push --dry-run`, which needed the network if the rule did not bite.
  A probe ending in `status: ERROR`, `The stream was interrupted`,
  `[agy] print timeout` or a quota message is reported as
  `inconclusive (quota)`; 0.3.0 reported it as "deny rules are not being
  applied".

## 0.3.0 — 2026-09-10

- Quota-aware pool selection: before every run the subagent reads both weekly
  gauges with `agy -p "/usage"` (answered by print mode for free, agy ≥ 1.1.11)
  and the default slug with `agy -p "/model"`, then picks the pool that has
  room; both pools out → it returns immediately without running. Replaces the
  reactive text match: an exhausted pool does not fail fast — agy retries with
  backoff (`RESOURCE_EXHAUSTED (code 429)` only in `cli.log`) until the print
  timeout and reports `status: ERROR` / `The stream was interrupted`, so the
  old detector burned nine minutes per attempt (observed at Gemini 0 %).
- `MSYS_NO_PATHCONV=1` on print-mode slash commands: in Git Bash `/usage` was
  rewritten into a Windows path and became a paid model turn.
- README audited from six newcomer perspectives (51-agent panel): safety model
  now separates what the deny list enforces from what the prompt merely asks
  (`git commit`/`checkout`/`stash` are not denied; `--add-dir` is not a
  sandbox; shell `curl`/`npm install` stay online), documents `--wait` /
  `--background`, the 9-minute cap, resuming, and how proactive delegation can
  be restricted to explicit invocation. `/antigravity:setup` prints both
  gauges and the default model.

## 0.2.0 — 2026-09-09

- Two quota pools: Antigravity meters Gemini models and Claude + GPT-OSS
  models on separate weekly quotas. The subagent now picks per pool and, when
  a Gemini run dies on quota, reruns the task once on the Claude/GPT pool
  (`claude-sonnet-4-6` / `claude-opus-4-6-thinking` / `gpt-oss-120b-medium`)
  and says so in the first output line. A Claude/GPT quota error is returned
  verbatim — both pools out.
- `--effort` is forwarded only with Gemini slugs; agy rejects it for Claude
  and GPT-OSS models (verified on 1.1.28). Fixed the README example that
  combined `claude-opus-4-6-thinking` with `--effort high`.
- Docs: pool table in README (en/es), CLAUDE.md snippet, delegation guide and
  setup output.

## 0.1.0 — 2026-09-09

Initial release.

- `antigravity-rescue` subagent: thin forwarder to Google Antigravity CLI
  (`agy`) in headless print mode — one `agy -p` call with the repo registered
  as workspace, output returned verbatim plus agy's stderr diagnostic markers.
- Safety model: `--dangerously-skip-permissions` per call (headless agy cannot
  prompt) guarded by a global `permissions.deny` list that agy honours even
  under that flag; the subagent refuses to run without the deny block.
- `/antigravity:rescue` command: delegate a task from any session
  (`--background`, `--wait`, `--model <slug>`, `--effort <level>`).
- `/antigravity:setup` command: locate the binary (PATH or known install
  dirs), version floor 1.1.28, auth probe, merge the deny rules, verify they
  bite, list models.
- `docs/permissions.json`, delegation guide, ready-to-paste CLAUDE.md snippet.
