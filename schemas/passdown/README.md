# passdown OpenSpec schema

Custom OpenSpec workflow schema, forked from the built-in `spec-driven` schema
(openspec CLI **1.5.0**) via `openspec schema fork spec-driven passdown`.

## Installing the schema

The openspec CLI (1.5.0) only loads schemas that are **real directories**:
`openspec new change --schema passdown`, `openspec status`, and
`openspec instructions apply` all fail with "Unknown schema 'passdown'" when
the schema directory is a symlink — user-level or project-local — even though
`openspec schema which passdown` resolves symlinks fine. So install a copy,
one (or both) of:

- **User-level** — `./install.sh` copies this directory to
  `~/.local/share/openspec/schemas/passdown`, making `schema: passdown`
  available in every repo on this machine. Re-run after editing the schema.
- **Per-repo** — copy it into the target repo so the repo is self-contained
  (collaborators and CI get the schema without installing passdown):

  ```bash
  ./install.sh --into <repo>
  # equivalent to: cp -R schemas/passdown <repo>/openspec/schemas/passdown
  ```

A repo-local copy takes precedence over the user-level one. As of 2026-07-05,
1.5.0 is the latest published openspec release, so no released version fixes
the symlink limitation — re-test it when bumping the pinned CLI version.

## Customizations on top of spec-driven

All changes live in the `tasks` artifact instruction (see "Passdown additions"
in `schema.yaml`):

1. **Self-contained tasks** — every task names the file paths to touch and
   explicit done criteria, so an external executor (another CLI agent or a
   fresh session) can complete it without conversation history.
2. **Dispatch tags** — mechanical tasks are marked `[dispatch: external-ok]`,
   judgment-heavy ones `[dispatch: main]`; the passdown-dispatch skill routes
   on these.
3. **Task ID conventions** — workspaces using task IDs (e.g. `PKG-0005`) embed
   them in change names and commit scopes.

## Upgrading

When bumping the openspec CLI, re-fork and re-apply the customizations:

```bash
openspec schema fork spec-driven passdown --force   # in a scratch dir
# diff against this directory, port upstream changes, keep the Passdown additions
openspec schema validate passdown
```
