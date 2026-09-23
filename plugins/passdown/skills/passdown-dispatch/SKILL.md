---
name: passdown-dispatch
description: Use before executing any multi-task plan or change, including before Superpowers executing-plans, to decide which tasks stay in the current session and which run on configured external CLI agents or explicitly authorized native subagents; records every delegated attempt in a durable receipt and verifies delegated results before marking tasks done
---

# Passdown Dispatch

Keep work in the current session unless a named reason justifies delegating
it. When a task is delegated, the attempt gets a durable receipt before the
worker can start, the worker's report is evidence rather than acceptance, and
an interrupted attempt is recovered from files, never retried on a guess.

## Execution gate

Run this skill **before execution begins** when any of these conditions apply:

- the plan or change has three or more pending tasks;
- any task has a `[dispatch: ...]` tag;
- any pending task is independently delegable or mechanical; or
- another installed skill or plugin is about to execute the plan, including
  Superpowers `executing-plans`.

Do not enter an inline plan executor, Superpowers `executing-plans`, an
external CLI adapter, or a native subagent executor until routing is complete.
The gate may still route every task to `main`; the required outcome is an
explicit per-task routing decision before implementation starts.

Materialize the decision: when the plan lives in a file (a markdown plan or an
OpenSpec `tasks.md`), write the routing decision into that file before
execution starts — add the missing `[dispatch: ...]` tag to each untagged
task. The tag records where the task actually runs: if you keep a
`[dispatch: external-ok]` task in the current session, change its tag to
`[dispatch: main]`. A decision that lives only in the session transcript is
lost at the next handoff.

A direct user instruction to execute one clearly scoped task does not require
this gate unless that task itself requests delegation. When a user explicitly
asks to bypass delegation and work only in the current session, honor that
choice and route the relevant tasks to `main` rather than silently skipping the
gate.

Before routing, check the attempt store for unresolved attempts
(`passdown-attempt list --unresolved`). Any unresolved attempt goes through
[Reconcile](#reconcile) first; a task with an unresolved attempt is not free
for a new one.

## Configuration (read first)

Build the effective passdown configuration root-to-nearest. Read applicable
`AGENTS.md` files from the workspace/repository root down to the current
directory, plus any parent file explicitly referenced by a thin entrypoint.
Merge `## passdown` keys in that order: nearer values override the same key and
inherit omitted keys. Resolve relative paths against the file that declared
them.

```markdown
## passdown
- executors: agy, subagent, main          # available executors; the order is not a cost ranking
- attempt_dir: <dir>                      # optional; default <git common dir>/passdown/attempts
- worktree_dir: ../.passdown-worktrees/   # optional; no default (see Isolation)
- executor_refs: <dir>                    # optional; workspace executor cards, nearest wins
- concurrency_profiles:                   # optional; none are built in
  - <name>: <evidence> — <what it covers>
```

Detect the current host and its available tools before routing. Executor
names describe a target, not the host. `main` is the current session.
`subagent` is the current host's native subagent tool. `codex` is an
external executor only from a non-Codex host: when the current host is Codex,
skip this self-target instead of recursively running Codex.

**Executor cards.** How to invoke, capture, extract, resume and cancel one
executor lives in its card, not in this skill:
`references/executors/<name>.md` next to this file, overridden by a card of
the same name under `executor_refs`. A card's capabilities are `verified`,
`unsupported` or `unverified`; use only `verified` ones for protocol
decisions. A missing card means every capability is `unverified`. A card
whose `cli_version` differs from the installed CLI is stale: use it, record
the real version, and say so in your report. See
`references/executors/README.md`.

Also read inherited `executor notes` lines in the effective configuration. They
record environment constraints and past failures (sandbox write scope,
network access, non-interactive permission gates) and **veto** routing: a
task that must write outside the repo, reach the network, or run a toolchain
wrapper that writes to its own install dir (e.g. `flutter`) is incompatible
with a sandboxed executor unless its sandbox was configured for it
beforehand. Executors cannot be reconfigured mid-dispatch — that is user
setup work, done before the executor earns its place in the list.

**The attempt helper.** Every delegated attempt goes through
`scripts/passdown-attempt` in this skill's directory. It is a stateless
Bash + `jq` CLI: it writes receipts, checks every transition and never
launches, signals or waits for a worker. Pass `--store <attempt_dir>` when
the key is set and `--card-dir <executor_refs>` when that key is set. Every
mutating command takes `--rev <n>`, the receipt's current `rev`. Exit codes:
`2` usage, `3` invalid transition or failed precondition, `4` validation
failed, `5` rev conflict (re-read the receipt and re-plan, do not force),
`6` guard refused (a claim is held, the depth guard, the read guard).
**Without `jq`, delegation is refused:** keep every task in `main` and tell the
user that delegated v0.5 dispatch needs `jq`.

## Routing ladder

Route each task to the first tier that fits:

```text
current session  →  authorized native delegation  →  external executor (named reason)
```

| Tier | Choose when | Record |
|---|---|---|
| `current` | Small work; tightly coupled reasoning; uncommitted context; costly to specify or verify elsewhere; **any uncertainty** | `[dispatch: main]`; no receipt |
| `native` | Delegation is useful (a fresh context, bounded parallel read work) **and** the user or host policy explicitly authorizes subagents | Receipt, `--tier native`, reason code `fresh-context` or `parallelism` |
| `external` | A named difference justifies crossing the provider boundary | Receipt, `--tier external`, reason code `required-environment`, `measured-specialization`, `quota`, `owner-policy` or `review-experiment`, plus a one-line reason |

- **Honor explicit tags first.** `[dispatch: main]` stays in the current
  session. `[dispatch: external-ok]` permits delegation; it does not require
  it, and the ladder still decides.
- Owner policy, such as a workspace routing table by kind of work, may select
  the external tier directly; its reason code is `owner-policy`.
- Availability alone never authorizes delegation. A configured `subagent` is
  not implicit authorization: if the user has not explicitly requested
  delegation, keep the task in `main` or ask first.
- `measured-specialization` must point at something measured: a card note or
  a recorded experiment. No scores, no guesses.
- An executor note that vetoes the task rules that executor out.
- Depth is one. A worker you launch never dispatches to another external
  agent CLI through passdown; the helper refuses `new --tier external` inside
  a worker (`PASSDOWN_ATTEMPT` is set). A provider's own native subagents are
  the provider's business.

`main` work keeps the usual flow and needs no receipt. A native subagent needs
a receipt when its output can complete a plan task (a review or analysis task
with its own checkbox). Only advisory read-only work that cannot change
canonical state may run without one.

## Completion authority

A delegated worker never accepts its own work. A delegated worker is any
executor other than the current session: an external CLI agent, or a native
subagent the host started. Its report is evidence, not acceptance.

| Field in the plan | Who may change it |
|---|---|
| Task text, paths, done criteria, verification | The planner (the host on the planner's behalf), never the worker |
| Task checkbox (`[ ]` / `[x]`) | The host, only after its verdict is persisted |
| `Dispatched:` outcome line | The host |
| Receipts and results in the attempt store | The host, only through the helper |

The worker implements the one task it was assigned and returns its result.
It must not edit plan checkboxes, `Dispatched:` lines, done criteria or
verification. If it finds a problem with those fields, it reports the finding
and the host decides.

**Accepted verdict.** A delegated task counts as accepted when its latest
`Dispatched:` line records `accepted`, names after `verified:` a check the
host ran, and — when it names `attempt: <id>` — that receipt is `accepted`
for this task. A task with any unresolved attempt is never accepted, whatever
its lines say. Lines written before the `accepted` wording existed count as
accepted when they report success and name a host check after `verified:`
(for example `— done; verified: npm test`), so upgrading passdown does not
reopen work that was already verified; such legacy lines count only while
the store holds no receipt for that task. Handoff and pickup apply this same
rule; anything else is not accepted.

For `main` tasks the host and the worker are the same actor, so the current
session keeps the usual flow: run the task's verification, then mark it
complete as you go. No `Dispatched:` line is needed.

## Isolation

Scheduling is **serial by default**. Choose the isolation per attempt:

| Class | Conditions (all required) | Isolation |
|---|---|---|
| Read-only | The task writes nothing (review, analysis) | `read-only`, `--kind read`. Claim-free only with an enforced mutation guard the card marks `verified`; otherwise it takes the claim like a writer |
| Simple repo-file edit | External writer; inputs committed at the base commit; no uncommitted context; no environment bootstrap (installs, services, `.env`, generated inputs); no shared mutable build or service state; `worktree_dir` configured; the card's `toolchain_check` passes in the worktree | `worktree`: one fresh worktree per attempt, still serial |
| Resource-coupled or uncertain | Anything else (Flutter/Gradle/Cargo caches and daemons, package installs, databases, ports, `.env`, generated outputs, uncommitted local context) | `current-checkout`: one attributable writer, baseline captured |
| Concurrent writers | Separate worktrees **and** a declared, validated concurrency profile | `worktree` + `--profile` |

- `worktree_dir` has no default. Without it the simple class falls back to
  `current-checkout`. Each attempt's worktree is `<worktree_dir>/<attempt-id>`
  on branch `passdown/<attempt-id>` from the base commit. It is kept after a
  rejection for inspection; removing it is a host action after the verdict,
  never automatic while the attempt is unresolved. A worktree is not a
  sandbox: caches, ports, `HOME`, credentials and Git's object store are
  still shared.
- **Read-only mutation guard.** A read attempt skips the claim only with
  `--mutation-guard readonly:<mechanism>` (the card's `read_only_mode` is
  `verified`) or `--mutation-guard snapshot+sandbox` (a `git archive` copy
  outside the target **and** a `verified` `sandbox_confined_writes`). A copy
  alone is not enough.
- **Host writes.** While any attempt holds a location's claim, do not edit
  that location yourself. Change it through an attempt that receives the
  claim by transfer (a salvage or a `--tier current` continuation), or run
  `release-claim` first and give up the leftover output. To keep working in
  your own checkout during a delegated attempt, give the attempt a worktree.
- **Machine-global resources are host policy.** Shared ports, daemons,
  databases and mutable global caches are not claimable. Do not start such a
  resource-coupled attempt while any other attempt you launched, in any
  repository, has ownership risk.
- A concurrency profile covers only worktree-local resources; the helper
  rejects one that declares any other key. Without a profile every writer
  takes the exclusive `repo` claim.

## Delegated attempt lifecycle

Each numbered step carries a step name in backticks. The reference host in
passdown's test suite performs the same named steps in the same order, and a
test checks that the two stay in step. Steps marked *(when …)* are skipped
otherwise.

1. `route` — **Route.** Pick the tier with the ladder and record the reason
   code and reason. Uncertainty routes to the current session, not to a
   speculative dispatch.
2. `isolate` — **Choose isolation and run its preflight.** For the simple
   class check that the inputs are committed (`git status --porcelain --
   <task paths and inputs>` is empty), that `worktree_dir` is set, and that
   the card's `toolchain_check` can run. If preflight fails, fall back to
   `current-checkout` or keep the task in `main` **before** anything is
   created, never mid-attempt.
3. `new` — **Create the attempt.** `passdown-attempt new --task-ref
   <plan path>#<task id> --kind write|read --tier native|external
   --reason-code <c> --reason <text> --executor <name> --card <name@version>
   --host <host agent> --session <session id> --place-repo <target repo>
   --isolation <i> [--worktree-dir <dir>] [--profile <p>] [--input <file>]...
   [--mutation-guard <g>]`. It snapshots the task and a baseline, takes the
   writer claim on the target repository and prints the attempt ID. Exit `6`
   names the attempt that holds the claim: report it and route elsewhere or
   wait. Never work around a refusal. For a worktree attempt, now create the
   worktree at the receipt's `place.location` (`git worktree add -b
   passdown/<id> <location> <base_commit>`); if that fails, `abandon` the
   attempt and fall back.
4. `prompt` — **Build a self-contained prompt.** Name the task by an
   **exact task reference** — the plan path plus the task ID — and copy in the task
   text, paths, done criteria and verification. Never let the worker pick its
   own task from the pending list: two workers doing that can pick the same
   task. For OpenSpec-planned work the worker can load context statelessly:
   `"Run: openspec instructions apply --change <name> --json for context,
   then implement only task <X.Y> of openspec/changes/<name>/tasks.md."` A
   custom schema must resolve as a **real directory** — repo-local
   `openspec/schemas/<name>/` or user-level
   `~/.local/share/openspec/schemas/<name>/`; symlinks fail with "Unknown
   schema" (openspec CLI 1.5.0). Always include these four clauses verbatim:
   - *Authority:* "You are a delegated worker. Implement only task
     <plan path>#<task ID>. Do not edit the plan file: no checkbox changes,
     no `Dispatched:` lines, no edits to done criteria or verification.
     Report your outcome, changed paths and verification evidence; the host
     decides whether the task is complete."
   - *Environment:* "If a command fails because of sandbox, permission, or
     network restrictions, STOP and report the error verbatim. Do not work
     around it (no HOME redirects, no local caches, no config or
     project-file edits)." Environment failures are the host's to fix;
     improvising around a sandbox leaves junk and unreviewable state behind.
   - *Result:* "End with one JSON object matching `passdown.result/v1` for
     attempt <id> as your final output. If the task is ambiguous, do not
     guess and do not write: return `needs_input` with your question. If a
     command is denied by sandbox, permission or network rules, stop and
     return `blocked` with the error verbatim."
   - *Depth:* "Do not dispatch this work, or any part of it, to another
     external agent CLI. Your provider's own native subagents are your
     provider's business."
   When the card marks `native_schema_enforcement` as `verified`, also pass
   `schemas/result.v1.schema.json` from this skill's directory. Host
   validation stays the rule either way. Never tell the worker where the
   attempt store is.
5. `arm` — **Arm.** `passdown-attempt arm <id> --rev <n> --prompt <file>`
   stores the exact prompt and records the observation `unknown` **before**
   launch. Launch only after it returns `0`. A crash from here on leaves an
   attempt that recovery treats as possibly running.
6. `launch` — **Launch** with **one** adapter action from the card, in a new
   process group, with `PASSDOWN_ATTEMPT=<id>` in its environment and its
   output redirected to `<attempt dir>/transport.log`. Where the platform
   offers an unprivileged containment scope (Linux `systemd-run --user
   --scope` or a cgroup, a Windows job object), launch inside it. Use only
   flags the card lists; execution, background and resume vocabulary is
   adapter-specific. Record the process start time (`ps -o lstart= -p <pid>`)
   right after spawning. Do not babysit output line by line. A native
   subagent is launched by the host's own subagent tool; write its final
   message to `transport.log`. It has no process group to probe, so unless
   the host's card measured otherwise, its stop is `owner-attested`.
7. `running` — **Observe running.** `passdown-attempt observe <id> running
   --rev <n> --pid <pid> --pid-started <start time> --pgid <pgid>` (or
   `--provider-session <s>`). If you never get an identity, the attempt stays
   `unknown`. That is correct, not an error.
8. `cancel` — *(when the budget is exceeded or the user asks)* **Wait,
   cancel if needed.** Give each attempt a wall-clock budget. Silence is not
   failure: a job with no fresh progress signal has exceeded its budget, it
   has not failed. Record the request first with `passdown-attempt cancel
   <id> --rev <n> --method <method>`, then send the card's cancel signal
   (for example `INT` to the process group, then `TERM` after the card's
   grace period). A cancel request does not prove termination. Never start a
   replacement writer while this one has ownership risk.
9. `exited` — **The worker exits.** Collect its exit code.
10. `parent-exited` — *(when the probe gives no safe stop evidence)*
    **Record the uncertain stop.** Run `passdown-attempt probe <id>`. When its
    `safe_evidence` is empty, record `observe <id> unknown --rev <n> --note
    <text> --parent-exited`: the parent exited, but surviving descendants
    are not ruled out. The attempt keeps ownership risk and its claim. Ask the
    user to confirm no process for this attempt remains (give them the card's
    `discovery_hint` and the process group); without that confirmation, stop
    the lifecycle here and report the attempt as unresolved.
11. `stopped` — **Record the safe stop.** `passdown-attempt observe <id>
    stopped --rev <n> --evidence <e> [--exit <code>]` with evidence the probe
    reported as safe for the card (`exit+scope-empty`, or `exit+pgroup-empty`
    only when the card measured `descendants_may_outlive: unsupported`), or
    `owner-attested --attested-by <who>` after the user confirmed. The helper
    refuses anything weaker. A bare parent exit or a provider's final event
    is never stop evidence.
12. `result` — **Extract the result.** Apply the card's `result_extraction`
    rule to `transport.log`, write the payload to a file and run
    `passdown-attempt result <id> --rev <n> --payload <file>`. The helper
    validates it; an invalid or missing payload is recorded, not repaired by
    hand.
13. `inspect` — **Inspect the artifact.** `passdown-attempt inspect <id>
    --rev <n>` measures the actual submission (commits, staged, unstaged and
    untracked output) against the baseline, the scope and the plan. When the
    card's `settle_seconds` is above zero, wait that long and `inspect` again:
    acceptance needs two equal inspections that far apart.
14. `verify` — **Verify as the host.** Decide from the receipt, in order:
    - result not valid → reject `invalid_result` (see *Re-emit and salvage*);
    - disposition `needs_input`, `blocked` or `failed` → reject
      `needs_input`, `blocked` or `worker_failed`; report the question or the
      blocker verbatim to the user;
    - `plan_touched` → compare the plan file against the baseline. A worker's
      `[x]` is never evidence. If a checkbox, a `Dispatched:` line, done
      criteria or verification changed since the baseline,
      restore it from the baseline only when the change is unambiguously the worker's
      — for example, nobody else could have edited the plan during the
      dispatch, or the worker's report shows the edit — and reject
      `plan_tampered`. If you cannot attribute the change safely (the user or
      another session may have edited the plan meanwhile), do not overwrite it
      and do not record a verdict: stop and report the conflict so the user
      can reconcile it;
    - `out_of_scope` not empty → reject `scope_violation`;
    - otherwise run the task's own verification commands yourself, saving each
      command's output to a file. Never replay the worker's evidence on
      trust. For a worktree attempt whose done criteria need the integrated
      tree, integrate first (apply the diff or cherry-pick into your
      checkout), verify there, and pass `--integrated-into <dir>
      --integrated-head <sha>`; a conflict or failing integrated check
      rejects `integration_failed`.
15. `verdict` — **Persist the verdict.** `passdown-attempt verdict <id>
    accept --rev <n> --check "<command>=<exit>:<output file>"` or `verdict
    <id> reject --rev <n> --reason-code <code> --reason <text>`. The helper
    recomputes the task and artifact digests. A task edited since `new` is
    `stale`: reject it and create a new attempt for the new revision. A
    refused accept is reported, never forced.
16. `plan-edit` — **Project to the plan.** Only now edit the plan: append one
    line under the task, then set the checkbox to match.
    - `- Dispatched: <executor> (<YYYY-MM-DD>) — accepted; verified: <check
      the host ran>; attempt: <id>` — tick the task `[x]`.
    - `- Dispatched: <executor> (<YYYY-MM-DD>) — rejected: <reason>;
      verified: <check the host ran, or ->; attempt: <id>` — the task stays
      `[ ]`. Render the reason (`needs input`, `blocked`, `verification
      failed`), never a bare "rejected".
    Record rejections too; the reason is exactly what the next shift needs.
    If you then finish the task yourself, append `- Dispatched: main
    (<YYYY-MM-DD>) — accepted; verified: <check>` so the latest line matches
    the checkbox.
17. `projected` — *(when accepted)* **Mark the projection.**
    `passdown-attempt projected <id> --rev <n> --plan <plan file>`. This
    resolves the attempt and releases its claim.

Return a **structured summary** to the user for each dispatched task:
executor, attempt ID, outcome, changed paths, verification evidence and
remaining work. Preserve sandbox, permission and network environment errors
verbatim; summarize successful intermediate output.

**Environment denial.** A `blocked` result, or sandbox or permission errors in
`transport.log`, is recorded and rejected `blocked`. Never widen permissions,
redirect `HOME`, add trust flags or switch executors silently to get past it.
After the user fixes the environment, run a continuation.

**Cleanup after a failed attempt.** Leave the leftover output in place while
the claim holds it (see *Host writes*). When you give it up with
`release-claim`, compare the location against the baseline and remove only
paths proven to be created or changed by that attempt. Never run broad
reset/clean commands and never discard pre-existing user changes. If
attribution is ambiguous, stop and ask instead of cleaning or retrying.

## Continuation, re-emit and salvage

- **`needs_input` / `blocked`.** The attempt is rejected with that reason and
  keeps the claim, so its partial output stays attributable. Put the user's
  answer in a file and run `passdown-attempt new --continues <id> --answer
  <file> ...`: the claim transfers to the new attempt, which runs steps 4–17
  in the same location. Resume the provider session only when the card marks
  `resume_session` as `verified`; otherwise launch fresh with the task, the
  question and the answer. Reusing a provider session never reuses an
  attempt ID.
- **Re-emit, at most once per chain.** A safely stopped attempt with an
  invalid or missing result: reject it `invalid_result` first (it keeps the
  claim), then `new --kind reemit --continues <id>`. The re-emit prompt asks
  only for the final result of the work already done and forbids file
  changes. If `inspect` shows the re-emit wrote, reject it `reemit_wrote`.
  A second re-emit in the chain is refused.
- **Salvage.** To finish unaccepted leftover output yourself, run `new --kind
  salvage --tier current --continues <id>`. The claim transfers to you; do the
  work in the open, then inspect, verify and record a verdict as usual. The
  coding task is never re-run just to repair its report.
- **Give up the output.** `passdown-attempt release-claim <id> --rev <n>
  --attested-by <who> --reason <text>` on a stopped attempt.

## Reconcile

Pickup is read-only: it lists unresolved attempts with a recovery class and
one proposed action each. Reconcile is where the host carries those actions
out, in the open, through the helper. **Nothing uncertain is retried
automatically, and no second writer starts while an attempt has ownership
risk.**

| Class | Seen as | Action |
|---|---|---|
| C1 never launched | `prepared` | Check the location for writes since the baseline. None → `abandon`; the task is free. Writes found → treat as C2 (`abandon` then requires `--attested-by`). |
| C2 launch outcome unknown | `unknown`, no handle | Inspect the location read-only for writes; look for the process with the card's `discovery_hint`. A writer found → C3. The user attests no writer remains → `observe stopped --evidence owner-attested`, then continue as C4/C5. Never start another writer first. |
| C3 live or maybe live | `running`, or `unknown` with a handle | `probe`. Same pid and start time alive → wait or cancel. Gone with safe evidence → `observe stopped`, then C4/C5. Gone without it → `observe unknown --parent-exited`; ask the owner to attest, or wait. The claim stays held throughout. |
| C4 result, no verdict | `stopped`, valid result, `pending` | Resume the lifecycle at step 13 (`inspect`). |
| C5 stopped, no valid result | `stopped`, `pending`, result missing or invalid | Try step 12 once more from `transport.log`; still nothing → re-emit once, salvage or reject. |
| C6 verdict, no projection | `accepted`, not projected | Recompute the task digest. Changed → do not project; report the verdict as historical for the old revision. Equal → re-run the recorded checks against the current tree, then confirm `digest artifact <id>` still equals the accepted artifact digest; only then do steps 16–17 (skip 16 if the plan line already names the attempt). |
| C7 stale | the task changed since `new` | Resolve ownership risk first (C2/C3), then reject `stale`. New work is a new attempt. |
| C8 cancel unconfirmed | cancel requested, `running`/`unknown` | `probe`; escalate the cancel method per the card; confirm the stop only with safe evidence. The claim stays held until then. |
| C9 orphaned | another session's attempt, older than the card's budget, not in the latest handoff's `open_attempts` | Surface it with age and location, then classify it as C1–C8. |
| C10 interrupted continuation | unresolved attempt with `continues` set | Show the chain; resolve its newest link as C1–C8. Nothing is re-asked. |
| C11 claim without a live holder | `claims` shows a key held by a stopped attempt, or its store is unreadable | Holder stopped → continue, salvage or `release-claim`. Store unreadable → treat as ownership risk; release only after the owner confirms no writer. |

A task with an unresolved attempt is never counted accepted from the plan
alone, and a `Dispatched: … attempt: <id>` line whose receipt is missing, not
accepted or for another task is *inconsistent*: report it, do not repair the
plan to match.

## Rules

- Never mark a task complete based only on an executor's claim, and never on
  a checkbox the executor ticked itself.
- One task per attempt unless tasks are trivially mechanical and share
  context.
- If an executor fails twice on the same task (count attempts with
  `passdown-attempt list --task <plan>#<id>`), escalate to the next tier —
  do not retry a third time.
- `unknown` is neither success nor failure. Never turn silence, a timeout or
  a missing result into `failed`, and never start another writer on the same
  target while an attempt has ownership risk.
- Never edit `receipt.json`, `result.json` or claim files by hand. If the
  helper refuses a step, the refusal is the finding: report it.
- When unsure which executor fits, keep the task in the current session.
  Propose recording what worked **and what failed, with the root cause** in
  `executor notes` or the executor's card. Update shared AGENTS.md only when
  that write is within the requested task and does not overwrite concurrent
  changes.
