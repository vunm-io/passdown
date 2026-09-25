---
status: IN_PROGRESS
branch: main
agent: claude
plan: openspec/changes/pkg-0001-demo/
open_attempts:
  - pd-20260706T100900Z-5b1e7c2a
---

# 2026-07-06 — passdown demo, dispatch paused

## Summary

Routed `pkg-0001-demo` and dispatched task 1.1 to an external executor
under owner policy. The session had to stop while that attempt was still
running, so it is recorded here as open. This log exists to show what a
handoff with an unresolved attempt looks like; the example workspace ships
no attempt store, so pickup reports the attempt as missing from the store.

## What was done

- Routing written into `tasks.md`: 1.1 and 1.2 `[dispatch: external-ok]`,
  2.1 `[dispatch: main]`.
- Task 1.1 dispatched as attempt `pd-20260706T100900Z-5b1e7c2a` (external,
  reason `owner-policy`, current checkout).

## Next steps

- [ ] Run `passdown-pickup`; resolve attempt `pd-20260706T100900Z-5b1e7c2a`
      through the *Reconcile* section of `passdown-dispatch` before
      dispatching anything else to this repository.
- [ ] Then dispatch 1.2, and do 2.1 in the main session.

## Caveats / traps

- Attempt `pd-20260706T100900Z-5b1e7c2a` (task
  `openspec/changes/pkg-0001-demo/tasks.md#1.1`) is **C3, ownership risk**:
  the worker was still running in the current checkout when this session
  stopped. Probe it before anything else; do not start another writer in
  this repository until it is stopped, and do not tick 1.1 until the host
  has accepted it.
