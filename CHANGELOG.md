# Changelog

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
