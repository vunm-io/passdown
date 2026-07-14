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
export HOME="$(mktemp -d)"
./install.sh --host claude
./install.sh --host codex
./install.sh --host kiro
```

- [ ] Each selected host contains all four real skill directories under
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
- [ ] The four skills appear in the skill list under the `passdown` plugin
      namespace — `passdown:passdown-intake`, `passdown:passdown-dispatch`,
      `passdown:passdown-handoff`, `passdown:passdown-pickup` — and are
      invocable as `/passdown:passdown-intake` etc.
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
- [ ] A new Codex thread lists all four namespaced skills
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
      `docs/log/YYYY-MM-DD_<topic>_<agent>-HHMMSS.md` starting with
      `status`/`branch`/`agent`/`plan` frontmatter; repeat with the same
      topic and confirm it creates another file rather than overwriting
- [ ] **passdown-pickup**: in `examples/basic-workspace/`, run pickup and
      confirm it reads the newest log's frontmatter, cross-checks
      `openspec/changes/pkg-0001-demo/tasks.md`, and produces a briefing
      without starting execution

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

## 7. Integration matrix (see docs/INTEGRATIONS.md)

Run these in a Claude Code session against a scratch workspace whose
`AGENTS.md` contains the dispatch invariant from `templates/AGENTS.thin.md`.

### 7a. Passdown only (no OpenSpec, no Superpowers)

```bash
export HOME="$(mktemp -d)"
./install.sh --host claude --skills-only
```

- [ ] All four skills install; nothing exists under
      `~/.local/share/openspec/`
- [ ] With `planning: markdown` and a `plan_dir` configured, intake creates a
      plan file shaped like `templates/plan.md` (dispatch tags, Paths, Done
      criteria, Verification) instead of an OpenSpec change
- [ ] `passdown-dispatch` reads the markdown plan's `[dispatch: ...]` tags and
      proposes routing without any OpenSpec CLI present

### 7b. Passdown + OpenSpec

- [ ] Steps 1–2 and 6 above pass (schema installs, resolves, validates)
- [ ] Intake with `planning: openspec` creates a change via
      `openspec new change --schema passdown`
- [ ] Dispatch reads `tasks.md` dispatch tags as in step 5

### 7c. Passdown + Superpowers

- [ ] Give the session a plan with three or more pending tasks and ask it to
      execute; confirm `passdown-dispatch` runs **before** Superpowers
      `executing-plans` starts implementing (per-task routing decisions are
      stated first)
- [ ] Superpowers must not begin inline or subagent execution with no routing
      decision recorded — if it does, the dispatch gate has regressed
- [ ] Routing every task to `main` is a valid gate outcome; execution then
      proceeds in-session
- [ ] A single clearly scoped task requested directly does not trigger the
      gate
- [ ] An explicit user request to stay in the main session is honored (tasks
      route to `main`; the gate is not silently skipped)

### 7d. Passdown + OpenSpec + Superpowers

- [ ] Full flow: OpenSpec change → Superpowers planning discipline →
      `passdown-dispatch` routing → execution → verification →
      `passdown-handoff`
- [ ] Native subagents are used only with explicit user authorization even
      when Superpowers proposes subagent-driven execution
