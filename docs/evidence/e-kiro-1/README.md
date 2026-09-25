# E-KIRO-1 — kiro-cli measured through the v0.5 lifecycle

Experiment design: §19 of `docs/design/PDN-0004-v05-acceptance-recovery.md`.
Result: the card at
`plugins/passdown/skills/passdown-dispatch/references/executors/kiro-cli.md`.

| | |
|---|---|
| Date | 2026-09-25 |
| kiro-cli | 2.24.0 (engine `v2`, from the `runStarted` event) |
| Host | macOS 26.6.2, `/bin/bash` 3.2 |
| Operator | Claude (passdown maintainer session), attesting stops from the recorded process listings |
| Fixture | a disposable Git repository with a four-task plan (read, bounded write, ambiguous, long-running), built inline; [`../fixture.sh`](../fixture.sh) reproduces it |
| Runner | [`run.sh`](run.sh) — every run goes through the real helper: `new`, `arm`, launch, `observe`, `probe`, `result`, `inspect`, verdict |
| Records | [`runs/`](runs/): per run the log (`<part>.md`), the exact prompt, the stream-json transport, the final receipt and the descendant tree seen while it ran. Local paths are replaced by `<fixture>`, `<scratch>`, `~` |

The design's version (`2.22.1`) was superseded by an update before the
experiment ran; the card records the version actually measured.

## Runs

| Run | Task | Setup | Outcome |
|---|---|---|---|
| [A](runs/A.md) | 2.1 read (count lines) | no trust flags | Exit 0. Result valid, `submitted`, correct count. `git status` clean. The shell call (`wc -l`) was **denied**; the worker fell back to the file-read tool. |
| [B0](runs/B0.md) | 1.1 write one file | no trust flags | The write was denied; the worker stopped and returned `blocked` with the error verbatim. Nothing written. Its payload was invalid only because the operator's prompt described the blocker kind wrongly (fixed before B: the prompt now carries the result schema itself). |
| [B](runs/B.md) | 1.1 | `--trust-tools=fs_read,fs_write` | File written, exactly one path, in scope, host check passes. The worker then tried to run the verification command, was denied the shell, and returned `blocked` as instructed. |
| [B2](runs/B2.md) | 1.1, continuation of B | `fs_read,fs_write,execute_bash`; answer "shell is trusted" | `submitted`; host check passes; two equal inspections 5 s apart; **accepted and projected**. |
| [C](runs/C.md) | 3.1 ambiguous rename | shell trusted | `needs_input` with a precise question; **no write**. |
| [D](runs/D.md) | 3.1, continuation of C | `--resume-id <C's session>`, prompt **without the task text**, answer `timeout_seconds` | Same session ID, new attempt ID. The resumed session knew the task, made the rename and verified it. Accepted and projected. |
| [E1](runs/E1.md) | 4.1 slow counter (40 appends, 1 s apart) | `SIGINT` to the process group after 15 s | Exit 1 at once; no `runFinished` event, so no result. 10 lines written; no write afterwards. No process survived. |
| [E2](runs/E2.md) | 4.1 | `SIGKILL` to the process group after 15 s | Exit 137; no result; 5 lines written, none afterwards. No process survived. |

## What the runs establish

- **Headless and structured output.** `kiro-cli chat --output-format
  stream-json` implies non-interactive mode and writes ACP events as JSON
  Lines. The first `metadata` event carries `sessionId`; the run ends with a
  `runFinished` event holding `status`, `finalText` and `finalTextTruncated`.
  Extraction rule: the `finalText` of the last `runFinished` event, then its
  last line that is a JSON object. Worked in every completed run (A, B0, B,
  B2, C, D).
- **No `runFinished` means no result.** Both interrupted runs (E1, E2) ended
  without one. A truncated `finalText` would also be an observation problem,
  not a worker failure.
- **Exit code.** 0 whenever the run completed, whatever the disposition
  (`submitted`, `blocked`, `needs_input` all exit 0); 1 after `SIGINT`; 137
  after `SIGKILL`. It tells a completed run from an interrupted one, not a
  good result from a bad one.
- **Permissions.** In non-interactive mode an untrusted tool is denied, not
  prompted: stderr says `[denied] tool permission approval is not supported
  in non-interactive mode`. File reads are allowed by default. Writes need
  `fs_write`; shell commands need `execute_bash`. The worker followed the
  environment clause each time (stopped with `blocked`, no workaround).
- **Read-only mode: not established.** Without `--trust-tools`, writes and
  shell were denied (A, B0) while reads worked. But an MCP server the user
  configured with auto-approval is outside what was measured and could
  write, so the card keeps `read_only_mode: unverified`. A read attempt on
  kiro-cli takes the writer claim.
- **No native schema enforcement.** `kiro-cli chat --help` (2.24.0) offers
  no option to enforce an output schema; the host validates.
- **Resume.** `--resume-id <sessionId>` from the same working directory
  continues the conversation: D had no task text and still did the right
  task.
- **Cancel.** `SIGINT` to the process group ends the whole tree within the
  2 s the runner waited; `SIGKILL` does too.
- **Process tree.** Every run: `kiro-cli` → `kiro-cli-chat chat` →
  `kiro-cli-chat acp` → tool shells (`bash -c …`, `sleep`), all in the
  launch process group, none in another group, none alive after the parent
  exited. The long-lived `kiro_cli_desktop` process on this machine
  (parent 1, started hours before the experiment) is not part of any run.

## What they do not establish

- **`descendants_may_outlive` stays `unverified`.** kiro-cli's own processes
  never left the process group, but with `execute_bash` trusted the model can
  run any command, including one that starts a process in a new group or
  session. Eight runs cannot rule that out, so a plain `exit+pgroup-empty` is
  not treated as a safe stop for Kiro. Every attempt still ends with owner
  attestation, unless it was launched in a containment scope. With only
  `fs_read`/`fs_write` trusted, no shell exists to detach anything; a card
  per trust profile could mark that case `unsupported` later.
- `TERM` was not tried; the card's cancel escalation is `INT`, then `KILL`.
- Resume from a different working directory, or after the session store is
  cleared, was not tried.
- No sandbox mode was measured (`--cloud` was out of scope).


## How stops were attested

The runner that produced these records ([`run.sh`](run.sh), kept as it ran) recorded `owner-attested`
**by itself** whenever the launch process group was empty and its own scans
found no surviving descendant and no new kiro process. It asked no person.
Those scans sample every 0.3 s and match process names, so they can miss a
process that detaches and exits quickly. That is fine for measuring what
the CLI does, but it is **not** the attestation the dispatch skill requires
(steps 10–11: a person confirms, and the host never attests on their
behalf). The `accepted` verdicts in these fixtures are measurement
artifacts, not examples of protocol-compliant acceptance.
The runner was changed after review
([#21](https://github.com/vunm-io/passdown/pull/21)):
[`../executor-run.sh`](../executor-run.sh) now stops at `unknown` and needs
`--finish <part> --attested-by <who>` from the operator before it records a
stop.

## A finding about passdown itself

B0 exposed a gap in the dispatch skill: its result clause asked for "one JSON
object matching `passdown.result/v1`" without saying what that schema is. The
worker followed the operator's hand-written approximation exactly, and the
approximation was wrong. The skill now tells the host to put the bundled
`result.v1.schema.json` into the prompt when the card does not verify native
schema enforcement.
