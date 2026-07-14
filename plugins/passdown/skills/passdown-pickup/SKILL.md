---
name: passdown-pickup
description: Use when starting or resuming work in a workspace that keeps passdown handoff logs — reads the latest handoff and plan state, verifies them against the working tree, and briefs the session so work resumes from files instead of a replayed transcript
---

# Passdown Pickup

Start of shift: read the previous passdown before touching anything. The
handoff wrote state into small files; pickup turns those files back into
working context for a fraction of what replaying a transcript costs.

## Configuration (read first)

Build the effective passdown configuration root-to-nearest. Read applicable
`AGENTS.md` files from the workspace/repository root down to the current
directory, plus any parent file explicitly referenced by a thin entrypoint.
Merge `## passdown` keys in that order: nearer values override the same key and
inherit omitted keys. Resolve relative paths against the file that declared
them.

The effective configuration should contain:

```markdown
## passdown
- log_dir: <path for session logs>
- planning: markdown | openspec   # used to locate plan state
- plan_dir: <path for markdown plans>   # when planning: markdown
```

If `log_dir` is still missing, ask where session logs live and suggest adding
it to the appropriate `AGENTS.md`.

## Process

1. **Locate the handoff**: list `<log_dir>` and sort by the filename's date
   and `HHMMSS` suffix, newest first. Read the newest log's frontmatter
   (`status`, `branch`, `agent`, `plan`); also read the frontmatter of any
   other recent logs, in case another agent worked in parallel. Frontmatter
   first, full text only for the logs that matter — that is what keeps pickup
   cheap.
2. **Read the passdown**: for the relevant log(s), read Summary, Next steps,
   and especially Caveats / traps in full. Task state lives in the plan, but
   traps live nowhere else.
3. **Verify against reality** — files may have moved on since the log was
   written:
   - the current branch vs the log's `branch:`;
   - `git status` and recent commits vs the log's "What was done";
   - the plan named in `plan:` — compare its checkboxes and any
     `Dispatched:` outcome lines against the log's next steps.
   Report any mismatch instead of silently reconciling it; the working tree
   and the plan win over the log.
4. **Brief, then wait**: report status, verified next steps, and the traps.
   Pickup produces a briefing and a proposed first action — it
   never starts executing on its own. If the proposed work is a multi-task
   plan, the `passdown-dispatch` gate still applies before implementation.

## Rules

- An empty or missing `log_dir` is a fact to report, not an error to fix:
  say so and brief from plan/task state alone.
- Never modify a previous shift's log. Corrections and discoveries belong in
  this session's own handoff or the workspace inbox.
- An `IN_PROGRESS` or `BLOCKED` log from another agent may mean that shift is
  still active — surface it before building on that work.
- Trust files over the transcript: when a summarized conversation and the
  logs disagree, the logs and the plan are the source of truth.
