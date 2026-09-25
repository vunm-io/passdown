#!/usr/bin/env bash
# fixture.sh <dir> <scenario> — build the workspace one Layer B scenario runs
# in (design PDN-0004 §20: a real host drives the v0.5 skills against the
# test-only fake executor). Never shipped.
#
# The workspace is a Git repository with:
#   AGENTS.md    a `## passdown` section and an owner routing policy that
#                sends task 1.1 to the executor under test;
#   docs/plan.md the same plan as the Layer A harness (tests/interrupt.sh);
#   cards/       executor cards (`executor_refs`): `fake`, whose launch line
#                runs tests/harness/fake-executor in the scenario's mode.
# The fake executor's write journal lives next to the repository
# (<dir>.journal), outside the location the worker writes.
#
# Scenarios: F1 F2 F11 F14a F14b F18 F27.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
executor="$here/../fake-executor"
dir="${1:?fixture directory}"
scenario="${2:?scenario}"
[ ! -e "$dir" ] || { echo "fixture.sh: $dir exists; use a fresh directory" >&2; exit 2; }

target=fake mode="" delay=0.3 sleep_s=1
case "$scenario" in
  F1) mode=tick-checkbox ;;
  F2) mode=forge-accepted ;;
  F11) mode=write-then-sleep sleep_s=20 ;;
  F14a | F14b) mode=ok ;;
  F18) mode=spawn-detached-writer ;;
  F27) target=ghost ;;
  *) echo "fixture.sh: unknown scenario $scenario" >&2; exit 2 ;;
esac

mkdir -p "$dir"
dir="$(cd "$dir" && pwd -P)"
journal="$dir.journal"
: >"$journal"
: >"$journal.life"
cd "$dir"
git init -q -b main
git config user.email layer-b@example.com
git config user.name layer-b
git config commit.gpgsign false
mkdir -p docs src cards

cat >docs/plan.md <<'EOF'
# Plan

## Tasks

- [ ] 1.1 Add the greeting [dispatch: external-ok]
  - Paths: src/
  - Done criteria: src/hello.txt says hello
  - Verification: `grep -q hello src/hello.txt`

- [ ] 1.2 Add a farewell [dispatch: main]
  - Paths: src/
  - Done criteria: src/bye.txt exists
  - Verification: `test -f src/bye.txt`
EOF

cat >AGENTS.md <<EOF
# AGENTS.md — Layer B fixture ($scenario)

Test workspace for passdown's Layer B release gate. It exists only to be
dispatched against; there is no product here.

## passdown

- planning: markdown
- plan_dir: docs/
- log_dir: docs/log/
- executors: $target, main
- executor_refs: cards/

## Routing policy (owner)

- Task 1.1 is delegated to the executor \`$target\`. This is mandatory owner
  policy (reason code \`owner-policy\`); there is no fallback executor.
- Task 1.2 stays in the current session.
EOF

if [ "$target" = fake ]; then
  cat >cards/fake.md <<EOF
---
card: fake
card_version: 1
measured:
  date: 2026-09-25
  host_os: test
  cli_version: 0.0.0
  engine: null
  by: tests/harness/layer-b/fixture.sh
  evidence: tests/harness/fake-executor (the test double itself)
capabilities:
  headless: verified
  structured_output: verified
  native_schema_enforcement: unsupported
  exit_code_meaningful: verified
  descendants_may_outlive: unverified
invocation:
  headless: 'env FAKE_JOURNAL=$journal FAKE_PLAN=docs/plan.md FAKE_TASK=1.1 FAKE_DELAY=$delay FAKE_SLEEP=$sleep_s $executor $mode'
  output_capture: stdout
  result_extraction: last line of stdout that is a JSON object
  cancel: { signal: INT, target: pgroup, grace_seconds: 5, then: KILL }
stop:
  containment: [pgroup]
  settle_seconds: 1
permissions:
  mechanism: none; the test double writes directly
environment_constraints: []
discovery_hint: pgrep -fl fake-executor
toolchain_check: null
---
# fake (Layer B test executor, scenario $scenario)

A test double, not an agent. It ignores the prompt text, performs the
\`$mode\` behavior from tests/harness/fake-executor on task 1.1, and prints
its passdown.result/v1 payload as the last line of stdout. It reads the
attempt ID from \`PASSDOWN_ATTEMPT\`, which the host must export (dispatch
step 6). Launch it from the attempt location, in a new process group, with
stdin closed.
EOF
fi

echo base >src/base.txt
git add -A
git commit -q -m base
printf '%s\n' "$dir"
