# Smoke test

Manual checklist for verifying an install actually works, end to end. Run
this after any change to `install.sh`, `.claude-plugin/*.json`, or
`schemas/passdown/`.

## 0. Manifest validation (also runs in CI)

```bash
./scripts/validate-plugin.sh
```

- [ ] Both `claude plugin validate ... --strict` checks (marketplace + plugin)
      print `✔ Validation passed`
- [ ] Exit code is 0 (`--strict` fails on unrecognized fields / missing
      metadata, so a green run means the manifests are marketplace-clean)

## 1. Script install (Claude Code + Kiro + OpenSpec)

```bash
./install.sh
```

- [ ] Output shows `COPY .../.claude/skills/passdown-{intake,dispatch,handoff}`
- [ ] `ls ~/.claude/skills/ | grep passdown` lists all three, as real
      directories (not symlinks — the desktop skill browser won't list
      symlinked entries)
- [ ] If `~/.kiro` exists: `ls -la ~/.kiro/skills/ | grep passdown` shows
      symlinked entries pointing back into this repo
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

## 4. Exercise each skill once

Use `examples/basic-workspace/` as the fixture — it already has a
processed inbox note, a completed OpenSpec change under the `passdown`
schema, and a session log, so you can diff behavior instead of guessing.

- [ ] **passdown-intake**: point it at a *fresh* copy of
      `examples/basic-workspace/docs/inbox/` with a new `status: new` note
      and confirm it proposes a target repo + planning artifact instead of
      writing code
- [ ] **passdown-dispatch**: point it at
      `examples/basic-workspace/openspec/changes/pkg-0001-demo/tasks.md` and
      confirm it reads the `[dispatch: external-ok]` / `[dispatch: main]`
      tags and proposes routing accordingly (tasks 1.1/1.2 external, 2.1 main)
- [ ] **passdown-handoff**: end a short session and confirm it writes
      `docs/log/YYYY-MM-DD_<topic>.md` — one new file, not an append to
      `2026-07-05_passdown-demo.md`

## 5. OpenSpec schema, from scratch

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
