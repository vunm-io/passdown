# Executor setup: measuring and writing a card

An executor becomes eligible for delegated dispatch when it has an **executor
card**: a small Markdown file with YAML frontmatter that says how to launch it
headless, where its output lands, how to extract the `passdown.result/v1`
payload, how to cancel it, and which of its capabilities were measured. The
dispatch skill keeps the policy; the card keeps these volatile mechanics. The
format is section 18 of the v0.5 design
(`docs/design/PDN-0004-v05-acceptance-recovery.md`), summarized in
`plugins/passdown/skills/passdown-dispatch/references/executors/README.md`.

Cards live in two places. passdown ships measured cards in
`plugins/passdown/skills/passdown-dispatch/references/executors/`. A
workspace can add its own, or replace a shipped one, in the directory its
`## passdown` section names as `executor_refs`. A workspace card replaces
the shipped card of the same name as a whole file, so it must be complete.

First identify the host. An executor name is a target, not the current host:
when passdown already runs in Codex, `codex` is a self-target and is skipped.

## 1. Pre-flight: the executor can run unattended

Non-interactive modes (`--print`, `exec`, `--no-interactive`, stream output)
have nobody to answer permission prompts. Depending on the CLI, an
unanswerable prompt becomes a silent hang or an immediate denial.

- [ ] Run a trivial prompt end to end ("reply with exactly the word: pong")
      and note how long it takes and what the exit code is
- [ ] Find the executor's own permission mechanism (a trust list, an
      allowlist, a policy file). Never use a blanket skip-all-permissions
      flag as the default
- [ ] Run one representative toolchain command through the executor
      (`<tool> --version` is not enough: pick one that builds or tests).
      Toolchain wrappers that write to their own install dir, like Flutter's
      SDK cache, fail inside a write-restricted sandbox
- [ ] If the work needs package fetches, decide on network access
      explicitly, with its prompt-injection and exfiltration trade-off
- [ ] For cross-repo work, check that every target repository is inside the
      executor's writable roots

## 2. Measure

Measure through the real attempt lifecycle, in a disposable fixture
repository, never in a repository you care about. E-KIRO-1 is the worked
example: its runner (`docs/evidence/e-kiro-1/run.sh`) drives `new`, `arm`,
the launch, `observe`, `probe`, `result`, `inspect` and a verdict, and records
every run's prompt, transport, receipt and the process tree seen while it
ran. To measure another executor, adapt the launch line and the result
extraction.

Use a plan with four tasks: a read-only task, a bounded write to one named
file, a task that is deliberately missing a decision, and a long-running
task that writes slowly (a loop with `sleep 1`). Then:

| Run | What to do | Capabilities it decides |
|---|---|---|
| A | Read-only task, output in the executor's machine-readable format | `headless`, `structured_output`, `exit_code_meaningful`, the `result_extraction` rule; with no trust flags, half of `read_only_mode` |
| B | Bounded write, with the narrowest permission that allows it; also once with none | the `permissions` mechanism; scope behavior; the other half of `read_only_mode` (writes denied without trust) |
| C | The ambiguous task; the prompt says not to guess | whether the executor returns `needs_input` without writing |
| D | Answer C's question by resuming its session, with a prompt that leaves the task text out | `session_id_observable`, `resume_session`, `invocation.resume` |
| E | The long task, interrupted with the cancel signal to the process group, then separately with `KILL`; record the process tree during the run and after the exit | `cancel_signal_honored`, `descendants_may_outlive`, `stop.containment`, `settle_seconds`, `discovery_hint` |

Check `--help` of the installed version for an option that enforces an
output schema (`native_schema_enforcement`), and record the CLI version with
every run.

Put the result schema itself in every prompt (or pass it through the
executor's schema flag). E-KIRO-1 found that a worker follows a hand-written
description of the schema exactly, including its mistakes.

## 3. Write the card

- `verified` only when a run of the recorded version produced the evidence;
  `unsupported` only for a measured negative; everything else `unverified`.
- `descendants_may_outlive: unsupported` makes a plain process-group-empty
  exit a safe stop. Mark it only when no process started for an attempt can
  leave the process group. An executor with a shell tool can start a
  detached process on request, so it normally stays `unverified`, and its
  attempts end with owner attestation or a containment scope.
- With `descendants_may_outlive` not `unsupported`, `stop.settle_seconds`
  must be above zero.
- A card is eligible to launch only with `invocation.headless`,
  `invocation.output_capture` and `invocation.result_extraction`.
- Point `measured.evidence` at the recorded runs.

Then check it:

```bash
scripts/passdown-attempt validate --file <card>.md --as card
```

It refuses unknown keys and capability values, a `verified` or `unsupported`
value without evidence, and a card that lacks what a launch needs. For a card
shipped with passdown, `tests/skills.sh` runs the same check and requires the
evidence to exist in the repository.

When the installed CLI version moves past the card's `cli_version`, the card
is stale: hosts may still use it and flag the mismatch, but no capability is
upgraded by assumption. Re-measure what the release notes touch.

## 4. Record environment limits as executor notes

Some limits are about the machine, not the executor: sandbox write scope,
network, a toolchain that writes outside the repository. Keep those as
`executor notes` in the workspace `AGENTS.md`; dispatch reads them as routing
vetoes. Record what failed and why. Never record a workaround that redirects
`HOME`, creates substitute caches, or edits project configuration to get past
a sandbox.
