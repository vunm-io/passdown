# 2026-07-05 — passdown demo

- Agent: main
- Status: DONE
- Branch: main
- Related change: `openspec/changes/pkg-0001-demo/`

## Summary

Ran passdown-intake on `docs/inbox/idea-001.md`, created the
`pkg-0001-demo` OpenSpec change (proposal + specs, no design.md needed),
and wrote a dispatchable `tasks.md`. Implementation itself was left undone —
this log exists only to show what a handoff looks like.

## What was done

- Processed `docs/inbox/idea-001.md`, marked it `status: processed`.
- Created `openspec/changes/pkg-0001-demo/` with proposal.md,
  specs/demo-greeting/spec.md, and tasks.md (2 tasks marked
  `[dispatch: external-ok]`, 1 marked `[dispatch: main]`).

## Next steps

- [ ] Dispatch task 1.1 and 1.2 to an external executor (mechanical, fully
      specified — see tasks.md).
- [ ] Do task 2.1 in the main session once 1.1/1.2 land (needs judgment on
      test coverage).

## Caveats / traps

- `openspec new change` requires lowercase kebab-case names — `PKG-0001-demo`
  is rejected, use `pkg-0001-demo`. If your workspace's task IDs are
  uppercase elsewhere, decide on a casing convention before scaling this
  past one example.
- `design.md` was skipped on purpose: this change has no cross-cutting
  architecture, new dependency, or migration complexity, so it didn't meet
  any of the "when to include design.md" criteria in the schema.
