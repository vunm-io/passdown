---
name: passdown-dispatch
description: Use when executing tasks from a plan/change and deciding who should run each task — routes work to the cheapest capable executor (external CLI agents, subagents, or the main session) and verifies results before marking tasks done
---

# Passdown Dispatch

The orchestrator session should stay small and cheap. Route each task to the
cheapest executor that can do it well; keep only judgment-heavy work in the
main session.

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

- **Honor explicit tags first**: tasks planned with the passdown schema may
  carry `[dispatch: external-ok]` or `[dispatch: main]` tags — follow them.
  Untagged tasks are classified by the rules below.
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

## Dispatch contract (thin forwarder)

When sending a task to an external executor:

1. **Capture a pre-dispatch baseline**: repository root, branch, `git status
   --short`, tracked diff, and untracked paths. A dirty tree is allowed only
   when the task does not overlap pre-existing changes and the baseline makes
   ownership unambiguous. Otherwise keep the task in `main` or ask the user.
2. Build a **self-contained prompt**: task text, relevant file paths, done
   criteria, and how to record completion (e.g. tick the checkbox in
   `tasks.md`). For OpenSpec-planned work, prefer stateless instructions:
   `"Run: openspec instructions apply --change <name> --json, then complete
   the next pending task and mark it [x]."` If the change uses a custom
   schema, the executor must be able to resolve it as a **real directory** —
   repo-local `openspec/schemas/<name>/` or user-level
   `~/.local/share/openspec/schemas/<name>/`; symlinks fail with "Unknown
   schema" (openspec CLI 1.5.0). Verify before dispatching.
3. Always include this environment clause in the prompt: *"If a command fails
   because of sandbox, permission, or network restrictions, STOP and report
   the error verbatim. Do not work around it (no HOME redirects, no local
   caches, no config or project-file edits)."* Environment failures are the
   orchestrator's to fix, not the executor's — an executor improvising around
   its sandbox burns time and leaves junk and unreviewable state behind.
4. Invoke with **one** adapter action. Do not babysit output line by line.
5. Return a **structured summary**: outcome, changed paths, verification
   evidence, and remaining work. Preserve sandbox, permission, and network
   environment errors verbatim; summarize successful intermediate output.
6. **Verify before trusting**: run the task's done criteria yourself (tests,
   `openspec status`, file checks). An unverified task stays unchecked. After
   a failed dispatch, compare against the baseline and remove only paths proven
   to be created or changed by that executor. Never run broad reset/clean
   commands and never discard pre-existing user changes. If attribution is
   ambiguous, stop and ask instead of cleaning or retrying.
7. Use only flags supported by the selected adapter. Execution/background and
   resume/fresh vocabulary is adapter-specific, not a portable contract.

## Rules

- Never mark a task complete based only on an executor's claim.
- One task per dispatch unless tasks are trivially mechanical and share
  context.
- If an executor fails twice on the same task, escalate to the next tier —
  do not retry a third time.
- Give each dispatch a wall-clock budget. If a background job shows no fresh
  adapter-specific progress signal for ~10 minutes, check process liveness; a
  stale "running" status is a failure — cancel, compare against the baseline,
  and escalate. A hang-to-timeout in a non-interactive
  executor (e.g. an unanswerable permission prompt) counts as a failure too.
