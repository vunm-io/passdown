---
name: passdown-intake
description: Use when processing captured notes/ideas from an inbox into actionable work — scans inbox notes, clarifies intent with the user, routes each note to its target repo, creates a planning artifact (e.g. an OpenSpec change), and marks the note processed
---

# Passdown Intake

Turn raw captured notes into properly planned work. Weak capture tools (chat
apps, quick notes) only need to drop a markdown file into an inbox; this skill
is where a capable agent applies judgment.

## Configuration (read first)

Build the effective passdown configuration root-to-nearest:

1. Start with every applicable `AGENTS.md` from the workspace/repository root
   down to the current directory.
2. If a thin `AGENTS.md` explicitly points to a parent file outside the Git
   root, read that parent too.
3. Merge `## passdown` keys from root to nearest; a nearer value overrides only
   the same key and inherits all omitted keys.
4. Resolve relative config paths against the directory containing the
   `AGENTS.md` that declared that value, not against an arbitrary current
   directory.

The effective configuration should contain:

```markdown
## passdown
- inbox: <path to inbox directory>
- planning: markdown | openspec
- plan_dir: <path for markdown plans>   # required when planning: markdown
- targets: <repo1>, <repo2>, ...   # known target repos for routing
```

If a required key is still missing, ask the user for that value and suggest
adding it to the appropriate `AGENTS.md`.

## Inbox note contract

Notes are markdown files with minimal frontmatter. Never demand more structure
from capture tools than this:

```markdown
---
status: new          # new | processed | discarded
target: unknown      # target repo if the author could guess it
---
# <idea / thing to do>
<free-form content>
```

A malformed note is still a valid note — it is raw material, not an artifact.

## Process

1. **Scan** the inbox for notes with `status: new` (treat missing frontmatter
   as `new`). List them briefly for the user.
2. **For each note**, in order:
   - Read it fully. Cross-check existing knowledge/specs in the workspace if
     relevant.
   - If intent is unclear, ask the user — one question at a time.
   - Before writing, resolve the inbox, target repo, planning directory, and
     schema paths. Verify that the current host has read access to inputs and
     write access to every intended output. Cross-repo work often needs the
     parent workspace opened as a workspace root or an explicit permission
     grant.
   - If sandbox, permission, or network policy blocks a required path, stop and
     report the blocked path and operation. Do not redirect `HOME`, create
     substitute caches, or edit project/tool configuration as a workaround.
   - Decide the disposition:
     - **Actionable work** → determine the target repo (use `target:` hint,
       the routing rules in AGENTS.md, or ask). Create the planning artifact
       in the target repo using the workspace's planning convention. For
       `planning: markdown`, create a plan file in the target repo's
       `plan_dir` following the structure of passdown's `templates/plan.md`:
       every task carries a `[dispatch: external-ok]` or `[dispatch: main]`
       tag plus Paths, Done criteria, and Verification. For
       `planning: openspec`, use the portable `openspec new change` CLI path;
       a host-specific command such as `/opsx:propose` may be used only when
       that host actually provides it. Either way the artifact must be
       self-contained: an executor must be able to work from it without
       reading this conversation.
     - **Knowledge, not work** → refile into the workspace's knowledge
       location per its conventions.
     - **Obsolete/noise** → mark `status: discarded` after confirming with
       the user.
3. **Close the loop**: update the note's frontmatter to `status: processed`
   and append a link to the created change/refiled location. The note stays
   where it is — it becomes the permanent record of where the idea came from.

## Rules

- The inbox repo stores material and provenance; it never hosts task
  execution. Planning artifacts always live in the target repo.
- Custom OpenSpec schemas (e.g. `openspec new change --schema passdown`) must
  exist as a **real directory** — `openspec/schemas/<name>/` in the target
  repo, or user-level `~/.local/share/openspec/schemas/<name>/`. Symlinked
  schema directories fail with "Unknown schema" (openspec CLI 1.5.0). If the
  schema is missing and the target repo is writable, prefer the repo-local
  copy from its source repo before creating the change (for passdown:
  `install.sh --into <target-repo>`). A user-level install writes outside the
  project and may require explicit approval.
- A discussion note is not an implementation request. Intake produces
  *plans*, never code changes.
- Do not batch-guess: when a note's disposition is ambiguous, ask.
