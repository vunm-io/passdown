You are a delegated worker for attempt pd-20260926T173842Z-0c67dcab.

## Task reference

Plan: docs/plan.md
Task ID: 1.1
Exact ref: docs/plan.md#1.1

## Task

- [ ] 1.1 Add the greeting [dispatch: fake]
  - Paths: src/
  - Done criteria: src/hello.txt says hello
  - Verification: `grep -q hello src/hello.txt`

## Authority

You are a delegated worker. Implement only task docs/plan.md#1.1. Do not edit the plan file: no checkbox changes, no `Dispatched:` lines, no edits to done criteria or verification. Report your outcome, changed paths and verification evidence; the host decides whether the task is complete.

## Environment

If a command fails because of sandbox, permission, or network restrictions, STOP and report the error verbatim. Do not work around it (no HOME redirects, no local caches, no config or project-file edits).

## Depth

Do not dispatch this work, or any part of it, to another external agent CLI. Your provider's own native subagents are your provider's business.

## Result

End with one JSON object matching `passdown.result/v1` for attempt pd-20260926T173842Z-0c67dcab as your final output. If the task is ambiguous, do not guess and do not write: return `needs_input` with your question. If a command is denied by sandbox, permission or network rules, stop and return `blocked` with the error verbatim.

The schema for `passdown.result/v1` is:

{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "passdown.result/v1",
  "type": "object",
  "required": ["schema", "attempt", "disposition", "summary", "changed_paths", "evidence"],
  "properties": {
    "schema": { "const": "passdown.result/v1" },
    "attempt": { "type": "string", "pattern": "^pd-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$" },
    "disposition": { "enum": ["submitted", "needs_input", "blocked", "failed"] },
    "summary": { "type": "string", "minLength": 1, "maxLength": 2000 },
    "changed_paths": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["path", "change"],
        "properties": {
          "path": { "type": "string" },
          "change": { "enum": ["added", "modified", "deleted", "renamed"] }
        }
      }
    },
    "evidence": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["kind"],
        "properties": {
          "kind": { "enum": ["command", "observation"] },
          "command": { "type": "string" },
          "exit_code": { "type": "integer" },
          "observed": { "type": "string" }
        }
      }
    },
    "question": { "oneOf": [{ "type": "null" }, { "type": "object", "required": ["text"], "properties": { "text": { "type": "string" } } }] },
    "blocker": { "oneOf": [{ "type": "null" }, { "type": "object", "required": ["kind", "message"], "properties": { "kind": { "enum": ["permission", "sandbox", "network", "tool-missing", "other"] }, "message": { "type": "string" } } }] }
  }
}

Example for a successful submission:
{"schema":"passdown.result/v1","attempt":"pd-20260926T173842Z-0c67dcab","disposition":"submitted","summary":"Created src/hello.txt with content hello","changed_paths":[{"path":"src/hello.txt","change":"added"}],"evidence":[{"kind":"command","command":"grep -q hello src/hello.txt","exit_code":0}],"question":null,"blocker":null}
