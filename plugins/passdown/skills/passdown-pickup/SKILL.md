---
name: passdown-pickup
description: Use when starting or resuming work in a workspace that keeps passdown handoff logs — reads the latest handoff, plan state and unresolved dispatch attempts, verifies them against the working tree, and briefs the session so work resumes from files instead of a replayed transcript
---

# Passdown Pickup

Start of shift: read the previous passdown before touching anything. The
handoff wrote state into small files; pickup turns those files back into
working context for a fraction of what replaying a transcript costs.

Pickup is **read-only**. It reads logs, plans and the attempt store, and it
may run read-only probes, but it never writes a receipt, a claim, a plan or a
log, and it never starts executing. Recovery actions are proposed here and
carried out in the open through the *Reconcile* section of
`passdown-dispatch`.

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
- attempt_dir: <dir>                    # optional; default <git common dir>/passdown/attempts
- executor_refs: <dir>                  # optional; workspace executor cards
```

If `log_dir` is still missing, ask where session logs live and suggest adding
it to the appropriate `AGENTS.md`.

**The attempt helper.** Delegated dispatch records each attempt in a receipt
in the attempt store of the repository that holds the plan. Read it with
`scripts/passdown-attempt` in this skill's directory, passing `--store
<attempt_dir>` when that key is set and `--card-dir <executor_refs>` when that
key is set. Pickup uses only its read-only commands: `list`, `claims`,
`probe`, `digest` and `validate`. If `jq` is missing, say "attempt store not
readable: jq missing" in the briefing and treat every delegated `[x]` as
unconfirmed; do not guess.

## Process

1. **Locate the handoff**: list `<log_dir>` and sort by the filename's date
   and `HHMMSS` suffix, newest first. Read the newest log's frontmatter
   (`status`, `branch`, `agent`, `plan`, and `open_attempts` when present);
   also read the frontmatter of any other recent logs, in case another agent
   worked in parallel. Frontmatter first, full text only for the logs that
   matter — that is what keeps pickup cheap.
2. **Read the passdown**: for the relevant log(s), read Summary, Next steps,
   and especially Caveats / traps in full. Task state lives in the plan;
   session-scoped traps live nowhere but the log.
3. **Read the attempt store.** For each repository that holds a plan in
   `plan:` (and the current repository), run `passdown-attempt --json list
   --unresolved`. It lists every attempt that is unresolved or still holds a
   claim (C11), each with its recovery classes from the table below. For C2, C3 and C8 attempts, run
   `passdown-attempt probe <id>` to see whether the worker is still alive.
   Then run `passdown-attempt --json claims --repo <repo>` for the current
   repository and for every target repository an unresolved attempt names
   (`location`). A claim held by another planner's attempt is shown with that
   planner's store path. Every `open_attempts` ID from the latest handoff
   must appear in one of those stores; a missing one is *inconsistent* (its
   store may be gone) and is reported as an ownership risk.
4. **Verify against reality** — files may have moved on since the log was
   written:
   - the current branch vs the log's `branch:`;
   - `git status` and recent commits vs the log's "What was done";
   - each plan listed in `plan:` (a single path or a YAML list, resolved
     from the workspace root) — compare its checkboxes and any
     `Dispatched:` outcome lines against the log's next steps and the store;
   - **completion authority** in each plan (next section).
   Report any mismatch instead of silently reconciling it; the working tree,
   the plan and the store win over the log, and an inconsistent `[x]` does
   not win over a missing host verdict.
5. **Brief, then wait**: report status, verified next steps, the traps, and
   every unresolved attempt with its class, location, ownership risk and one
   proposed action. Pickup produces a briefing and a proposed first action —
   it never starts executing on its own. If the proposed work is a multi-task
   plan, or resolves an attempt, the `passdown-dispatch` gate and its
   *Reconcile* section still apply before anything is executed.

## Recovery classes

`list --unresolved` computes the class; pickup adds C9 and explains each
class in the briefing. **Ownership risk** means a worker may still be writing
(`running` or `unknown`): no other writer may start on that repository until
it is resolved. Render a rejection by its reason (**needs input**,
**blocked**, …), never as a bare "rejected".

| Class | Seen as | Ownership risk | Proposed action (carried out through dispatch *Reconcile*) |
|---|---|---|---|
| C1 never launched | `prepared` | No | Compare the location with the baseline read-only first. No writes → `abandon`. Writes → treat as C2. |
| C2 launch outcome unknown | `unknown`, no handle | **Yes** | Look for the process with the card's `discovery_hint`, inspect the location read-only. Never start another writer first; ask the owner to attest if no process remains. |
| C3 live or maybe live | `running`, or `unknown` with a handle | **Yes** | `probe`: alive → wait or cancel; gone with safe machine evidence → record the stop, then C4/C5; otherwise owner attestation. |
| C4 result, no verdict | `stopped`, valid result, `pending` | No | Run the acceptance lifecycle from `inspect`. |
| C5 stopped, no valid result | `stopped`, `pending`, result missing or invalid | No | Re-extract once; then inspect, reject `invalid_result`, and re-emit once, salvage or release. |
| C6 verdict, no projection | `accepted`, not projected | No | Re-check the task digest, the checks and the artifact digest; then finish the projection. |
| C7 stale | the task changed since `new` | Per observation | Resolve ownership risk first, then reject `stale`; new work is a new attempt. |
| C8 cancel unconfirmed | cancel requested, `running`/`unknown` | **Yes** | `probe`; escalate the cancel per the card; stop only with safe evidence. |
| C9 orphaned | another session's attempt, older than its dispatch budget (use one hour when none is recorded), not named in the latest handoff's `open_attempts` | Per observation | Surface it prominently with age and location, then classify it as C1–C8. |
| C10 interrupted continuation | unresolved, with `continues` set | Per observation | Show the chain; resolve its newest link as C1–C8. Nothing is re-asked. |
| C11 claim without a live holder | a claim held by a stopped attempt rejected with a claim-holding reason, or by an attempt whose store is unreadable | No, or **unknown** if the store is unreadable | Continue, salvage or `release-claim`; an unreadable store is released only after the owner confirms no writer. |

An attempt can carry more than one class (for example `C9,C2` or `C10,C3`);
report all of them.

## Completion authority

A delegated worker cannot accept its own work (see `passdown-dispatch`), so
check every `[x]` task that shows signs of delegation, and every task with a
receipt in the store:

- **A task with any unresolved attempt is not accepted**, whatever its plan
  lines say: brief it as *unaccepted, attempt unresolved*. This covers a
  worker that forged an `accepted` line and ticked the box before the host
  crashed.
- Otherwise the task's **latest** `Dispatched:` line decides. It is an
  accepted verdict when it records `accepted`, names a host check after
  `verified:`, and is one of:
  - a **v0.5 line** naming `attempt: <id>` whose receipt exists, is
    `accepted`, and is for this exact task (plan path and task ID);
  - a **host line**, `Dispatched: main …`, for work the host finished itself;
  - a **legacy line** without `attempt:`, only while the store holds no
    receipt at all for that task.
    Lines written before the `accepted` wording existed count as accepted when they report success and name a host check after `verified:`,
    under the same condition.
- `[x]` whose latest `Dispatched:` line is not an accepted verdict, or names
  an attempt whose receipt is missing, not accepted or for another task —
  **inconsistent**: the checkbox claims completion the host never recorded.
- `[x]` on a `[dispatch: external-ok]` task with no `Dispatched:` line at
  all — **unconfirmed**: nothing records who did it or whether it was
  verified.

Report each such task by plan path and task ID, and treat it as not
accepted — still pending verification — in the briefing and the proposed
first action. Dispatches from before v0.5 have no receipts; they are judged
by the plan lines alone, and pickup never back-fills a receipt for them.

## Rules

- Pickup is read-only: never write a receipt, a claim, a plan or a log, and
  never run `abandon`, `observe`, `cancel`, `verdict`, `release-claim` or any
  other mutating helper command. The host does that later, in the open,
  through dispatch *Reconcile*.
- Nothing uncertain is proposed as a retry. An attempt with ownership risk is
  never answered with "start another writer".
- An empty or missing `log_dir` is a fact to report, not an error to fix:
  say so and brief from plan, task and store state alone.
- Pickup does not fix an inconsistent `[x]` itself; the host that verifies
  the task (or unticks it) records the verdict, per `passdown-dispatch`.
- Never modify a previous shift's log. Corrections and discoveries belong in
  this session's own handoff or the workspace inbox.
- An `IN_PROGRESS` or `BLOCKED` log from another agent may mean that shift is
  still active — surface it before building on that work.
- Trust files over the transcript: when a summarized conversation and the
  logs disagree, the logs, the plan and the store are the source of truth.
