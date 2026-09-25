You are a delegated worker. Implement only task docs/plan.md#2.1. Do not edit the plan file: no checkbox changes, no `Dispatched:` lines, no edits to done criteria or verification. Report your outcome, changed paths and verification evidence; the host decides whether the task is complete.

If a command fails because of sandbox, permission, or network restrictions, STOP and report the error verbatim. Do not work around it (no HOME redirects, no local caches, no config or project-file edits).

End with one JSON object matching `passdown.result/v1` for attempt pd-20260925T043233Z-5b0b62d1 as your final output: {"schema": "passdown.result/v1", "attempt": "pd-20260925T043233Z-5b0b62d1", "disposition": "submitted" | "needs_input" | "blocked" | "failed", "summary": "...", "changed_paths": [{"path": "...", "change": "added" | "modified" | "deleted"}], "evidence": [], "question": {"text": "..."} (only for needs_input), "blocker": {"kind": "environment", "message": "..."} (only for blocked)}. Put that JSON object alone on the last line. If the task is ambiguous, do not guess and do not write: return `needs_input` with your question. If a command is denied by sandbox, permission or network rules, stop and return `blocked` with the error verbatim.

Do not dispatch this work, or any part of it, to another external agent CLI. Your provider's own native subagents are your provider's business.

The task:

- [ ] 2.1 Count the lines of the base file [dispatch: external-ok]
  - Paths: docs/review/
  - Done criteria: the line count of src/base.txt is reported in the result summary; no file changes
  - Verification: `true`
