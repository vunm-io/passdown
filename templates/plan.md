# Plan: <title>

## Context

<!-- Why this work is needed, relevant constraints, and links. -->

## Tasks

- [ ] 1.1 <Mechanical or fully specified task> [dispatch: external-ok]
  - Paths: <files/directories this task may touch>
  - Done criteria: <observable completion condition>
  - Verification: `<command or check>`

- [ ] 1.2 <Judgment-heavy or ambiguous task> [dispatch: main]
  - Paths: <files/directories this task may touch>
  - Done criteria: <observable completion condition>
  - Verification: `<command or check>`

## Notes

- Every task must be self-contained enough for a fresh session or external executor.
- Use `[dispatch: external-ok]` for mechanical, isolated, verifiable work.
- Use `[dispatch: main]` for architecture, security, ambiguous requirements, release decisions, and final judgment.
- Run `passdown-dispatch` before executing a multi-task plan, even when another plugin supplies its own executor.
- `passdown-dispatch` materializes routing decisions as tags in this file and
  appends a `- Dispatched: ...` outcome line under each task executed off-main.
