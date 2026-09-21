---
name: passdown-dispatch
description: Use before executing any multi-task plan or change, including before Superpowers executing-plans, to decide which tasks stay in the current session and which run on configured external CLI agents or explicitly authorized native subagents; verifies delegated results before marking tasks done
---

# Passdown Dispatch

The orchestrator session should stay small and cheap. Route each task to the
cheapest executor that can do it well; keep only judgment-heavy work in the
main session.

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

## Configuration (read first)

Build the effective passdown configuration root-to-nearest. Read applicable
`AGENTS.md` files from the workspace/repository root down to the current
directory, plus any parent file explicitly referenced by a thin entrypoint.
Merge `## passdown` keys in that order: nearer values override the same key and
inherit omitted keys. Resolve relative paths against the file that declared
them.

Read the effective `executors` entry, cheapest first:

```markdown
## passdown
- executors: agy, subagent, main   # cheapest first; omit what's unavailable
```

Detect the current host and its available tools before routing. Executor names
describe a target, not the host:

| Executor | How to invoke | Notes |
|---|---|---|
| `agy` (Antigravity CLI) | `agy --print "<prompt>" [--add-dir <path>]` | Non-interactive; `--continue` resumes the last thread |
| `kiro-cli` | `kiro-cli chat "<prompt>"` | Check non-interactive support with `--help` first |
| `codex` | Configured Codex adapter on a non-Codex host | On Claude Code this may be `/codex:rescue`; when the current host is Codex, skip this self-target instead of recursively running Codex |
| `subagent` | Current host's native subagent tool | Use only when the user explicitly asks for delegation/subagents and host policy permits it |
| `main` | current session | Reserve for judgment-heavy work |

Also read inherited `executor notes` lines in the effective configuration. They
record environment constraints and past failures (sandbox write scope,
network access, non-interactive permission gates) and **veto** the default
routing: a task that must write outside the repo, reach the network, or run
a toolchain wrapper that writes to its own install dir (e.g. `flutter`) is
incompatible with a sandboxed executor unless its sandbox was configured for
it beforehand. Executors cannot be reconfigured mid-dispatch — that is user
setup work, done before the executor earns its place in the list.

## Routing rules (starting point — tune per workspace)

- **Honor explicit tags first**: tasks planned with the passdown schema or the
  standalone markdown template may carry `[dispatch: external-ok]` or
  `[dispatch: main]` tags — follow them. Untagged tasks are classified by the
  rules below.
- **Mechanical, fully specified** (rename, apply a template, config change,
  boilerplate): cheapest external CLI executor.
- **Moderate, verifiable** (small feature with tests, clear spec): subagent
  or external executor with a verification step.
- **Judgment-heavy** (architecture, ambiguous requirements, security):
  main session, or a fresh dedicated session.
- A configured `subagent` is not implicit authorization. If the user has not
  explicitly requested delegation, keep the task in `main` or ask first.
- When unsure, try the cheaper compatible executor once; escalate on failure.
  Propose recording what worked **and what failed, with the root cause** in
  `executor notes`. Update shared AGENTS.md only when that write is within the
  requested task and does not overwrite concurrent changes.

## Completion authority

A delegated worker never accepts its own work. A delegated worker is any
executor other than the current session: an external CLI agent, or a native
subagent the host started. Its report is evidence, not acceptance.

| Field in the plan | Who may change it |
|---|---|
| Task text, paths, done criteria, verification | The planner (the host on the planner's behalf), never the worker |
| Task checkbox (`[ ]` / `[x]`) | The host, only after its own verification passes |
| `Dispatched:` outcome line | The host |

The worker implements the one task it was assigned and returns its result.
It must not edit plan checkboxes, `Dispatched:` lines, done criteria or
verification. If it finds a problem with those fields, it reports the finding
and the host decides.

**Accepted verdict.** A delegated task counts as accepted when its latest
`Dispatched:` line records `accepted` and names, after `verified:`, a check
the host ran. Lines written before the `accepted` wording existed count as
accepted when they report success and name a host check after `verified:`
(for example `— done; verified: npm test`), so upgrading passdown does not
reopen work that was already verified. Handoff and pickup apply this same
rule; anything else is not accepted.

For `main` tasks the host and the worker are the same actor, so the current
session keeps the usual flow: run the task's verification, then mark it
complete as you go. No `Dispatched:` line is needed.

## Dispatch contract (thin forwarder)

When sending a task to an external executor:

1. **Capture a pre-dispatch baseline**: repository root, branch, `git status
   --short`, tracked diff, and untracked paths. A dirty tree is allowed only
   when the task does not overlap pre-existing changes and the baseline makes
   ownership unambiguous. Otherwise keep the task in `main` or ask the user.
2. Build a **self-contained prompt** that names the task by an **exact task
   reference**: the plan path plus the task ID, with the task text, paths,
   done criteria and verification copied in. Never let the worker pick its
   own task from the pending list: two workers doing that can pick the same
   task.
   For OpenSpec-planned work, the worker can load context statelessly:
   `"Run: openspec instructions apply --change <name> --json for context,
   then implement only task <X.Y> of openspec/changes/<name>/tasks.md."`
   If the change uses a custom schema, the executor must be able to resolve
   it as a **real directory** — repo-local `openspec/schemas/<name>/` or
   user-level `~/.local/share/openspec/schemas/<name>/`; symlinks fail with
   "Unknown schema" (openspec CLI 1.5.0). Verify before dispatching.
3. Always include this authority clause in the prompt: *"You are a delegated
   worker. Implement only task <plan path>#<task ID>. Do not edit the plan
   file: no checkbox changes, no `Dispatched:` lines, no edits to done
   criteria or verification. Report your outcome, changed paths and
   verification evidence; the host decides whether the task is complete."*
4. Always include this environment clause in the prompt: *"If a command fails
   because of sandbox, permission, or network restrictions, STOP and report
   the error verbatim. Do not work around it (no HOME redirects, no local
   caches, no config or project-file edits)."* Environment failures are the
   orchestrator's to fix, not the executor's — an executor improvising around
   its sandbox burns time and leaves junk and unreviewable state behind.
5. Invoke with **one** adapter action. Do not babysit output line by line.
6. Return a **structured summary**: outcome, changed paths, verification
   evidence, and remaining work. Preserve sandbox, permission, and network
   environment errors verbatim; summarize successful intermediate output.
7. **Verify before trusting**: first compare the plan file against the
   baseline. A worker's `[x]` is never evidence. If a checkbox, a
   `Dispatched:` line, done criteria or verification changed since the
   baseline, restore it from the baseline only when the change is
   unambiguously the worker's — for example, nobody else could have edited
   the plan during the dispatch, or the worker's report shows the edit —
   and note the restore in the outcome line. If you cannot attribute the
   change safely (the user or another session may have edited the plan
   meanwhile), do not overwrite it and do not record a verdict: stop and
   report the conflict so the user can reconcile it.
   Then run the task's done criteria yourself (tests, `openspec status`,
   file checks). An unverified task stays unchecked. After a failed
   dispatch, compare against the baseline and remove only paths proven
   to be created or changed by that executor. Never run broad reset/clean
   commands and never discard pre-existing user changes. If attribution is
   ambiguous, stop and ask instead of cleaning or retrying.
8. **Record the verdict in the plan**: the host, never the worker, appends
   one line under the dispatched task, then sets the checkbox to match:
   - `- Dispatched: <executor> (<YYYY-MM-DD>) — accepted; verified: <check
     the host ran>` — verification passed; only now tick the task `[x]`.
   - `- Dispatched: <executor> (<YYYY-MM-DD>) — rejected: <reason>;
     verified: <check the host ran>` — the worker returned but verification
     failed; the task stays `[ ]`.
   - `- Dispatched: <executor> (<YYYY-MM-DD>) — failed: <root cause>` — the
     executor errored, hung or timed out; the task stays `[ ]`.
   Record failed and rejected dispatches too; the failure and its root cause
   are exactly what the next shift needs. If the host then finishes the task
   itself, it appends `- Dispatched: main (<YYYY-MM-DD>) — accepted;
   verified: <check>` so the latest line matches the checkbox.
9. Use only flags supported by the selected adapter. Execution/background and
   resume/fresh vocabulary is adapter-specific, not a portable contract.

## Rules

- Never mark a task complete based only on an executor's claim, and never on
  a checkbox the executor ticked itself.
- One task per dispatch unless tasks are trivially mechanical and share
  context.
- If an executor fails twice on the same task, escalate to the next tier —
  do not retry a third time.
- Give each dispatch a wall-clock budget. If a background job shows no fresh
  adapter-specific progress signal for ~10 minutes, check process liveness; a
  stale "running" status is a failure — cancel, compare against the baseline,
  and escalate. A hang-to-timeout in a non-interactive
  executor (e.g. an unanswerable permission prompt) counts as a failure too.
