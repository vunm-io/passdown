# Attempt protocol fixtures

Contract corpus for the v0.5 protocol schemas in `schemas/protocol/`
(design: `docs/design/PDN-0004-v05-acceptance-recovery.md`, sections 6–8 and
10.4). `tests/contracts.sh` runs a pinned JSON Schema validator over it; the
`passdown-attempt` helper (slice S2) must reach the same verdict on every
file.

```text
receipts/  results/  claims/
  valid/              accepted by the schema and by the helper
  invalid/            rejected by the schema (and by the helper)
  semantic-invalid/   accepted by the schema, rejected by the helper only
MANIFEST.tsv          every invalid and semantic-invalid fixture
```

## Three layers

JSON Schema can check one document's fields and the combinations of their
values. It cannot compare two values with each other, look at the executor
card, or look at other files. The corpus therefore has three layers:

| Layer | Rejected by | Examples |
|---|---|---|
| `invalid/` | schema and helper | accepted while `running`; `stopped` with bare `exit` evidence; a rejection without a reason code; a result path with `..` |
| `semantic-invalid/` | helper `validate` / `result` only | `verdict.task_digest ≠ task.digest`; `chain_root ≠ id` on a chain root; `rev` not equal to the last transition; a result whose `attempt` is another attempt |
| helper tests (S2) | helper only, needs more than one file | two receipts holding the same claim key (I-20); `exit+pgroup-empty` on a card that has not measured `descendants_may_outlive: unsupported`; a result payload over 256 KiB |

## Naming and the manifest

Every invalid fixture is a valid fixture of the same kind with **one**
change. `MANIFEST.tsv` records, per file, the valid fixture it was derived
from and the JSON pointer where the schema must report the error. The test
fails if the schema rejects a fixture anywhere else, so a fixture cannot pass
by being broken for an unrelated reason. `-` marks a schema-valid
(`semantic-invalid/`) fixture and `!parse` a file that is not one JSON value.

Result fixtures are named `<diagnostic>--<case>.json`, where `<diagnostic>`
is the code the helper must report (section 7). Receipt fixtures are named
after the rule they break.

Result fixtures are checked against the receipt ID
`pd-20260921T101530Z-3f9a1c2e`, which is the `id` of the receipt fixtures.

## Adding a fixture

1. Copy the closest `valid/` fixture and make exactly one change.
2. Put it in `invalid/` if the schema must reject it, else in
   `semantic-invalid/`.
3. Add a line to `MANIFEST.tsv`: path, source fixture name, JSON pointer (or
   `-`).
4. Run `tests/contracts.sh`.
