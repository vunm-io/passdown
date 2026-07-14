# Changelog

All notable changes to passdown are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0-beta.2] - 2026-07-14

Beta build for the `release/v0.4.0` testing window — not a GitHub release.

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

- Added the missing `0.4.0-beta.1` link reference; the documentation contract
  tests now require a link reference for every CHANGELOG version heading, and
  `check-version.sh` requires a CHANGELOG section for the current version.

## [0.4.0-beta.1] - 2026-07-13

Beta build for the `release/v0.4.0` testing window — not a GitHub release.

### Fixed

- Restore the 0.1.0 changelog entries and version link references dropped by
  the v0.3.0 release commit.

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

[Unreleased]: https://github.com/vunm-io/passdown/compare/v0.3.0...HEAD
[0.4.0-beta.2]: https://github.com/vunm-io/passdown/compare/v0.3.0...release/v0.4.0
[0.4.0-beta.1]: https://github.com/vunm-io/passdown/compare/v0.3.0...release/v0.4.0
[0.3.0]: https://github.com/vunm-io/passdown/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/vunm-io/passdown/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/vunm-io/passdown/releases/tag/v0.1.0
