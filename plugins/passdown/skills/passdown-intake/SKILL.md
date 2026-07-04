---
name: passdown-intake
description: Use when processing captured notes/ideas from an inbox into actionable work — scans inbox notes, clarifies intent with the user, routes each note to its target repo, creates a planning artifact (e.g. an OpenSpec change), and marks the note processed
---

# Passdown Intake

Turn raw captured notes into properly planned work. Weak capture tools (chat
apps, quick notes) only need to drop a markdown file into an inbox; this skill
is where a capable agent applies judgment.

## Configuration (read first)

Find the nearest `AGENTS.md` walking up from the current directory. Look for a
`## passdown` section:

```markdown
## passdown
- inbox: <path to inbox directory>
- planning: openspec | <other convention>
- targets: <repo1>, <repo2>, ...   # known target repos for routing
```

If no configuration exists, ask the user where the inbox lives and suggest
adding the section to AGENTS.md.

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
   - Decide the disposition:
     - **Actionable work** → determine the target repo (use `target:` hint,
       the routing rules in AGENTS.md, or ask). Create the planning artifact
       in the target repo using the workspace's planning convention (for
       `planning: openspec`, run `/opsx:propose` or `openspec new change` in
       that repo). The artifact must be self-contained: an executor must be
       able to work from it without reading this conversation.
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
- A discussion note is not an implementation request. Intake produces
  *plans*, never code changes.
- Do not batch-guess: when a note's disposition is ambiguous, ask.
