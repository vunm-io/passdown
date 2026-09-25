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
- attempt_dir: <dir> # optional; default <git common dir>/passdown/attempts
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
   open_attempts:        # only when delegated attempts are unresolved
     - pd-20260921T101530Z-3f9a1c2e
   ---
   ```

   `plan:` paths must resolve from the workspace root — no repo shorthand,
   arrows, or prose, because `passdown-pickup` opens them mechanically. A
   session that executed several plans lists them all:

   ```yaml
   plan:
     - repo-a/openspec/changes/slug-0004-short-name/
     - repo-a/openspec/changes/slug-0009-short-name/
   ```

   `open_attempts` lists every attempt that is unresolved when the log is
   written: run `passdown-attempt --json list --unresolved` (the helper in
   this skill's `scripts/` directory, with `--store <attempt_dir>` when that
   key is set) in each repository that holds a plan this session touched,
   and list every ID it prints. Omit the key when there are none. The next
   shift uses it to tell a known open attempt from an orphaned one. If `jq`
   is missing, write "attempt store not readable: jq missing" in Caveats /
   traps instead of guessing.

   The `agent` value must match the `<agent>` field in the filename. Body
   sections:
   - **Summary**: 2–5 sentences — what was worked on and the outcome.
   - **What was done**: concrete items with numbers; commit SHAs and key
     file paths (clickable).
   - **Next steps**: checkboxes the next session can start on immediately.
   - **Caveats / traps**: known pitfalls discovered this session. This is
     the highest-value section — task state lives in the plan, but a fresh
     trap lives nowhere else yet (step 4 promotes the durable ones). Name
     every unresolved attempt here too: its ID, task, recovery class,
     location, and whether it has ownership risk (a worker may still be
     writing, so nobody may start another writer there).

3. **Sync task state**: if executing against a plan, update its checkboxes
   to match reality (for OpenSpec work: `tasks.md` of the change). Reality
   means accepted work, not claimed work:
   - a task this session did itself (`main`) is `[x]` once its
     verification passed;
   - a delegated task is `[x]` only when its latest `Dispatched:` line is
     an accepted verdict as `passdown-dispatch` defines it: `accepted`
     with a check the host ran, and either naming `attempt: <id>` whose
     receipt is `accepted` for this task, or a host `main` line, or a legacy
     line for a task with no receipt at all. Lines written before the `accepted` wording existed count as accepted when they report success and name a host check after `verified:`
     — keep those `[x]` under the same condition. Never tick a delegated
     task because the worker reported success, because its files exist, or
     because the worker ticked the box itself;
   - never tick a task that has an unresolved attempt, whatever its lines
     say; it goes back to (or stays) `[ ]` and is named in Caveats / traps;
   - delegated work that is still unverified goes back to (or stays) `[ ]`,
     and the log's Caveats / traps names it as unverified so the next shift
     verifies it before building on it.

   Task state belongs in the plan; the log tells the story around it. Any
   done/total counts quoted in the log are then counted from the synced
   plan file — never recalled from the session; a drifted count sends the
   next shift to the wrong task.

4. **Route leftovers**: unimplemented ideas/decisions go to the workspace's
   backlog or inbox per its conventions — not into the session log. The
   same goes for traps with project lifetime (a toolkit default, a platform
   quirk — anything that still bites ten sessions from now): promote those
   into the repo's durable docs (`AGENTS.md` or the doc that owns the
   topic) and keep the log's copy as the session record. Only
   session-scoped traps live in the log alone.

5. **Do not commit** unless the user asks or the workspace's conventions say
   sessions end with a commit.

## Rules

- Handoff never resolves an attempt: no `abandon`, `observe`, `verdict`,
  `release-claim` or other mutating helper command. It records what is open;
  the next shift reconciles it through `passdown-dispatch`.
- The log complements, never duplicates, the plan: plan = which tasks are
  done; log = why we stopped here and what to avoid.
- Keep it short enough that the next session actually reads all of it.
- Write only your own log file; check `git status` before touching shared
  files (AGENTS.md, templates) to avoid overwriting another agent's work.
