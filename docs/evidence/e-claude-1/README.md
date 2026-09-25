# E-CLAUDE-1 — Claude Code CLI measured through the v0.5 lifecycle

The E-KIRO-1 method (§19 of `docs/design/PDN-0004-v05-acceptance-recovery.md`,
[`../e-kiro-1/`](../e-kiro-1/)) applied to `claude -p`. Result: the card at
`plugins/passdown/skills/passdown-dispatch/references/executors/claude-code.md`.

| | |
|---|---|
| Date | 2026-09-25 |
| claude | 2.1.193 (Claude Code); model from the `init` event: `claude-sonnet-4-6` (the CLI default on this machine) |
| Host | macOS 26.6.2, `/bin/bash` 3.2 |
| Operator | Claude (passdown maintainer session, a separate Claude Code desktop session), attesting stops from the recorded process listings |
| Fixture | [`../fixture.sh`](../fixture.sh): the same four-task plan as E-KIRO-1 |
| Runner | [`../executor-run.sh`](../executor-run.sh) with `EK_EXECUTOR=claude` |
| Records | [`runs/`](runs/). Local paths are replaced by placeholders, and the `init` and hook events are reduced so that the operator's tool, MCP server and plugin names are not published |

## Runs

| Run | Task | Setup | Outcome |
|---|---|---|---|
| [A](runs/A.md) | 2.1 read | no permission flags | Exit 0; valid `submitted`; accepted. A read-only shell command (`wc -l`) ran without a prompt. |
| [B0](runs/B0.md) | 1.1 write | no permission flags | `Write` denied; the worker then **tried to write through `Bash` (`printf > file`)**, also denied (3 denials in the `result` event). It returned `blocked`. Nothing written. |
| [B](runs/B.md) | 1.1, continuation of B0 | `--permission-mode acceptEdits` | One path written, in scope, host check passes; accepted. |
| [C-429](runs/C-429.md) | 3.1 ambiguous | `acceptEdits` | The account hit its usage limit mid-run: `result` event with `is_error: true`, `api_error_status: 429`, exit 1, no payload. Recorded, claim released, rerun. |
| [C](runs/C.md) | 3.1 | `acceptEdits` | `needs_input` with a precise question; no write. |
| [D](runs/D.md) | 3.1, continuation of C | `--resume <C's session>`, prompt **without the task text** | Same session, new attempt; the rename was made and verified; accepted. |
| [E1-argv](runs/E1-argv.md) | 4.1 | `--allowedTools Bash` (space form) | The variadic `--allowedTools` took the prompt as another tool name; the CLI exited 1 with "Input must be provided". No task ran. |
| [E1](runs/E1.md) | 4.1 slow counter | `acceptEdits`, `--allowedTools=Bash`; `SIGINT` to the launch process group after 20 s | **Exit 0**, `result` subtype `error_during_execution`, no payload. The Bash tool ran the loop in **its own process group** (13 descendants outside the launch group). Claude ended that group on `SIGINT`: nothing survived, 10 lines written. |
| [E2](runs/E2.md) | 4.1 | same; `SIGKILL` after 20 s | Exit 137. The launch process group was empty, yet **the Bash tool's shell (its own process group) survived and kept writing**: 14 → 38 lines, until the operator killed that group. The runner did not attest; the attempt stayed `unknown` with its claim held. |
| [S](runs/S.md) | 2.1 read | `--json-schema <result.v1 schema>` | Valid `submitted`, but the `result` event carried no `structured_output`: the answer was free text with the JSON embedded. |

## What the runs establish

- **Headless and structured output.** `claude -p --output-format stream-json
  --verbose` writes JSON Lines; `session_id` is on every event; the run ends
  with a `result` event (`subtype`, `is_error`, `result`,
  `permission_denials`). Extraction rule: `.result` of the last `result`
  event, then its last line that is a JSON object; `is_error: true` means no
  result.
- **Exit code is not a completion signal.** 0 for completed runs whatever
  the disposition, and **also 0 after `SIGINT`**; 1 for a usage-limit or
  argument error; 137 after `SIGKILL`.
- **Permissions.** With no flags (and a user settings file that grants
  nothing), edits and writing shell commands are denied, read-only shell
  commands are allowed. `--permission-mode acceptEdits` allows edits,
  including edits through the shell. `--allowedTools` is variadic: use
  `--allowedTools=<tools>`, or it swallows the prompt. The user's settings,
  hooks, plugins and MCP servers load into `-p` runs.
- **Read-only mode: not established.** The default mode denied writes only
  with a settings file that grants nothing; the invocation inherits the
  user's permissions, hooks and MCP servers. The card keeps
  `read_only_mode: unverified`, so a read attempt on Claude takes the writer
  claim.
- **The permission layer, not the prompt, stops a workaround.** In B0 the
  worker tried a shell redirect after `Write` was denied, against the
  environment clause.
- **Resume.** `--resume <session_id>` continues the conversation (D).
- **Cancel.** `SIGINT` to the launch process group makes Claude end its tool
  process groups too (E1).
- **Descendants outlive the parent.** The Bash tool runs commands in a
  separate process group. After `SIGKILL` that group survives and keeps
  writing (E2). `descendants_may_outlive` is therefore **verified**: an empty
  launch process group is never a safe stop for Claude.
- **`--json-schema` does not enforce passdown's result schema** (S).


## How stops were attested

The runner that produced these records ([`../executor-run.sh`](../executor-run.sh) as it was then) recorded `owner-attested`
**by itself** whenever the launch process group was empty and its own scans
found no surviving descendant and no new claude process. It asked no person.
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

`TERM`; `bypassPermissions` and `auto` modes; resume from another directory;
a containment scope; `--setting-sources` to isolate the run from user
settings.
