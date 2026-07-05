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

- `main` only. No `develop`, no long-lived feature branches.
- Linear history: no merge commits, squash/fixup before pushing.
- Never force-push `main`.
- One commit = one logical change. Conventional Commits, English, imperative
  mood (`fix: ...`, `feat: ...`, `ci: ...`, `docs: ...`).

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
3. **JSON edits** (`.claude-plugin/marketplace.json`, `plugins/passdown/.claude-plugin/plugin.json`):
   ```bash
   jq empty .claude-plugin/marketplace.json
   jq empty plugins/passdown/.claude-plugin/plugin.json
   ```
4. **Skill edits** (`plugins/passdown/skills/*`): re-run `./install.sh` to
   sync `~/.claude/skills/` before testing the skill live in a session.

CI (`.github/workflows/ci.yml`) runs all of the above except step 4 on every
push/PR — treat a red run the same as a failing test suite, not advisory.

## Release rule

A release is: bump `version` in **both** `.claude-plugin/marketplace.json`
(top-level `metadata.version` and the `passdown` plugin's `version`) **and**
`plugins/passdown/.claude-plugin/plugin.json` to the same value, then tag:

```bash
git tag -a v0.2.0 -m "v0.2.0"
git push origin v0.2.0
```

Keep the two JSON files' versions in sync — the plugin loader reads
`plugin.json`, the marketplace listing reads `marketplace.json`, and a
mismatch is confusing for anyone diffing releases.

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
