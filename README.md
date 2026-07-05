# passdown

> Shift-handover workflow for AI agents. Like a passdown log between work
> shifts: one session (or agent) writes down the state, the next one picks it
> up — cheaply, from small files, with any tool.

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

## How it works

passdown is three **workspace-agnostic skills** installed at user level, plus
conventions. Skills are the engine; each workspace's `AGENTS.md` is the config
(a `## passdown` section declares inbox/log locations, language, and available
executors). Nothing workspace-specific ever lives inside a skill — which is
also why the skills survive any `cwd` and any repo.

| Skill | What it does |
|---|---|
| `passdown-intake` | Turns raw notes from an inbox (dropped there by weak capture tools like chat apps) into properly planned work in the right repo |
| `passdown-dispatch` | Routes each task to the cheapest capable executor — external CLI agents, subagents, or the main session — and verifies results |
| `passdown-handoff` | Ends every session with a small handoff log: summary, next steps, and the traps that live nowhere else |

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

**For other tools (Kiro, or any agent that reads user-level skill dirs):**

```bash
git clone git@github.com:vunm-io/passdown.git && cd passdown
./install.sh   # copies skills for Claude Code, symlinks for Kiro, links the OpenSpec schema
```

Pick ONE channel per tool — installing both the plugin and the script copies
into `~/.claude/skills` loads every skill twice. Note that Claude Code's
desktop skill browser only lists plugin-delivered and app-managed skills;
script-installed skills still work in every session, they just don't appear
in that panel.

Then add a `## passdown` section to your workspace's `AGENTS.md` (see
`templates/AGENTS.thin.md` for a starting point).

## Layout

```
plugins/passdown/skills/   # the three skills (English, workspace-agnostic)
schemas/passdown/          # OpenSpec workflow schema customizations
templates/AGENTS.thin.md   # thin AGENTS.md template for sub-repos
install.sh                 # user-level symlink installer
```

## License

MIT
