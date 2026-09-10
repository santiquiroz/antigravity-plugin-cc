# Changelog

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
