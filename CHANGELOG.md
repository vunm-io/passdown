# Changelog

All notable changes to passdown are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-06

First public beta. Distributed as a GitHub-hosted Claude Code plugin
marketplace (`vunm-io/passdown`).

### Added

- Three workspace-agnostic Claude Code / Kiro skills:
  - `passdown-intake` — turn raw inbox notes into planned work in the right repo.
  - `passdown-dispatch` — route each task to the cheapest capable executor and
    verify results.
  - `passdown-handoff` — end a session with a small handoff log.
- OpenSpec workflow schema (`schemas/passdown/`) that makes tasks
  self-contained and dispatchable, with proposal/design/spec/task templates.
- `install.sh` user-level installer (skills + OpenSpec schema) with an
  `--into <repo>` mode to vendor the schema into a target repo.
- Claude Code plugin marketplace manifest (`.claude-plugin/marketplace.json`)
  and plugin manifest (`plugins/passdown/.claude-plugin/plugin.json`), with
  public-facing metadata (displayName, homepage, repository, license,
  keywords, category).
- `scripts/validate-plugin.sh` and a CI step running
  `claude plugin validate --strict` on both manifests.
- `examples/basic-workspace/` worked example (inbox note, completed OpenSpec
  change, session log) and `docs/SMOKE_TEST.md` manual verification checklist.
- CI (`.github/workflows/ci.yml`): JSON validation, shellcheck, strict plugin
  validation, OpenSpec schema validation, and a schema-sync check.

[Unreleased]: https://github.com/vunm-io/passdown/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/vunm-io/passdown/releases/tag/v0.1.0
