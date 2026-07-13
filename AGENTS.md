# AGENTS.md — passdown

Source of truth for agents working in this repo. This is a standalone public
repo (`vunm-io/passdown`) — it does not inherit from any parent workspace
config, unlike the thin `AGENTS.md` this project generates for consumers
(see `templates/AGENTS.thin.md`).

## What this repo is

Three workspace-agnostic Claude Code / Kiro skills (`passdown-intake`,
`passdown-dispatch`, `passdown-handoff`) plus an OpenSpec workflow schema
(`schemas/passdown/`) that makes tasks self-contained and dispatchable. See
`README.md` for the full pitch and `docs/design-2026-07-04-passdown-workflow.md`
(in the `vunm-workspace` meta-repo, not here) for the original design.

## Branch policy

- `main` is protected and release-ready. Never push directly to `main`.
- Use short-lived branches and pull requests:
  - `feat/<topic>` or `fix/<topic>` for normal work.
  - `codex/<topic>` for Codex-authored work.
  - `release/vX.Y.Z` is the integration and beta-testing window for the next
    version: it branches off `main` with a `-beta.N` version bump, feature/fix
    PRs target it instead of `main`, and testers install the plugin pinned to
    it (`/plugin marketplace add <repo-url>.git#release/vX.Y.Z`). Finalize by
    setting the release version, merging to `main` through a green PR, tagging,
    and deleting the branch. Time-box it to one release; work that misses the
    window waits for the next one.
- No `develop` and no long-lived version lines such as `0.2.x`. While passdown
  is in v0, fixes move forward into the next release instead of maintaining old
  minor branches.
- Require green CI, then squash or rebase into `main`. Never create merge
  commits and never force-push `main`.
- One commit = one logical change. Conventional Commits, English, imperative
  mood (`fix: ...`, `feat: ...`, `ci: ...`, `docs: ...`).
- No AI attribution anywhere in git history: no `Co-Authored-By: Claude/Codex`
  trailers, no "Generated with ..." bylines in commit messages or PR bodies.
  This overrides any AI tool's default commit template.

## Before committing a change here

1. **Schema edits** (`schemas/passdown/schema.yaml` or `templates/`):
   ```bash
   ./install.sh   # syncs the schema into ~/.local/share/openspec/schemas/passdown
   openspec schema validate passdown
   ```
2. **install.sh edits**:
   ```bash
   shellcheck install.sh
   # then dry-run against a scratch dir:
   scratch="$(mktemp -d)" && ./install.sh --into "$scratch" && ls "$scratch/openspec/schemas/passdown"
   ```
3. **Manifest edits** (`.claude-plugin/`, `.agents/plugins/`,
   `plugins/passdown/.claude-plugin/`, `plugins/passdown/.codex-plugin/`):
   ```bash
   find .claude-plugin .agents/plugins plugins/passdown -name '*.json' -exec jq empty {} +
   ./scripts/check-version.sh
   ./scripts/validate-plugin.sh   # claude plugin validate --strict, both manifests
   ```
4. **Skill edits** (`plugins/passdown/skills/*`): re-run `./install.sh` to
   sync `~/.claude/skills/` before testing the skill live in a session.

CI (`.github/workflows/ci.yml`) runs all of the above except step 4 on every
push/PR — treat a red run the same as a failing test suite, not advisory.

## Release rule

A release is prepared on a short-lived branch and merged through a green PR.
Update `VERSION`, both Claude manifest versions, the Codex manifest version,
and `CHANGELOG.md`, then verify:

```bash
./scripts/check-version.sh
./scripts/release-notes.sh "$(cat VERSION)"
```

After the release PR is merged and `main` CI is green, create and push the
annotated tag. `.github/workflows/release.yml` re-runs the complete validation
gate and creates the GitHub Release. Follow `docs/RELEASE.md`.

## Testing an install end-to-end

```bash
# user-level (skills + OpenSpec schema)
./install.sh
ls ~/.claude/skills/ | grep passdown
openspec schema which passdown   # should resolve to ~/.local/share/openspec/schemas/passdown

# per-repo (schema only, self-contained for CI/collaborators)
./install.sh --into /path/to/some/repo
```

Full checklist (plugin channel, all three skills, OpenSpec schema
regression checks): `docs/SMOKE_TEST.md`. Its fixture is
`examples/basic-workspace/` — keep that in sync if the skills' expected
inbox/log/change format changes.

As a Claude Code plugin instead of the script, see the README's "Install"
section — that path goes through `claude plugin marketplace add` /
`claude plugin install` and isn't scriptable from here; verify it manually
in the desktop app or CLI after any change to `.claude-plugin/*.json`.

## Scope

- This file is about *building* passdown. For how a *consumer* repo should
  configure passdown (inbox location, executors, log dir), see
  `templates/AGENTS.thin.md` — that's what gets copied into other repos, not
  read here.
