# Changelog

All notable changes to passdown are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0-beta.1] - 2026-09-21

Beta build for the `release/v0.5.0` testing window — not a GitHub release.

### Added

- v0.5 protocol contracts (PDN-0004, slice S1): JSON Schemas for the attempt
  receipt, the worker result and the writer claim under `schemas/protocol/`
  (`passdown.receipt/v1`, `passdown.result/v1`, `passdown.claim/v1`), with a
  fixture corpus in `tests/fixtures/attempt/` that covers every state
  combination and result rule of the v0.5 design. `tests/contracts.sh` checks
  the corpus with a pinned JSON Schema validator in CI; each invalid fixture
  must fail at the JSON pointer its manifest names. Nothing consumes the
  contracts yet.
- Deterministic attempt helper (PDN-0004, slice S2):
  `scripts/passdown-attempt`, a Bash + `jq` CLI that creates attempt
  receipts in the Git common dir and applies every allowed transition of the
  v0.5 design and refuses the rest. It validates worker results, computes
  task and artifact digests, and guards writers with a claim kept in the
  target repository: taking, transferring and releasing a claim survive a
  crash at any step. Every receipt write is a locked compare-and-write that
  is checked against the published schemas before it lands. Byte-identical
  copies ship in the dispatch, pickup and handoff skills
  (`scripts/sync-bundled.sh`; CI fails on drift). `tests/attempt.sh` covers
  the transition table, schema conformance, golden digests, a crash-point
  sweep and concurrency races on Linux, macOS (bash 3.2) and Windows (Git
  Bash with `jq`). `scripts/doctor.sh` now reports a missing `jq`. No skill
  calls the helper yet.
- Behavioral interruption harness (PDN-0004, slice S3): `tests/interrupt.sh`
  drives the interruption matrix F1–F26 of the v0.5 design through a
  reference host (`tests/harness/ref-host`) and a fake worker
  (`tests/harness/fake-executor`). The host can be killed at named points,
  and the worker journals its writes and its lifetime. After every scenario
  the suite checks for false acceptance and overlapping writers, validates
  the receipts and checks the recovery classes. A mutation check reruns
  claim-dependent scenarios against a helper whose writer claim is stubbed
  out and requires them to fail. Test-only; never shipped.

### Changed

- `passdown-dispatch` runs delegated work through the v0.5 attempt protocol
  (PDN-0004, slice S4):
  - Routing is a ladder: current session → explicitly authorized native
    subagent → external executor with a recorded reason code. The
    "cheapest executor" objective is gone; `executors:` lists what is
    available, and its order is no longer a cost ranking.
  - A delegated attempt follows 17 named steps through the bundled
    `passdown-attempt` helper: the receipt, the writer claim when the
    attempt needs one, and the prompt are on disk before the worker is
    launched; the worker ends
    with a `passdown.result/v1` JSON object; only safe stop evidence ends an
    attempt; the verdict is persisted before the plan is ticked, and the
    `Dispatched:` line names the attempt (`; attempt: <id>`).
  - A new Reconcile section tells the host how to resolve each recovery
    class (C1–C11) in the open. Silence is no longer failure, and nothing
    uncertain is retried.
  - An isolation policy: serial by default, a fresh worktree per attempt
    only when `worktree_dir` is configured and preflight passes, claim-free
    reads only with a card-verified mutation guard, and no host edits in a
    location another attempt's claim holds.
  - Executor mechanics move out of the skill into executor cards
    (`references/executors/`); the inline invocation table is gone. An
    executor without a usable card is not eligible for delegation, and
    delegated dispatch is refused without `jq`. Ineligible is not "the host
    does it": a task whose owner-mandated executor is ineligible stays
    pending and is reported, unless the owner's policy names a fallback
    (#19).
  - A delegated line counts as accepted only if it binds to an accepted
    receipt for the exact task, is a host (`main`) line, or is a legacy line
    for a task with no receipts at all. One plan task per attempt.
  - The host runs every verification command a task names, and
    `passdown-attempt verdict accept` refuses unless every `--check` passed
    (it used to need only one passing check). C6 recovery completes a
    half-written projection (outcome line written, box not yet ticked).
  - `templates/plan.md` and `templates/AGENTS.thin.md` document the attempt
    reference and the new optional keys `attempt_dir`, `worktree_dir`,
    `executor_refs` and `concurrency_profiles`.
- `passdown-pickup` and `passdown-handoff` recover interrupted dispatches
  (PDN-0004, slice S5):
  - Pickup reads the attempt store read-only (`list --unresolved`,
    `claims`, `probe`). It classifies every unresolved attempt C1–C11 with
    its ownership risk and one proposed action, carried out later through
    dispatch *Reconcile*, and reports a handoff attempt missing from the
    store. It never writes a receipt, claim, plan or log.
  - Pickup's completion check follows the dispatch rule: a task with an
    unresolved attempt is never accepted, the latest `Dispatched:` line
    decides, and a legacy line counts only for a task with no receipts.
  - Handoff lists unresolved attempts in a new optional `open_attempts`
    frontmatter key and names them in Caveats / traps. It never resolves
    an attempt and never ticks a task that has one.
  - Handoff carries forward every ID from the previous handoff's
    `open_attempts` until its receipt shows it resolved; an ID whose receipt
    is missing stays listed (`# receipt missing`) until the owner confirms
    no worker remains. `passdown-attempt list` warns when the store is
    absent ("absent, not empty") and reports `idle_seconds` since the last
    receipt transition, which pickup uses for C9.
  - A missing `jq` is reported as "attempt store not readable" instead of
    guessed around. The example workspace gains a handoff with an open
    attempt, and `docs/SMOKE_TEST.md` covers both skills against a live
    attempt.
- Executor cards (PDN-0004, slice S6):
  - `passdown-attempt validate --file <card> --as card` checks a card's
    format, the evidence behind every measured value, and what a launch
    needs. `tests/skills.sh` runs it on every shipped card.
  - Measured cards for `kiro-cli` 2.24.0, Claude Code 2.1.193 (executor
    and card name `claude-code`: a `claude.md` file is `CLAUDE.md` on
    case-insensitive file systems) and codex-cli 0.157.0. Each is based on runs through the real attempt
    lifecycle, recorded in `docs/evidence/e-kiro-1/`, `e-claude-1/` and
    `e-codex-1/` with a shared fixture and runner. All three support
    headless structured output, session resume and a read-only mode, and
    end their tree on `SIGINT` to the process group. None can enforce
    passdown's result schema natively. Claude Code and Codex run tool
    shells in separate process groups that survive `SIGKILL` and keep
    writing, so an empty process group is never a safe stop for them;
    every attempt on the three executors ends with owner attestation
    unless it ran in a containment scope. Only Codex has a measured
    read-only mode that does not depend on inherited configuration
    (`--sandbox read-only --ignore-user-config`), so only Codex reads can
    skip the writer claim, and only through that read-only mode: no card
    marks `sandbox_confined_writes` verified.
  - The measurements found that a worker follows a hand-written
    description of the result schema exactly, mistakes included. The
    dispatch skill now puts the schema itself into the prompt.
  - `docs/EXECUTOR_SETUP.md` is now the guide to measuring and writing a
    card. The executor README drops the invocation hints now covered by
    cards; only `agy` remains, as an unmeasured note.
- The reference host (`tests/harness/ref-host`) prints the skill's step names,
  and a new harness scenario (`tests/interrupt.sh STEPS`) checks that the
  host performs the skill's numbered steps by name and in order. The reference
  host now also takes the settle inspection a card asks for, and F18b uses a
  card that wrongly claims its worker never detaches and releases the late
  write inside that window. For S5, its pickup reads `open_attempts` from a
  handoff log's frontmatter, and a new scenario (`tests/interrupt.sh
  PICKUP`) checks that the helper, the pickup skill and dispatch Reconcile
  use one set of class names, and that pickup changes no file.

### Fixed

- Delegated completion authority (PDN-0003): a delegated worker — external
  CLI or native subagent — can no longer mark canonical plan completion.
  - `passdown-dispatch` gains a completion-authority section. External work
    is assigned by an exact task reference instead of "the next pending
    task", every prompt carries an authority clause forbidding plan-file
    edits, worker edits to checkboxes/`Dispatched:` lines/criteria are
    restored from the baseline only when they are unambiguously the
    worker's (otherwise the host stops and reports the conflict), and only
    the host ticks a task after recording `accepted` in its `Dispatched:`
    line (`rejected` / `failed` leave it `[ ]`).
  - One accepted-verdict rule is shared by dispatch, handoff and pickup:
    `accepted` with a host check, or a pre-existing success line that
    names a host check, so upgrading does not reopen verified tasks.
  - The OpenSpec `passdown` schema's `apply.instruction` now tells an
    assigned worker to implement only its task and not edit `tasks.md`;
    the owning session keeps "mark each task complete as you go".
  - `passdown-handoff` syncs checkboxes to accepted work only: unverified
    delegated work goes back to `[ ]` and is named in Caveats / traps.
  - `passdown-pickup` flags a delegated `[x]` without a host `accepted`
    verdict as inconsistent (or unconfirmed when no `Dispatched:` line
    exists) and briefs it as still pending verification.
  - Current-session (`main`) work is unchanged: host and worker are the
    same actor, so it still marks tasks complete as it goes.
- `tests/openspec-apply.sh` checks the instruction a worker actually
  receives from `openspec instructions apply`; CI runs it against the pinned
  OpenSpec CLI.

### Changed

- `passdown-handoff`: done/total counts quoted in a log must be counted
  from the synced plan file, never recalled from the session.
- `passdown-handoff`: `plan:` frontmatter accepts a YAML list for sessions
  that executed several plans; every path must resolve from the workspace
  root so `passdown-pickup` can open it mechanically.
- `passdown-handoff` / `passdown-pickup`: traps with project lifetime are
  promoted into the repo's durable docs when routing leftovers; the log
  alone keeps only session-scoped traps.

## [0.4.0] - 2026-08-15

### Added

- `passdown-pickup` skill: reads the latest handoff log and plan state,
  verifies them against the working tree, and briefs the next session —
  closing the shift-handover loop.
- Machine-readable YAML frontmatter (`status`, `branch`, `agent`, `plan`) at
  the top of every handoff log, plus a defined agent-identity convention.
- `scripts/doctor.sh`: reports install-channel hygiene per host — dual
  plugin/direct installs and direct installs that drifted from the checkout —
  with a regression suite wired into CI.

### Changed

- `passdown-dispatch` now materializes routing decisions as `[dispatch: ...]`
  tags in the plan file and records a `Dispatched:` outcome line under each
  task executed off the main session.

### Fixed

- Restore the 0.1.0 changelog entries and version link references dropped by
  the v0.3.0 release commit.
- The documentation contract tests now require a link reference for every
  CHANGELOG version heading, and `check-version.sh` requires a CHANGELOG
  section for the current version.

## [0.3.0] - 2026-07-13

### Added

- Standalone markdown planning template with Passdown dispatch tags, done
  criteria, and verification fields.
- Optional `--skills-only` direct-install mode for users who do not use
  OpenSpec.
- Integration guidance for standalone Passdown, OpenSpec, Superpowers, and the
  combined workflow.

### Changed

- Made `passdown-dispatch` an explicit pre-execution gate for multi-task plans,
  including plans about to enter Superpowers `executing-plans`.
- Added a consumer workspace invariant requiring routing before implementation.
- Defined `planning: markdown` with a `plan_dir` key in `passdown-intake`, so
  standalone plans are created from the markdown template without OpenSpec.
- Documented the dispatch gate, optional integrations, standalone markdown
  planning, and `--skills-only` in the README and smoke-test checklist.

### Fixed

- Prevent plan executors from bypassing Passdown routing merely because another
  plugin entered its own execution skill first.
- Reject combining `--into` with `--host` or `--skills-only` in any argument
  order instead of silently installing the schema and dropping the other flags.

## [0.2.0] - 2026-07-09

### Added

- First-class Codex host support with a native `.codex-plugin` manifest and
  repo marketplace.
- Installer, skill-contract, version, and release-workflow regression suites.
- A single `VERSION` source of truth with manifest/tag agreement checks.
- Tag-gated GitHub Release automation.
- Executor environment preflight and setup guidance.

### Changed

- Made intake, dispatch, and handoff configuration inherit root-to-nearest
  `AGENTS.md` values with nearest-key precedence.
- Made dispatch host-aware: Codex is an external executor only from another
  host, while native subagents use the portable `subagent` name.
- Made executor results concise structured summaries, preserving verbatim
  environment errors rather than relaying all output.
- Made direct installs explicit per host and recursive for skill resources.
- Adopted short-lived branches, protected `main`, and PR-only integration.
- Expanded the public documentation, examples, smoke tests, and release gates.

### Fixed

- Preserve pre-existing working-tree changes when an executor fails; cleanup is
  limited to changes attributable to that dispatch.
- Stop cross-repo intake when permissions are insufficient instead of
  attempting sandbox workarounds.
- Remove stale files during direct skill synchronization.
- Reject unknown installer arguments and make `--help` side-effect free.
- Avoid handoff log collisions with agent/time filename suffixes.
- Keep optional OpenSpec design artifacts from blocking task generation.

## [0.1.0] - 2026-07-05

Initial dogfooding snapshot.

### Added

- Three workspace-agnostic skills: intake, dispatch, and handoff.
- Claude Code plugin and marketplace manifests.
- User-level skill installer and thin consumer `AGENTS.md` template.
- OpenSpec `passdown` schema with self-contained task metadata and dispatch
  tags.

[Unreleased]: https://github.com/vunm-io/passdown/compare/v0.4.0...HEAD
[0.5.0-beta.1]: https://github.com/vunm-io/passdown/compare/v0.4.0...release/v0.5.0
[0.4.0]: https://github.com/vunm-io/passdown/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/vunm-io/passdown/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/vunm-io/passdown/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/vunm-io/passdown/releases/tag/v0.1.0
