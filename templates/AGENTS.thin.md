# AGENTS.md — <repo-name>

> Thin entrypoint. The source of truth for agents working in this workspace is
> the parent workspace's `AGENTS.md` — read it first: `../AGENTS.md`
> (adjust the relative path to your layout).

## Repo-specific notes

<!-- Only what differs from the parent: build commands, test commands, local invariants. -->

## passdown

Before executing any multi-task plan, the agent MUST invoke
`passdown-dispatch` and classify all pending tasks. This rule applies even when
another installed skill or plugin provides its own plan executor, including
Superpowers `executing-plans`. The routing gate may assign every task to
`main`, but it must run before implementation starts.

<!-- Per-repo overrides for passdown skills. Omit keys to inherit the parent's. -->
<!--
- inbox: docs/inbox/
- planning: markdown            # markdown | openspec
- plan_dir: docs/plans/          # used when planning: markdown
- log_dir: docs/log/
- log_language: en
- executors: agy, subagent, main   # available executors; order is not a cost ranking
- attempt_dir: <dir>                     # default: <git common dir>/passdown/attempts, outside every worktree
- worktree_dir: ../.passdown-worktrees/  # no default; without it delegated writers use the current checkout
- executor_refs: docs/executors/         # workspace executor cards; override the bundled ones by name
- concurrency_profiles:                  # none are built in; each needs recorded evidence
  - docs-only: tested <date> (<evidence path>) — edits only repo files, no build, no services
-->
