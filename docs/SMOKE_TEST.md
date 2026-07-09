# Smoke test

Manual checklist for verifying an install actually works, end to end. Run
this after any change to `install.sh`, either plugin manifest/marketplace, the
skills, or `schemas/passdown/`.

## 0. Manifest validation (also runs in CI)

```bash
./scripts/validate-plugin.sh
```

On Windows (PowerShell): `.\scripts\validate-plugin.ps1` (avoids Git
Bash/WSL path conversion issues with the `.sh` version).

- [ ] Both `claude plugin validate ... --strict` checks (marketplace + plugin)
      print `✔ Validation passed`
- [ ] Exit code is 0 (`--strict` fails on unrecognized fields / missing
      metadata, so a green run means the manifests are marketplace-clean)

## 1. Direct script install (host-selected + OpenSpec)

```bash
home="$(mktemp -d)"
HOME="$home" ./install.sh --host claude
HOME="$home" ./install.sh --host codex
HOME="$home" ./install.sh --host kiro
```

- [ ] Each selected host contains all three real skill directories under
      `.claude/skills`, `.agents/skills`, or `.kiro/skills`
- [ ] Running `./tests/install.sh` confirms `--help` is side-effect free,
      unknown args fail, nested resources copy, and stale files are removed
- [ ] `openspec schema which passdown` resolves to
      `~/.local/share/openspec/schemas/passdown`, `Source: user`
- [ ] `openspec schema validate passdown` prints `✓ Schema 'passdown' is valid`

## 2. Per-repo install (self-contained, no passdown clone needed later)

```bash
scratch="$(mktemp -d)"
./install.sh --into "$scratch"
```

- [ ] `ls "$scratch/openspec/schemas/passdown"` shows `schema.yaml`,
      `README.md`, `templates/`
- [ ] Inside `$scratch`: `openspec schema which passdown` reports
      `Source: project`, and shadows the user-level copy if both exist

## 3. Claude Code plugin channel

```bash
claude plugin marketplace add vunm-io/passdown
claude plugin install passdown@passdown
```

- [ ] Plugin shows up under Personal plugins in the desktop app / `/plugin`
- [ ] The three skills appear in the skill list under the `passdown` plugin
      namespace — `passdown:passdown-intake`, `passdown:passdown-dispatch`,
      `passdown:passdown-handoff` — and are invocable as
      `/passdown:passdown-intake` etc.
- [ ] They appear **without** also running `./install.sh` (installing both
      channels double-loads skills — pick one per tool, see README)
- [ ] Restart the app/session, then confirm each skill triggers on its
      description (see step 4)

## 4. Codex plugin channel

Use an isolated Codex home so an existing direct install cannot mask results:

```bash
CODEX_HOME="$(mktemp -d)"
export CODEX_HOME
codex plugin marketplace add "$(pwd)"
codex plugin add passdown@passdown
codex plugin list
```

- [ ] `passdown@passdown` is `installed, enabled` at the version in `VERSION`
- [ ] A new Codex thread lists all three namespaced skills
- [ ] No unnamespaced `passdown-*` duplicate exists in `$HOME/.agents/skills`
- [ ] When Codex is the host, a configured `codex` executor is skipped as a
      self-target; `main` or an explicitly requested native subagent is used

## 5. Exercise each skill once

Use `examples/basic-workspace/` as the fixture — it already has a
processed inbox note, a completed OpenSpec change under the `passdown`
schema, and a session log, so you can diff behavior instead of guessing.

- [ ] **passdown-intake**: point it at a *fresh* copy of
      `examples/basic-workspace/docs/inbox/` with a new `status: new` note
      and confirm it proposes a target repo + planning artifact instead of
      writing code
- [ ] **cross-repo permission preflight**: configure the inbox or target
      outside writable workspace roots and confirm intake reports the blocked
      path without redirecting HOME, caches, or config; then grant the proper
      workspace root and retry
- [ ] **passdown-dispatch**: point it at
      `examples/basic-workspace/openspec/changes/pkg-0001-demo/tasks.md` and
      confirm it reads the `[dispatch: external-ok]` / `[dispatch: main]`
      tags and proposes routing accordingly (tasks 1.1/1.2 external, 2.1 main)
- [ ] **passdown-handoff**: end a short session and confirm it writes
      `docs/log/YYYY-MM-DD_<topic>_<agent>-HHMMSS.md`; repeat with the same
      topic and confirm it creates another file rather than overwriting

## 6. OpenSpec schema, from scratch

```bash
mkdir -p /tmp/passdown-smoke && cd /tmp/passdown-smoke
git init -q
/path/to/passdown/install.sh --into .
openspec new change my-test-change --schema passdown --description "smoke test"
openspec status --change my-test-change
```

- [ ] Change name must be lowercase kebab-case — `openspec` rejects
      uppercase/underscore names (this rules out embedding uppercase task
      IDs like `PKG-0005` verbatim; lowercase them: `pkg-0005-...`)
- [ ] `openspec status` shows 4 artifacts (proposal, design, specs, tasks)
      with `tasks` blocked only by `specs` — **not** by `design` (this was
      the bug fixed in schema.yaml; if `tasks` shows blocked by `design`
      again, the fix regressed)
- [ ] Write `proposal.md` + `specs/<cap>/spec.md`, skip `design.md` entirely,
      and confirm `tasks` still unblocks and `openspec status` reports it
      `[x]` once `tasks.md` exists

Clean up: `rm -rf /tmp/passdown-smoke`.
