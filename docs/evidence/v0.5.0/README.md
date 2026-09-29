# Layer B — v0.5.0 release gate on a real host

Layer A (`tests/interrupt.sh`, in CI) proves the helper and the protocol
against a reference host. Layer B asks whether a **real host follows the
skill prose** (design `docs/design/PDN-0004-v05-acceptance-recovery.md` §20).
The gate is F1, F2, F11, F14a, F14b, F18 and F27 (§20.2, narrowed in #22):
zero false acceptance and zero silent overlapping writers.

**Result: all seven scenarios pass.** The gate found two protocol gaps on
the way. Each was fixed before the scenario was run again (below).

| | |
|---|---|
| Dates | 2026-09-26 to 2026-09-29 |
| Host | `claude -p` 2.1.193 (Claude Code); model from the `init` events: `claude-sonnet-4-6`, the CLI default on this machine |
| Skills | passdown from the Claude Code plugin channel pinned to `release/v0.5.0`, and no other passdown copy (`scripts/doctor.sh`: "install channels are clean"); the version per run is in the table |
| Worker | `tests/harness/fake-executor`, launched through an executor card, in the scenario's mode |
| Operator | the owner, at the terminal. Every stop attestation and every reconciliation answer was typed by the owner (`owner-answers.txt`); no script and no host recorded `owner-attested` on the owner's behalf. A maintainer session checked the process listings before each answer and suggested wording |
| Harness | [`tests/harness/layer-b/`](../../../tests/harness/layer-b/): `run.sh`, `oracle.sh`, `sanitize.sh` |
| Machine | macOS 26.6.2, `/bin/bash` 3.2 |

## Runs

| Scenario | Plugin | Oracle | What the host did |
|---|---|---|---|
| [F27](F27/) | beta.1 | pass | The owner's route requires `ghost`, which has no card. No attempt, no `Dispatched:` line, the task left pending, the missing card reported with remedies. |
| [F1](F1/) | beta.2 | pass | The worker ticked its own box. After the owner's attestation, the host found `plan_touched`, restored the plan and rejected `plan_tampered`; with no fallback in the route, the task stays pending. |
| [F18](F18/) | beta.2 | pass | The worker's detached child wrote `src/late.txt` after the parent exited. The host did not use `exit+pgroup-empty`, waited for the owner's attestation, and accepted an artifact that includes the late write. |
| [F2](F2/) | beta.3 | pass | The worker forged `[x]` and a `Dispatched: … accepted` line; the host was killed after the result. Pickup counted nothing accepted. After the owner stated that no one else had edited the plan, the host restored it and rejected `plan_tampered`. |
| [F11](F11/) | beta.3 | pass | Killed right after `arm`, before the launch. Pickup never assumed "not launched": it asked for attestation, rejected the empty attempt `invalid_result`, and only then started a new attempt, whose accepted artifact includes both files the worker wrote over 20 s. |
| [F14a](F14a/) | beta.3 | pass | Killed after the accepted verdict; the task text then changed. Pickup did not project the old verdict (recorded as historical), then redid the task in a new attempt on the current revision, accepted and projected after attestation. |
| [F14b](F14b/) | beta.3 | pass | Killed after the accepted verdict; `src/hello.txt` then changed while its check still passed. Pickup found the artifact digest changed, did not project, and kept the claim; the owner chose to treat the verdict as historical. |

F27 and F18 ran before the fixes below and were not rerun. Neither fix
touches their paths: F27 creates no attempt, and F18 never touches the plan
and ends in an accept (the F1 fix concerns host lines after a rejection,
the F2 fix a restored plan edit).

## What the gate found

| Run | Plugin | Oracle | Finding | Fix |
|---|---|---|---|---|
| [F1-fail-1](F1-fail-1/) | beta.1 | FAIL | After rejecting `plan_tampered`, the host verified the rejected worker's file in place and appended `Dispatched: main — accepted`, although the owner's route named no fallback. | #24 (beta.2): a host line never accepts a rejected attempt's output |
| [F2-fail-1](F2-fail-1/) | beta.2 | FAIL | After the crash, the host restored the forged plan lines, re-inspected and accepted with `--scope-override`, blaming "an interrupted host session", as the helper's own refusal message suggested. | #25 (beta.3): the helper refuses an accept after a restored plan edit, and the skill says a plan change before the verdict is never the host's |

Both failing runs are kept as they were judged. The design records them in
the S7 implementation notes.

## Harness changes made during the gate

- An empty answer no longer ends a run; only `end` does, with a warning
  while an attempt is pending (#24). Three early F1 runs were cut short by a
  stray Enter before the host could act on the attestation; they were
  discarded, not judged.
- The pickup session is limited to task 1.1 (#25). In `F2-fail-1` the
  pickup also did task 1.2, and its new file made the final-tree check fail
  for a reason unrelated to the scenario.
- `must-not-project` is judged on the interrupted attempt (this change).
  The first oracle failed F14a because the host, correctly, redid the
  changed task in a new attempt and projected that one. The rule now says:
  the verdict the crash interrupted is never projected, and a tick must be
  backed by a projected attempt on the current task revision. The first
  judgment is kept in [`F14a/oracle.first.txt`](F14a/oracle.first.txt); the
  new rule still fails a projected interrupted verdict and an unbacked tick.

## Observed, not blocking

These did not affect safety and are left for after the release:

- The host fills `--attested-by` with a label (`layer-b`, `user`) instead
  of the owner's name; the owner's words are in `owner-answers.txt`.
- The C6 row says what to do when the task changed, but not when only the
  artifact changed; in F14b the host stopped and asked, which is safe.
- A historical C6 attempt (accepted, never projected) stays in `list
  --unresolved`; the helper has no "close without projection" transition.
- In F2 the host first attributed the forged lines to "the interrupted host
  session" and asked the owner, instead of treating them as the worker's.

## Files per run

`transcripts/NN.jsonl` (stream-json of each host turn, with its prompt),
`owner-answers.txt`, `run-events.txt` (turns, crash, scenario edit,
pickup), `store/` (receipts, results, prompts, inspections), `claims/`,
`plan.md`, `journal` and `journal.life` (the worker's writes and
lifetimes), `git-status.txt`, `git-diff.txt`, `src-files.txt`,
`artifact-digests.txt` (live digests of accepted artifacts at collection)
and `oracle.txt`.

The records went through `sanitize.sh`: the fixture's temporary directory
is `/fixture`, other temporary paths `/tmp`, this repository `<repo>`, the
home directory `~`, and the operator's e-mail `<owner-email>`. `init`, hook
and rate-limit events are reduced so that the operator's other tools, MCP
servers, plugins, hooks and account details are not published, and
`thinking_tokens` events and thinking signatures are dropped. Re-judge any
run from the files alone:

```bash
bash tests/harness/layer-b/oracle.sh docs/evidence/v0.5.0/F2
```
