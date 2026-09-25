# Executor cards

An executor card says how to drive one executor at one tested CLI version:
how to launch it headless, where its final output lands, how to extract the
`passdown.result/v1` payload, whether a session can be resumed, how to cancel
it, and which stop evidence is safe. `passdown-dispatch` keeps the policy;
cards keep the volatile mechanics.

## Lookup

`<name>.md` in this directory, overridden by a card of the same name in the
workspace's `executor_refs` directory (nearest `AGENTS.md` wins). The helper
takes that directory as `--card-dir` and copies the card into the attempt
directory at `new`, so a later card edit cannot change a running attempt's
safety decisions.

## Format

Markdown with a YAML frontmatter block. The full format is section 18 of the
v0.5 design (`docs/design/PDN-0004-v05-acceptance-recovery.md` in the passdown
repository). The keys the host and the helper read:

| Key | Meaning |
|---|---|
| `card`, `card_version` | Executor name and card revision; passed to `new --card <name>@<version>` |
| `measured.cli_version`, `measured.date`, `measured.evidence` | What was measured, when, and where the run log is |
| `capabilities.*` | Each `verified`, `unsupported` or `unverified`: `headless`, `structured_output`, `native_schema_enforcement`, `resume_session`, `session_id_observable`, `exit_code_meaningful`, `descendants_may_outlive`, `cancel_signal_honored`, `read_only_mode`, `sandbox_confined_writes` |
| `invocation.headless` | The one adapter action that launches the worker |
| `invocation.output_capture`, `invocation.result_extraction` | Where the output goes and the exact rule that finds the final payload |
| `invocation.resume` | Resume template; only when `resume_session` is `verified` |
| `invocation.cancel` | Signal, target, grace period and escalation |
| `stop.containment`, `stop.settle_seconds` | Scopes the executor was measured under; the artifact-stability gap for the second inspection |
| `permissions`, `environment_constraints` | Measured permission mechanism; routing vetoes |
| `discovery_hint` | How to find a live process for an attempt |
| `toolchain_check` | Command the worktree preflight runs |

Rules:

- `verified` needs a run of the recorded version that produced the evidence.
  Documentation alone gives `unverified`; a measured negative gives
  `unsupported`.
- The host uses only `verified` capabilities for protocol decisions.
- `exit+pgroup-empty` is safe stop evidence only when
  `descendants_may_outlive` is `unsupported`. Otherwise an attempt ends with
  `exit+scope-empty` (launched in a containment scope) or `owner-attested`.
- A card whose `cli_version` differs from the installed CLI is stale. Use it,
  record the real version, and flag the mismatch; never upgrade a capability
  by assumption.

## Without a card

An executor without a card is **not eligible** for a new delegated attempt:
the launch action, output capture and result rule have nowhere to come from.
Ineligible does not mean "the host does it instead". When owner policy
requires that executor, the task stays pending and the host reports the
missing card; it moves to another executor, the current session included,
only if the owner's policy or the owner allows it. See *Eligibility* in the
dispatch skill.

To make an executor eligible, write a card. A first card may mark every
capability `unverified`; it still has to state `invocation.headless`,
`invocation.output_capture` and `invocation.result_extraction`, and set
`stop.settle_seconds` above zero, because a parent exit cannot rule out a
surviving writer. Having a card does not make any capability measured and
does not lift an executor-note veto. With every capability `unverified`,
the host:

- ends every attempt with `owner-attested` — a person confirming no process
  for the attempt remains, not a click to approve the work — unless it
  launched the worker in a containment scope and the probe shows it empty;
- starts continuations fresh from files (no session resume).

A missing capability key in a card counts as `unverified`. The helper itself
only warns when a named card is missing and then reads every capability as
`unverified` with default values; that keeps old receipts readable, but it is
not an eligibility check. A card in `executor_refs` replaces the bundled card
of the same name as a whole file (fields are not merged), so a local
override must be complete.

Unmeasured invocation hints for executors that have no card yet. They are a
starting point for writing and measuring a card (see
`docs/EXECUTOR_SETUP.md` in the passdown repository), not an operational
dispatch contract:

| Executor | Headless invocation | Notes |
|---|---|---|
| `agy` (Antigravity CLI) | `agy --print "<prompt>" [--add-dir <path>]` | `--continue` resumes the last thread |
| `kiro-cli` | `kiro-cli chat --no-interactive "<prompt>"` | Check non-interactive support with `--help` first |
| `codex` | Configured Codex adapter on a non-Codex host | On Claude Code this may be `/codex:rescue`; skip it when Codex is the host |
