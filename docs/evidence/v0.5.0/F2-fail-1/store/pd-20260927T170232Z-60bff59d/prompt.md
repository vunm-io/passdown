Task reference: docs/plan.md#1.1

## Task

**1.1 Add the greeting**

- Paths: src/
- Done criteria: src/hello.txt says hello
- Verification: `grep -q hello src/hello.txt`

## Authority

You are a delegated worker. Implement only task docs/plan.md#1.1. Do not edit the plan file: no checkbox changes, no `Dispatched:` lines, no edits to done criteria or verification. Report your outcome, changed paths and verification evidence; the host decides whether the task is complete.

## Environment

If a command fails because of sandbox, permission, or network restrictions, STOP and report the error verbatim. Do not work around it (no HOME redirects, no local caches, no config or project-file edits).

## Result

End with one JSON object matching `passdown.result/v1` for attempt pd-20260927T170232Z-60bff59d as your final output. If the task is ambiguous, do not guess and do not write: return `needs_input` with your question. If a command is denied by sandbox, permission or network rules, stop and return `blocked` with the error verbatim.

The schema for passdown.result/v1 is:

{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "passdown.result/v1",
  "type": "object",
  "required": ["schema", "attempt", "disposition", "summary", "changed_paths", "evidence"],
  "properties": {
    "schema": { "const": "passdown.result/v1" },
    "attempt": { "type": "string", "pattern": "^pd-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$" },
    "disposition": { "enum": ["submitted", "needs_input", "blocked", "failed"] },
    "summary": { "type": "string" },
    "changed_paths": { "type": "array" },
    "evidence": { "type": "array" },
    "question": { "oneOf": [{ "type": "null" }, { "type": "object" }] },
    "blocker": { "oneOf": [{ "type": "null" }, { "type": "object" }] }
  }
}

## Depth

Do not dispatch this work, or any part of it, to another external agent CLI. Your provider's own native subagents are your provider's business.
