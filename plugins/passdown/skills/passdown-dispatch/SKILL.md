---
name: passdown-dispatch
description: Use when executing tasks from a plan/change and deciding who should run each task — routes work to the cheapest capable executor (external CLI agents, subagents, or the main session) and verifies results before marking tasks done
---

# Passdown Dispatch

The orchestrator session should stay small and cheap. Route each task to the
cheapest executor that can do it well; keep only judgment-heavy work in the
main session.

## Configuration (read first)

Find the nearest `AGENTS.md` walking up from the current directory. Look for
an `executors` entry in the `## passdown` section, cheapest first:

```markdown
## passdown
- executors: agy, claude-subagent, main   # cheapest first; omit what's unavailable
```

Executors the skill knows how to drive:

| Executor | How to invoke | Notes |
|---|---|---|
| `agy` (Antigravity CLI) | `agy --print "<prompt>" [--add-dir <path>]` | Non-interactive; `--continue` resumes the last thread |
| `kiro-cli` | `kiro-cli chat "<prompt>"` | Check non-interactive support with `--help` first |
| `codex` | `/codex:rescue` from the codex plugin, if installed | Do not build a custom wrapper |
| `claude-subagent` | Agent tool, fresh context | Saves main-session context, not total tokens |
| `main` | current session | Reserve for judgment-heavy work |

Also read any `executor notes` lines in the same `## passdown` section. They
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
- When unsure, try the cheaper executor once; escalate on failure. Record
  what worked **and what failed, with the root cause** in the workspace
  AGENTS.md `executor notes` — negative results are the expensive ones to
  rediscover.

## Dispatch contract (thin forwarder)

When sending a task to an external executor:

1. Build a **self-contained prompt**: task text, relevant file paths, done
   criteria, and how to record completion (e.g. tick the checkbox in
   `tasks.md`). For OpenSpec-planned work, prefer stateless instructions:
   `"Run: openspec instructions apply --change <name> --json, then complete
   the next pending task and mark it [x]."` If the change uses a custom
   schema, the executor must be able to resolve it as a **real directory** —
   repo-local `openspec/schemas/<name>/` or user-level
   `~/.local/share/openspec/schemas/<name>/`; symlinks fail with "Unknown
   schema" (openspec CLI 1.5.0). Verify before dispatching.
2. Always include this environment clause in the prompt: *"If a command fails
   because of sandbox, permission, or network restrictions, STOP and report
   the error verbatim. Do not work around it (no HOME redirects, no local
   caches, no config or project-file edits)."* Environment failures are the
   orchestrator's to fix, not the executor's — an executor improvising around
   its sandbox burns time and leaves junk and unreviewable state behind.
3. Invoke with **one** command. Do not babysit output line by line.
4. Return/relay the executor's result **verbatim** — do not paraphrase or
   summarize it back into expensive tokens.
5. **Verify before trusting**: run the task's done criteria yourself (tests,
   `openspec status`, file checks). An unverified task stays unchecked. After
   a failed dispatch, diff the working tree and clean partial output (stray
   files, caches, half-applied edits) before the next attempt — never retry
   on a dirty tree.
6. Flags vocabulary (align with the codex plugin): `--background` / `--wait`
   for execution mode, `--resume` / `--fresh` for thread continuity.

## Rules

- Never mark a task complete based only on an executor's claim.
- One task per dispatch unless tasks are trivially mechanical and share
  context.
- If an executor fails twice on the same task, escalate to the next tier —
  do not retry a third time.
- Give each dispatch a wall-clock budget. If a background job shows no fresh
  progress signal (new log lines, an advancing `updatedAt`) for ~10 minutes,
  check process liveness; a stale "running" status is a failure — cancel,
  clean up leftovers, escalate. A hang-to-timeout in a non-interactive
  executor (e.g. an unanswerable permission prompt) counts as a failure too.
