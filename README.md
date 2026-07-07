# passdown

<p align="center">
  <img src="assets/hero.svg" alt="passdown — shift notes for your AI agents" width="100%">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/status-v0%20dogfooding-orange.svg" alt="Status: v0 dogfooding">
  <img src="https://img.shields.io/badge/skills-3-2dd4bf.svg" alt="3 skills">
  <a href="https://github.com/vunm-io/passdown/actions/workflows/ci.yml"><img src="https://github.com/vunm-io/passdown/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

<p align="center"><strong>Shift notes for your AI agents.</strong></p>

> Like a passdown log between work shifts: one session (or agent) writes down
> the state, the next one picks it up — cheaply, from small files, with any tool.

**Status: v0 — dogfooding.** APIs, file layouts, and skill contents will change.

## Why

Working with AI coding agents across long-running projects has three recurring
problems:

1. **Sessions grow too long.** Context bloats, tokens get expensive, and there
   is no natural stopping point to resume from.
2. **One vendor is not enough.** Heavy work should go to whatever executor is
   cheapest and capable — another CLI agent, a subagent, a different model.
3. **Rules live in the wrong place.** Workspace-level conventions vanish when
   an agent opens a sub-repo, because project-level config follows the
   directory, not the user.

## Strengths

- **Workspace-agnostic** — skills install at user level and survive any `cwd` and sub-repo.
- **Multi-executor** — dispatch routes heavy work to the cheapest capable executor available (Codex, Antigravity, a subagent, or the main session); which executors exist is declared per workspace in `AGENTS.md`.
- **Cheap resume** — the next session reads small handoff files, not a giant transcript.
- **Composes, not replaces** — fits alongside superpowers, OpenSpec, and codex-plugin-cc.
- **Tool-agnostic host** — ships as a Claude Code plugin, plus an `install.sh` for Kiro and other agents that read user-level skill dirs.

## How it works

<p align="center">
  <img src="assets/flow.svg" alt="inbox → intake → dispatch → handoff" width="100%">
</p>

passdown is three **workspace-agnostic skills** installed at user level, plus
conventions. Skills are the engine; each workspace's `AGENTS.md` is the config
(a `## passdown` section declares inbox/log locations, language, and available
executors). Nothing workspace-specific ever lives inside a skill — which is
also why the skills survive any `cwd` and any repo.

| Skill | What it does |
|---|---|
| `passdown-intake` | Turns raw notes from an inbox (dropped there by weak capture tools like chat apps) into properly planned work in the right repo |
| `passdown-dispatch` | Routes each task to the cheapest capable executor — external CLI agents (Codex via `/codex:rescue`, Antigravity via `agy`), subagents, or the main session — and verifies results |
| `passdown-handoff` | Ends every session with a small handoff log: summary, next steps, and the traps that live nowhere else |

**Where it runs vs. what it drives.** passdown *runs* as the orchestrator in
Claude Code (and Kiro, via installed skills). From there, `passdown-dispatch`
*drives* external executors — Codex, Antigravity, subagents — as configured.
Codex and Antigravity are dispatch targets, not places passdown installs into.

passdown composes with, and does not replace:

- [superpowers](https://github.com/obra/superpowers) — process discipline
  (TDD, debugging, planning etiquette)
- [OpenSpec](https://github.com/Fission-AI/openspec) — planning artifacts
  (living specs, change deltas, task lists whose state lives in files, not in
  sessions)
- [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) — the Codex
  executor backend, when available

## Install

**As a Claude Code plugin (recommended):**

```bash
claude plugin marketplace add vunm-io/passdown
claude plugin install passdown@passdown
```

Or in the desktop app: Plugins → Add marketplace → "Add from a repository".
The plugin (and its skills) then shows up under Personal plugins, like any
marketplace plugin.

Once installed, the three skills load under the `passdown` plugin namespace.
They trigger automatically on their descriptions, and you can invoke them
explicitly:

- `/passdown:passdown-intake`
- `/passdown:passdown-dispatch`
- `/passdown:passdown-handoff`

**For other host tools (Kiro, or any agent that reads user-level skill dirs):**

```bash
# HTTPS (recommended for public users):
git clone https://github.com/vunm-io/passdown.git && cd passdown
# or SSH, if you have a key set up (handy for maintainers):
# git clone git@github.com:vunm-io/passdown.git && cd passdown
./install.sh   # copies skills for Claude Code, symlinks for Kiro, copies the OpenSpec schema
```

Pick ONE channel per tool — do not run both the Claude Code plugin install
and `./install.sh`. Installing both copies every skill into `~/.claude/skills`
a second time and double-loads them. Note that Claude Code's desktop skill
browser only lists plugin-delivered and app-managed skills; script-installed
skills still work in every session, they just don't appear in that panel.

Then add a `## passdown` section to your workspace's `AGENTS.md` (see
`templates/AGENTS.thin.md` for a starting point).

## Layout

```
plugins/passdown/skills/   # the three skills (English, workspace-agnostic)
schemas/passdown/          # OpenSpec workflow schema customizations
templates/AGENTS.thin.md   # thin AGENTS.md template for sub-repos
assets/                    # README hero + flow SVGs
install.sh                 # user-level installer (--into <repo> copies the schema into a repo)
examples/basic-workspace/  # a worked example: inbox note, OpenSpec change, session log
docs/SMOKE_TEST.md         # manual verification checklist for install + skills
```

See [`examples/basic-workspace/`](examples/basic-workspace/) for what an
inbox note, a completed `passdown`-schema OpenSpec change, and a session log
actually look like end to end. See [`docs/SMOKE_TEST.md`](docs/SMOKE_TEST.md)
before shipping any change to `install.sh`, the plugin manifests, or the
schema.

## Distribution status

- **GitHub-hosted marketplace** — supported once this repo is public. Install
  with `claude plugin marketplace add vunm-io/passdown` (see [Install](#install)).
- **Community marketplace** — planned, after public validation and a full
  smoke test (`docs/SMOKE_TEST.md`). This is an opt-in listing you submit.
- **Official (Anthropic-curated) marketplace** — curated by Anthropic; there
  is no direct application process, so there is nothing to submit here.

See [`docs/RELEASE.md`](docs/RELEASE.md) for the release + go-public checklist.

## License

MIT
