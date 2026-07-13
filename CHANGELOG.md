# Changelog

All notable changes to passdown are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
