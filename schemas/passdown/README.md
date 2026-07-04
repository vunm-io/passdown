# passdown OpenSpec schema

Custom OpenSpec workflow schema, forked from the built-in `spec-driven` schema
(openspec CLI **1.5.0**) via `openspec schema fork spec-driven passdown`.

`install.sh` links this directory to `~/.local/share/openspec/schemas/passdown`
so every repo can use it (`schema: passdown` in `.openspec.yaml`, or per-change
selection). A repo can still override it with its own `openspec/schemas/`.

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
