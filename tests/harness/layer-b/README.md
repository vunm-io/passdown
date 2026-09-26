# Layer B — real-host release gate for v0.5

Layer A (`tests/interrupt.sh`, in CI) proves the helper and the protocol
against a reference host. Layer B asks the one question Layer A cannot
answer: **does a real host follow the skill prose?** Design:
`docs/design/PDN-0004-v05-acceptance-recovery.md` §20. The release gate is
F1, F2, F11, F14a, F14b, F18 and F27 (§20.2, narrowed in #22).

| File | Role |
|---|---|
| `fixture.sh <dir> <scenario>` | Builds the scenario workspace: plan, `AGENTS.md` with an owner routing policy, and a card for the test executor (`../fake-executor` in the scenario's mode) |
| `scenarios/<S>.sh` | Crash marker, ground truth and expected behavior of one scenario |
| `run.sh <S> <out>` | Runs the host (`claude -p`), kills it at the crash marker, starts a new session for pickup, relays the owner's answers, then collects and judges |
| `collect.sh`, `oracle.sh` | Copy the files after a run and judge them. Safety is judged from files only. Each scenario also lists the evidence that it really ran (`REQUIRE`: host turn, worker, crash, pickup, accepted verdict, changed task or artifact, detached write). Missing evidence makes the run **incomplete** (exit 2), never a pass |

## Before running

- The host must load exactly one passdown version, the one under test. With
  the Claude Code plugin pinned to the release branch and no direct copies,
  `scripts/doctor.sh` reports "install channels are clean". Do not run
  `./install.sh` for Claude.
- `claude` must be logged in (`claude -p "ping"` answers).

## Running a scenario (the owner, in a terminal)

```bash
LB_OPERATOR="<your name>" tests/harness/layer-b/run.sh F1 docs/evidence/v0.5.0/F1
```

The script shows each host reply and waits for your answer. When the host
asks whether any process remains for an attempt, **check it yourself**
(`pgrep -fl fake-executor`, and the process group the host names) before
you confirm. The script passes your words through verbatim, records them in
`owner-answers.txt`, and never answers for you. An empty line ends the run.
The script then copies the files and prints the oracle's verdict
(`oracle.txt`).

Crash scenarios (F2, F11, F14a, F14b) watch every host turn, including the
ones after your answers (F14's verdict only comes after your attestation).
They kill the host at their marker, apply
the scenario's edit, and open a new session that runs pickup and
reconciles. The worker the host launched keeps running across the crash,
as it would in a real one.

## After running

Replace local paths in the transcripts, and remove personal environment
names (MCP servers, plugins) from the `init` events, as done for
`docs/evidence/e-claude-1/`. Then record pass/fail per scenario in
`docs/evidence/v0.5.0/README.md`. A failing scenario blocks the release and
becomes a fix, not a waiver.
