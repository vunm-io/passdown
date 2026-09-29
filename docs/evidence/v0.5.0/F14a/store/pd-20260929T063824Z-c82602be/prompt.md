# Task: docs/plan.md#1.1

## Task definition

- [ ] 1.1 Add the greeting in French
  - Paths: src/
  - Done criteria: src/hello.txt says hello
  - Verification: `grep -q hello src/hello.txt`

## Authority

You are a delegated worker. Implement only task docs/plan.md#1.1. Do not edit the plan file: no checkbox changes, no `Dispatched:` lines, no edits to done criteria or verification. Report your outcome, changed paths and verification evidence; the host decides whether the task is complete.

## Environment

If a command fails because of sandbox, permission, or network restrictions, STOP and report the error verbatim. Do not work around it. Environment failures are the host to fix.

## Result

End with one JSON object matching `passdown.result/v1` for attempt pd-20260929T063824Z-c82602be as your final output. If the task is ambiguous, do not guess and do not write: return needs_input with your question. If a command is denied by sandbox, permission or network rules, stop and return blocked with the error verbatim.

Schema for passdown.result/v1: required: schema (const passdown.result/v1), attempt (pd-YYYYMMDDTHHMMSSZ-xxxxxxxx), disposition (submitted|needs_input|blocked|failed), summary, changed_paths (array of {path, change(added|modified|deleted|renamed)}), evidence (array of {kind(command|observation), ...}). Optional: question only if needs_input, blocker only if blocked.

## Depth

Do not dispatch this work, or any part of it, to another external agent CLI.
