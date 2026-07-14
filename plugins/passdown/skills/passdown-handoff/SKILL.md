---
name: passdown-handoff
description: Use when ending or pausing a work session — writes a session handoff log (the "passdown") so the next session or agent resumes cheaply from small files instead of replaying a large transcript
---

# Passdown Handoff

End every working session with a passdown: a small file the next shift reads
to catch up. State lives in files, never in the session.

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
- log_language: en   # or another language for human-facing logs
```

If a required key is still missing, ask where session logs should live and
suggest adding it to the appropriate `AGENTS.md`.

## Process

1. **Create ONE new log file**:
   `<log_dir>/YYYY-MM-DD_<short-topic>_<agent>-HHMMSS.md`. Before writing,
   check whether the path already exists. On collision, add an incrementing
   suffix (`-2`, `-3`, ...) and create a new file; never truncate or append to
   another session's or agent's file.

2. **Start with machine-readable frontmatter**, then the body sections (in
   the configured language). The frontmatter is what lets the next shift — or
   `passdown-pickup` — filter logs without reading them in full:

   ```markdown
   ---
   status: DONE          # DONE | IN_PROGRESS | BLOCKED
   branch: <git branch>
   agent: <agent identity — the host name (claude|codex|kiro) unless the workspace names agents>
   plan: <path to the plan/change this session executed, or none>
   ---
   ```

   The `agent` value must match the `<agent>` field in the filename. Body
   sections:
   - **Summary**: 2–5 sentences — what was worked on and the outcome.
   - **What was done**: concrete items with numbers; commit SHAs and key
     file paths (clickable).
   - **Next steps**: checkboxes the next session can start on immediately.
   - **Caveats / traps**: known pitfalls discovered this session. This is
     the highest-value section — task state lives in the plan, but traps
     live nowhere else.

3. **Sync task state**: if executing against a plan, update its checkboxes
   to match reality (for OpenSpec work: `tasks.md` of the change). Task
   state belongs in the plan; the log tells the story around it.

4. **Route leftovers**: unimplemented ideas/decisions go to the workspace's
   backlog or inbox per its conventions — not into the session log.

5. **Do not commit** unless the user asks or the workspace's conventions say
   sessions end with a commit.

## Rules

- The log complements, never duplicates, the plan: plan = which tasks are
  done; log = why we stopped here and what to avoid.
- Keep it short enough that the next session actually reads all of it.
- Write only your own log file; check `git status` before touching shared
  files (AGENTS.md, templates) to avoid overwriting another agent's work.
