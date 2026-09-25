# E-CODEX-1 — Codex CLI measured through the v0.5 lifecycle

The E-KIRO-1 method (§19 of `docs/design/PDN-0004-v05-acceptance-recovery.md`,
[`../e-kiro-1/`](../e-kiro-1/)) applied to `codex exec`. Result: the card at
`plugins/passdown/skills/passdown-dispatch/references/executors/codex.md`.

| | |
|---|---|
| Date | 2026-09-25 |
| codex | codex-cli 0.157.0 (standalone install; the model is not reported in `--json` output) |
| Host | macOS 26.6.2, `/bin/bash` 3.2 |
| Operator | Claude (passdown maintainer session), attesting stops from the recorded process listings |
| Fixture | [`../fixture.sh`](../fixture.sh): the same four-task plan as E-KIRO-1 |
| Runner | [`../executor-run.sh`](../executor-run.sh) with `EK_EXECUTOR=codex` |
| Records | [`runs/`](runs/), local paths replaced by placeholders |

Before the update, codex-cli 0.142.5 could not run at all: the default model
answered "requires a newer version of Codex". The card is for 0.157.0.

## Runs

| Run | Task | Setup | Outcome |
|---|---|---|---|
| [A](runs/A.md) | 2.1 read | no flags | Exit 0; valid `submitted`; accepted. |
| [B0](runs/B0.md) | 1.1 write | no flags | The default sandbox is **read-only, enforced by the OS**: `zsh:1: operation not permitted: src/greeting.txt`. The worker returned `blocked` with the error verbatim. |
| [B](runs/B.md) | 1.1, continuation of B0 | `--sandbox workspace-write` | One path written, in scope; accepted. |
| [C](runs/C.md) | 3.1 ambiguous | `workspace-write` | `needs_input`; no write. |
| [D](runs/D.md) | 3.1, continuation of C | `codex exec resume … -c sandbox_mode=workspace-write <thread_id>`, prompt **without the task text** | Same thread, new attempt; rename made and verified; accepted. |
| [E1-early](runs/E1-early.md) | 4.1 slow counter | `SIGINT` after 25 s | Codex was still starting up (reading skills and plugins); the signal arrived before any write. Exit 1, nothing survived. |
| [E1](runs/E1.md) | 4.1 | `SIGINT` 8 s after `src/count.txt` appeared | Exit 1, no result; the tool shells ran in **their own process groups** (18 descendants outside the launch group), and all of them ended; 9 lines written. |
| [E2](runs/E2.md) | 4.1 | `SIGKILL` 8 s after `src/count.txt` appeared | Exit 137. The launch group was empty, yet **the tool shell (its own process group) survived and kept writing**: 11 → 28 lines, until the operator killed it. The runner did not attest; the attempt stayed `unknown`. |
| [S](runs/S.md) | 2.1 read | `--output-schema <result.v1 schema>` | The API rejected the schema (`invalid_json_schema`: "In context=('not',), schema must have a 'type' key"); `turn.failed`, exit 1. |
| R (`R.transport.jsonl`) | outside the lifecycle | `--sandbox read-only --ignore-user-config`; asked to count lines, then to create a file with any tool | Count correct; the shell write failed with `operation not permitted`; no plugin or MCP activity. |
| R2 (`R2.transport.jsonl`) | outside the lifecycle | same; asked to create a file with `apply_patch`, not the shell | "patch rejected: writing is blocked by read-only sandbox". Nothing written. |
| W (`W.transport.jsonl`) | outside the lifecycle | `--sandbox workspace-write`, asked to write a file in the home directory | `operation not permitted`; nothing written outside the workspace. |

## What the runs establish

- **Headless and structured output.** `codex exec --json` writes JSON Lines:
  `thread.started` (with `thread_id`), `item.completed` items
  (`command_execution`, `file_change`, `agent_message`), and
  `turn.completed` or `turn.failed`. Extraction rule: the text of the last
  `agent_message` item, then its last line that is a JSON object; no
  `turn.completed` means no result.
- **Close stdin.** `codex exec` reads extra input from stdin ("Reading
  additional input from stdin..."); a backgrounded worker must get
  `</dev/null`.
- **Exit code.** 0 for completed turns whatever the disposition; 1 after
  `SIGINT` or a failed turn; 137 after `SIGKILL`.
- **Read-only mode and sandbox.** The default sandbox is read-only and
  OS-enforced, for the shell (B0, R) and for `apply_patch` (R2). A read-only
  mode that does not depend on inherited configuration is `--sandbox
  read-only --ignore-user-config`: without the second flag the user's MCP
  servers and plugins load, outside the sandbox (R showed no such activity
  with it). `--sandbox workspace-write` allows writes in the workspace and
  refused a write in the home directory (W). Writes to `/tmp` or `$TMPDIR`
  were not measured.
- **Resume.** `codex exec resume <thread_id>` continues the thread (D). The
  `resume` subcommand has no `--sandbox` option; pass
  `-c sandbox_mode=<mode>`.
- **Cancel.** `SIGINT` to the launch process group ends the tool process
  groups too (E1).
- **Descendants outlive the parent.** Tool shells run in their own process
  groups and survive `SIGKILL` of codex, still writing (E2).
  `descendants_may_outlive` is **verified**.
- **`--output-schema` cannot carry passdown's result schema.** The API
  accepts only a stricter subset of JSON Schema (S).
- **User environment loads.** Codex read the operator's installed skills and
  refreshed plugin marketplaces (`git ls-remote`) during runs, and took about
  25 s to start writing.


## How stops were attested

The runner that produced these records ([`../executor-run.sh`](../executor-run.sh) as it was then) recorded `owner-attested`
**by itself** whenever the launch process group was empty and its own scans
found no surviving descendant and no new codex process. It asked no person.
Those scans sample every 0.3 s and match process names, so they can miss a
process that detaches and exits quickly. That is fine for measuring what
the CLI does, but it is **not** the attestation the dispatch skill requires
(steps 10–11: a person confirms, and the host never attests on their
behalf). The `accepted` verdicts in these fixtures are measurement
artifacts, not examples of protocol-compliant acceptance.
In E2 the scans did see the survivor, and the runner left the attempt
`unknown`; the operator killed it before attesting.
The runner was changed after review
([#21](https://github.com/vunm-io/passdown/pull/21)):
[`../executor-run.sh`](../executor-run.sh) now stops at `unknown` and needs
`--finish <part> --attested-by <who>` from the operator before it records a
stop.

## Not measured

`TERM`; `danger-full-access`; writes to `/tmp`; resume from another
directory; a containment scope.
