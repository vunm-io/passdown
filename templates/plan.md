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
- Use `[dispatch: external-ok]` for isolated, verifiable work another executor may take.
- Use `[dispatch: main]` for architecture, security, ambiguous requirements, release decisions, and final judgment.
- Run `passdown-dispatch` before executing a multi-task plan, even when another plugin supplies its own executor.
- `passdown-dispatch` materializes routing decisions as tags in this file and
  appends a `- Dispatched: ...` outcome line under each task executed off-main,
  e.g. `- Dispatched: agy (2026-09-21) — accepted; verified: npm test; attempt: pd-20260921T101530Z-3f9a1c2e`.
  The `attempt:` ID names the attempt receipt in the local attempt store
  (`.git/passdown/attempts/` by default); a rejection names its reason, e.g.
  `— rejected: needs input; verified: -; attempt: <id>`.
- `[dispatch: external-ok]` permits delegation; it does not require it. The
  dispatch skill still keeps the task in the current session unless a named
  reason (owner policy, a required environment, a measured specialization,
  quota) justifies an external executor.
- Keep task text, paths, done criteria and verification stable while an
  attempt runs: an edit makes that attempt `stale`, and a new attempt is
  needed for the new revision.
- Completion authority: a delegated worker (external CLI or native subagent)
  never ticks a checkbox or edits this file. The host ticks a delegated task
  `[x]` only after its own verification passes, its `accepted` verdict is
  persisted in the attempt receipt, and it records `accepted` in the
  `Dispatched:` line. Tasks done in the current session (`main`) are
  marked complete as you go, after their verification passes.
