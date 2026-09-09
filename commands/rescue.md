---
description: Delegate a well-specified coding task to Google Antigravity CLI (agy) through the antigravity-rescue subagent
argument-hint: "[--background|--wait] [--model <slug>] [--effort low|medium|high] [the task agy should perform]"
allowed-tools: AskUserQuestion, Agent
---

Invoke the `antigravity:antigravity-rescue` subagent via the `Agent` tool (`subagent_type: "antigravity:antigravity-rescue"`), forwarding the raw user request as the prompt.
`antigravity:antigravity-rescue` is a subagent, not a skill — do not call it via the `Skill` tool. This command runs inline so the `Agent` tool stays in scope.
The final user-visible response must be the subagent's output verbatim.

Raw user request:
$ARGUMENTS

Execution mode:

- If the request includes `--background`, run the subagent in the background and continue other work; relay the result when it completes.
- If the request includes `--wait`, run the subagent in the foreground.
- If neither flag is present, default to foreground.
- `--background` and `--wait` are execution flags for Claude Code. Do not forward them in the prompt, and do not treat them as part of the natural-language task text.
- `--model <slug>` and `--effort <level>` are runtime-selection flags. Preserve them in the forwarded prompt (the subagent maps them to `agy` flags), but do not treat them as part of the natural-language task text.

Operating rules:

- The subagent is a thin forwarder only. It uses one `Bash` call to run `agy -p ...` headless with the repo registered as workspace, and returns that command's output as-is.
- Before dispatching, make sure the task text is self-contained: paste in the file paths, signatures and acceptance criteria it refers to. The delegate does not see this conversation.
- Return the output verbatim to the user. Do not paraphrase, summarize, rewrite, or add commentary before or after it.
- Do not ask the subagent to inspect files, monitor progress, summarize output, or do follow-up work of its own.
- If the returned output says `agy` is not installed, not authenticated, or that the deny-rule safety check failed, tell the user to run `/antigravity:setup`.
- If the returned output shows a quota or rate-limit message, report it and suggest another delegate or retrying later — do not retry automatically.
- If the user did not supply a task, ask what task agy should perform.
