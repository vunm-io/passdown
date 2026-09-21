#!/usr/bin/env bash
# Behavioral harness, Layer A (design PDN-0004 section 20): the interruption
# matrix F1-F26 driven through tests/harness/ref-host (the host protocol) and
# tests/harness/fake-executor (a worker), against the real helper.
#
# Oracles checked after every scenario:
#   - no false acceptance: no accepted receipt and no pickup-accepted task
#     unless the scenario's ground truth says so, and every accepted verdict
#     matches the final tree;
#   - no silent overlapping writer: no two attempts' worker lifetimes overlap
#     on one location;
#   - every receipt passes `validate`, and unresolved attempts carry the
#     expected recovery class.
#
# The last group is a mutation check: the suite runs scenarios against a copy
# of the helper whose claim check is stubbed out, and must fail.
#
#   tests/interrupt.sh              all scenarios + mutation check
#   tests/interrupt.sh F4 F18       selected scenarios
#
# `[ a ] && [ b ] || fail` means "unless both hold, fail" throughout.
# shellcheck disable=SC2015
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
harness="$repo_root/tests/harness"
export PASSDOWN_EXECUTOR_REFS="$repo_root/tests/fixtures/attempt/cards"
export REF_HELPER="${REF_HELPER:-$repo_root/scripts/passdown-attempt}"
unset PASSDOWN_ATTEMPT PASSDOWN_ATTEMPT_DIR PASSDOWN_TEST_CRASH_AT REF_CRASH_AT REF_ATTEST REF_CANCEL_AFTER

tests_run=0
fail() { echo "FAIL [$scenario]: $*" >&2; exit 1; }
pass() { tests_run=$((tests_run + 1)); echo "ok $tests_run - $scenario: $*"; }

scratch="$(mktemp -d)"
scratch="$(cd "$scratch" && pwd -P)"
cleanup() {
  local pid
  if [ -f "$scratch/pids" ]; then
    while read -r pid; do kill -KILL "-$pid" 2>/dev/null || true; done <"$scratch/pids"
  fi
  pkill -KILL -f "$scratch" 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT

scenario=""
H() { "$REF_HELPER" --store "$store" "$@"; }
field() { jq -r "$2" "$store/$1/receipt.json"; }
rev() { field "$1" .rev; }

# setup <name>: a fresh fixture repository and journal for one scenario.
setup() {
  scenario="$1"
  repo="$scratch/$1/repo"
  store="$repo/.git/passdown/attempts"
  journal="$scratch/$1/journal"
  mkdir -p "$repo"
  : >"$journal"
  : >"$journal.life"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
  git -C "$repo" config commit.gpgsign false
  mkdir -p "$repo/docs" "$repo/src"
  cat >"$repo/docs/plan.md" <<'EOF'
# Plan

## Tasks

- [ ] 1.1 Add the greeting [dispatch: external-ok]
  - Paths: src/
  - Done criteria: src/hello.txt says hello
  - Verification: `grep -q hello src/hello.txt`

- [ ] 1.2 Add a farewell [dispatch: external-ok]
  - Paths: src/
  - Done criteria: src/bye.txt exists
  - Verification: `true`

- [ ] 2.1 Review the greeting [dispatch: external-ok]
  - Paths: docs/review/
  - Done criteria: findings reported in the result
  - Verification: `true`
EOF
  echo base >"$repo/src/base.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  export REF_REPO="$repo" REF_STORE="$store" REF_JOURNAL="$journal"
  # The test card has not measured descendants, so the owner attests every
  # stop unless a scenario says otherwise (design 8.3).
  export REF_ATTEST=owner
  ground_truth_accepted=""
}

# host <args>: run the reference host; output in $out, exit code in $code.
host() {
  code=0
  out="$("$harness/ref-host" "$@" 2>"$scratch/$scenario/host.err")" || code=$?
  printf '%s\n' "$out" >>"$scratch/$scenario/host.log"
  if [ -n "${HARNESS_DEBUG:-}" ]; then printf '%s\n' "$out" >&2; cat "$scratch/$scenario/host.err" >&2; fi
}
# host_bg <args>: run the reference host in the background (it may crash).
host_bg() {
  "$harness/ref-host" "$@" >>"$scratch/$scenario/host.log" 2>&1 &
  host_pid=$!
}
outcome_of() { sed -n 's/^outcome [^ ]* //p' <<<"$out" | tail -n 1; }
attempt_of() { sed -n 's/^step new //p' <<<"$out" | tail -n 1; }
crashed() { grep -q "^crash " <<<"$out"; }
worker_pid() { field "$1" .handle.pid; }

# reap <attempt>: the harness (acting as the owner) kills an attempt's worker
# processes and closes their lifetime entries.
reap() {
  local a="$1" pid t
  pid="$(field "$a" '.handle.pgid // empty' 2>/dev/null || true)"
  [ -z "$pid" ] || kill -KILL "-$pid" 2>/dev/null || true
  awk -v a="$a" '$1 == "begin" && $4 == a { print $2 }' "$journal.life" | while read -r pid; do
    kill -KILL "$pid" 2>/dev/null || true
    grep -q "^end $pid " "$journal.life" || {
      t="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
      echo "end $pid $t" >>"$journal.life"
    }
  done
}

wait_dead() { # <pid>: wait until a process (not our child) is gone
  local n=0
  while kill -0 "$1" 2>/dev/null && [ "$n" -lt 200 ]; do sleep 0.05; n=$((n + 1)); done
}

class_of() { H --json list --unresolved | jq -r --arg id "$1" '.[] | select(.id == $id) | .classes | join(",")'; }

expect_refused_new() { # a second writer on the target must be refused (exit 6)
  local c=0
  H new --task-ref docs/plan.md#1.2 --planner-repo "$repo" --kind write --tier external --reason-code quota \
    --reason "second writer" --executor fake --card fake@1 --host other --place-repo "$repo" \
    --isolation current-checkout >/dev/null 2>&1 || c=$?
  [ "$c" = 6 ] || fail "a second writer was not refused (exit $c): $*"
}

# ------------------------------------------------------------------ oracles

oracle() {
  local f a task
  # 1. False acceptance.
  for f in "$store"/pd-*/receipt.json; do
    [ -f "$f" ] || continue
    [ "$(jq -r .verdict.acceptance "$f")" = accepted ] || continue
    a="$(jq -r .id "$f")"
    task="$(jq -r '.task.ref | sub(".*#"; "")' "$f")"
    case " $ground_truth_accepted " in
      *" $task "*) ;;
      *) fail "false acceptance: $a accepted task $task" ;;
    esac
    [ "$(H digest artifact "$a")" = "$(jq -r .verdict.artifact_digest "$f")" ] ||
      fail "false acceptance: $a's accepted artifact digest does not match the final tree"
  done
  "$harness/ref-host" pickup >"$scratch/$scenario/pickup.out" 2>/dev/null || true
  while read -r kind task _; do
    [ "$kind" = accepted ] || continue
    case " $ground_truth_accepted " in
      *" $task "*) ;;
      *) fail "false acceptance: pickup counts task $task accepted" ;;
    esac
  done <"$scratch/$scenario/pickup.out"

  # 2. Overlapping writers: per location, worker lifetimes of different
  # attempts must not overlap. A process without an end is still alive.
  awk '
    $1 == "begin" { b[$2] = $3; att[$2] = $4; loc[$2] = $5 }
    $1 == "end" { e[$2] = $3 }
    END {
      for (p in b) {
        key = loc[p] SUBSEP att[p]
        s = b[p]; t = (p in e) ? e[p] : 1e18
        if (!(key in lo) || s < lo[key]) lo[key] = s
        if (!(key in hi) || t > hi[key]) hi[key] = t
      }
      for (k1 in lo) for (k2 in lo) {
        if (k1 >= k2) continue
        split(k1, x, SUBSEP); split(k2, y, SUBSEP)
        if (x[1] != y[1]) continue
        if (lo[k1] < hi[k2] && lo[k2] < hi[k1]) { printf "%s and %s overlap on %s\n", x[2], y[2], x[1]; bad = 1 }
      }
      exit bad
    }' "$journal.life" >"$scratch/$scenario/overlap.out" || fail "silent overlapping writer: $(cat "$scratch/$scenario/overlap.out")"

  # 3. Receipts are valid.
  if ls "$store"/pd-*/receipt.json >/dev/null 2>&1; then
    H validate --all >"$scratch/$scenario/validate.out" 2>&1 || fail "validate: $(cat "$scratch/$scenario/validate.out")"
  fi
}

# ---------------------------------------------------------------- scenarios

F1() {
  setup F1
  host dispatch --mode tick-checkbox
  [ "$(outcome_of)" = rejected:plan_tampered ] || fail "outcome $(outcome_of)"
  grep -q '^- \[ \] 1.1 ' "$repo/docs/plan.md" || fail "the worker's tick survived"
  oracle
  pass "a worker checkbox edit is restored and rejected plan_tampered; no [x] without a verdict"
}

F2() {
  setup F2
  REF_CRASH_AT=after-result host dispatch --mode forge-accepted
  crashed || fail "host did not crash"
  grep -q '^- \[x\] 1.1 ' "$repo/docs/plan.md" || fail "fixture: forged tick missing"
  oracle
  grep -q "^unaccepted 1.1" "$scratch/F2/pickup.out" || fail "pickup does not flag the forged task: $(cat "$scratch/F2/pickup.out")"
  pass "forged accepted + [x] then a host crash: pickup counts nothing accepted (unresolved attempt)"
}

F3() {
  setup F3
  host dispatch --mode edit-criteria
  case "$(outcome_of)" in rejected:plan_tampered | rejected:stale) ;; *) fail "outcome $(outcome_of)" ;; esac
  oracle
  pass "a worker editing its own done criteria is rejected ($(outcome_of))"
}

F4() {
  local o r
  setup F4
  host dispatch --mode malformed-result
  o="$(attempt_of)"
  [ "$(outcome_of)" = rejected:invalid_result ] || fail "O: $(outcome_of)"
  REF_CRASH_AT=after-verdict host reemit --prev "$o" --mode ok-no-write
  r="$(attempt_of)"
  crashed || fail "no crash after R's verdict"
  [ "$(field "$o" .verdict.reason_code)" = invalid_result ] || fail "O not already resolved"
  [ "$(class_of "$r")" = "C6,C10" ] || [ "$(class_of "$r")" = C6 ] || fail "R class $(class_of "$r")"
  [ "$(field "$r" .artifact.at_arm)" = "$(field "$o" .artifact.digest)" ] || fail "R at_arm != D"
  [ "$(field "$r" .artifact.digest)" = "$(field "$o" .artifact.digest)" ] || fail "R digest != D"
  host finish --id "$r"
  [ "$(outcome_of)" = accepted ] || fail "finish R: $(outcome_of)"
  ground_truth_accepted="1.1"
  [ ! -f "$repo/.git/passdown/claims/repo.json" ] || fail "claim survives projected R"
  host reemit --prev "$o" --mode ok-no-write
  [ "$code" = 6 ] || fail "a second re-emit in the chain was not refused ($code)"
  oracle
  pass "malformed result: O rejected, one no-write re-emit accepted on O's artifact, crash->C6 repaired, no second re-emit"
}

F5() {
  local o r s
  setup F5
  host dispatch --mode no-result
  o="$(attempt_of)"
  [ "$(outcome_of)" = rejected:invalid_result ] || fail "O: $(outcome_of)"
  FAKE_SLEEP=0.2 host reemit --prev "$o" --mode write-then-sleep
  r="$(attempt_of)"
  [ "$(outcome_of)" = rejected:reemit_wrote ] || fail "R: $(outcome_of)"
  [ "$(field "$r" .claim.state)" = held ] || fail "R dropped the claim"
  host salvage --prev "$r"
  s="$(attempt_of)"
  [ "$(field "$r" .claim.transferred_to)" = "$s" ] || fail "salvage did not receive the claim"
  [ "$(outcome_of)" = accepted ] || fail "salvage: $(outcome_of)"
  ground_truth_accepted="1.1"
  oracle
  pass "a writing re-emit is rejected reemit_wrote; salvage takes the claim by transfer and finishes on the host"
}

F6() {
  setup F6
  host_bg dispatch --mode write-then-sleep
  sleep 0.8
  perl -pi -e 's/src\/hello.txt says hello/src\/hello.txt says hello twice/' "$repo/docs/plan.md"
  wait "$host_pid" || true
  out="$(cat "$scratch/F6/host.log")"
  [ "$(outcome_of)" = rejected:stale ] || fail "outcome $(outcome_of)"
  oracle
  pass "a task edited while the worker runs makes its result stale; accept refused"
}

F7() {
  setup F7
  REF_ATTEST=owner host dispatch --mode write-outside-scope
  [ "$(outcome_of)" = rejected:scope_violation ] || fail "outcome $(outcome_of)"
  oracle
  pass "an out-of-scope write is rejected scope_violation"
}

F8() {
  local o c
  setup F8
  host dispatch --mode needs-input
  o="$(attempt_of)"
  [ "$(outcome_of)" = rejected:needs_input ] || fail "O: $(outcome_of)"
  [ "$(field "$o" .claim.state)" = held ] || fail "needs_input dropped the claim"
  host continue --prev "$o" --mode ok --answer "hello"
  c="$(attempt_of)"
  [ "$c" != "$o" ] && [ "$(field "$c" .continues)" = "$o" ] || fail "continuation link"
  [ "$(outcome_of)" = accepted ] || fail "C: $(outcome_of)"
  grep -q "attempt: $c" "$repo/docs/plan.md" || fail "the plan line does not name C"
  ground_truth_accepted="1.1"
  oracle
  pass "needs_input is rejected, a new attempt continues with the answer and is accepted"
}

F9() {
  local o n
  setup F9
  REF_ATTEST=owner host dispatch --mode blocked-env
  o="$(attempt_of)"
  [ "$(outcome_of)" = rejected:blocked ] || fail "outcome $(outcome_of)"
  [ "$(field "$o" .verdict.reason)" = "open /home/test/.gradle/caches: operation not permitted" ] ||
    fail "the blocker is not recorded verbatim: $(field "$o" .verdict.reason)"
  n="$(find "$store" -mindepth 1 -maxdepth 1 -name 'pd-*' | wc -l | tr -d ' ')"
  [ "$n" = 1 ] || fail "the host started another attempt after blocked ($n)"
  oracle
  pass "environment denial is rejected blocked, verbatim; no retry, no second executor"
}

F10() {
  local a
  setup F10
  REF_CRASH_AT=after-new host dispatch --mode ok
  a="$(attempt_of)"
  [ "$(class_of "$a")" = C1 ] || fail "class $(class_of "$a")"
  H abandon "$a" --rev "$(rev "$a")" >/dev/null || fail "abandon refused"
  oracle
  pass "crash after new: C1, abandon allowed, no ownership risk"
}

F11() {
  local a point
  for point in after-arm after-launch; do
    setup "F11-$point"
    REF_CRASH_AT="$point" host dispatch --mode ok
    a="$(attempt_of)"
    crashed || fail "no crash at $point"
    [ "$(class_of "$a")" = C2 ] || fail "$point: class $(class_of "$a")"
    expect_refused_new "after a crash $point"
    [ "$point" = after-arm ] || { sleep 1; reap "$a"; }
    oracle
  done
  scenario=F11
  pass "crash after arm and after launch: both C2 (never assumed not launched); no second writer"
}

F12() {
  local a
  setup F12
  export REF_ATTEST=owner
  FAKE_SLEEP=1 REF_CRASH_AT=after-first-write host dispatch --mode write-then-sleep
  a="$(attempt_of)"
  crashed || fail "no crash"
  [ "$(class_of "$a")" = C3 ] || fail "class $(class_of "$a")"
  [ "$(H probe "$a" | jq -r .process)" = alive ] || fail "probe does not see the live worker"
  expect_refused_new "while the worker still writes"
  wait_dead "$(worker_pid "$a")"
  host finish --id "$a"
  [ "$(outcome_of)" = accepted ] || fail "finish: $(outcome_of)"
  ground_truth_accepted="1.1"
  oracle
  pass "crash after the first write: C3, probe alive, no second writer; resumed and accepted after exit"
}

F13() {
  local a n
  setup F13
  REF_ATTEST=owner REF_CRASH_AT=after-result host dispatch --mode ok
  a="$(attempt_of)"
  [ "$(class_of "$a")" = C4 ] || fail "class $(class_of "$a")"
  host finish --id "$a"
  [ "$(outcome_of)" = accepted ] || fail "finish: $(outcome_of)"
  n="$(grep -c "attempt: $a" "$repo/docs/plan.md")"
  [ "$n" = 1 ] || fail "acceptance ran $n times"
  ground_truth_accepted="1.1"
  oracle
  pass "crash after the result: C4, the acceptance lifecycle runs once"
}

F14() {
  local a
  setup F14
  REF_ATTEST=owner REF_CRASH_AT=after-verdict host dispatch --mode ok
  a="$(attempt_of)"
  [ "$(class_of "$a")" = C6 ] || fail "class $(class_of "$a")"
  host finish --id "$a"
  [ "$(outcome_of)" = accepted ] || fail "finish: $(outcome_of)"
  [ "$(field "$a" '.verdict.projected_at != null')" = true ] || fail "not projected"
  ground_truth_accepted="1.1"
  oracle

  # Changed task: the verdict is historical, never projected.
  setup F14b
  REF_ATTEST=owner REF_CRASH_AT=after-verdict host dispatch --mode ok
  a="$(attempt_of)"
  perl -pi -e 's/Add the greeting/Add the greeting in French/' "$repo/docs/plan.md"
  host finish --id "$a"
  [ "$(outcome_of)" = historical ] || fail "changed task: $(outcome_of)"
  grep -q '^- \[ \] 1.1 ' "$repo/docs/plan.md" || fail "projected against a changed task"
  ground_truth_accepted="1.1"
  oracle
  scenario=F14
  pass "crash between verdict and projection: C6, projected only after digest + checks re-verified"
}

F15() {
  local a
  setup F15
  REF_CANCEL_AFTER=0.8 REF_CRASH_AT=after-cancel host dispatch --mode hang
  a="$(attempt_of)"
  crashed || fail "no crash"
  [ "$(class_of "$a")" = C8 ] || fail "class $(class_of "$a")"
  [ "$(H probe "$a" | jq -r .process)" = alive ] || fail "the hung worker is not alive"
  expect_refused_new "while cancellation is unconfirmed"
  local c=0
  H observe "$a" stopped --rev "$(rev "$a")" --evidence exit+pgroup-empty >/dev/null 2>&1 || c=$?
  [ "$c" = 3 ] || fail "unsafe stop accepted ($c)"
  reap "$a"
  wait_dead "$(worker_pid "$a")"
  H observe "$a" stopped --rev "$(rev "$a")" --evidence owner-attested --attested-by owner >/dev/null || fail "attested stop"
  oracle
  pass "cancel requested, termination unknown: C8, claim held, stop only with safe evidence"
}

F16() {
  local a
  setup F16
  REF_SESSION=other-session REF_CRASH_AT=after-arm host dispatch --mode ok
  a="$(attempt_of)"
  sleep 1.1
  "$harness/ref-host" pickup --session current-session --budget 0 >"$scratch/F16/pickup.out" 2>"$scratch/F16/pickup.err" || fail "pickup failed: $(cat "$scratch/F16/pickup.err")"
  grep -q "^class $a C9,C2 ownership-risk" "$scratch/F16/pickup.out" || fail "not surfaced as C9: $(cat "$scratch/F16/pickup.out")"
  echo "$a" >"$scratch/F16/handoff"
  "$harness/ref-host" pickup --session current-session --budget 0 --handoff "$scratch/F16/handoff" >"$scratch/F16/pickup2.out"
  grep -q "^class $a C2 ownership-risk" "$scratch/F16/pickup2.out" || fail "handoff-named attempt still C9"
  oracle
  pass "an old attempt from another session, not in the handoff, is surfaced C9 with ownership risk"
}

F17() {
  local o c
  setup F17
  host dispatch --mode needs-input
  o="$(attempt_of)"
  REF_CRASH_AT=after-arm host continue --prev "$o" --mode ok --answer hello
  c="$(attempt_of)"
  [ "$(class_of "$c")" = "C2,C10" ] || fail "class $(class_of "$c")"
  [ "$(field "$o" .verdict.reason_code)" = needs_input ] || fail "predecessor changed"
  [ "$(field "$o" .claim.state)/$(field "$o" .claim.transferred_to)" = "transferred/$c" ] || fail "claim not with C"
  oracle
  pass "interrupted continuation: C10 + C2 on the newest link; the predecessor is untouched"
}

F18() {
  local a c
  setup F18
  REF_ATTEST="" FAKE_DETACHED_DELAY=1.5 host dispatch --mode spawn-detached-writer
  a="$(attempt_of)"
  [ "$(outcome_of)" = unknown ] || fail "outcome $(outcome_of)"
  [ "$(field "$a" '.handle.parent_exited_at != null')" = true ] || fail "parent exit not recorded"
  c=0
  H observe "$a" stopped --rev "$(rev "$a")" --evidence exit+pgroup-empty >/dev/null 2>&1 || c=$?
  [ "$c" = 3 ] || fail "exit+pgroup-empty accepted on an unmeasured card ($c)"
  c=0
  H inspect "$a" --rev "$(rev "$a")" >/dev/null 2>&1 || c=$?
  [ "$c" = 3 ] || fail "inspect allowed before a safe stop ($c)"
  expect_refused_new "while the descendant is alive"
  sleep 2.5
  grep -q " $a .* src/late.txt" "$journal" || fail "fixture: the descendant did not write"
  expect_refused_new "after the descendant wrote, attempt still unresolved"
  reap "$a"
  H observe "$a" stopped --rev "$(rev "$a")" --evidence owner-attested --attested-by owner >/dev/null || fail "attest"
  oracle
  pass "a detached writer outlives its parent: unknown + parent_exited, no pgroup stop, no second writer until attested"
}

F18b() {
  local a
  setup F18b
  FAKE_DETACHED_DELAY=0.6 host dispatch --mode spawn-detached-writer --card fake-measured@1
  a="$(attempt_of)"
  [ "$(field "$a" .execution.stop_evidence)" = exit+pgroup-empty ] || fail "the wrong card did not allow a pgroup stop"
  case "$(outcome_of)" in pending:*) ;; *) fail "outcome $(outcome_of)" ;; esac
  # The host inspected once right after the stop; the settle inspection a
  # card-mandated second later sees the descendant's write.
  sleep 1.1
  H inspect "$a" --rev "$(rev "$a")" >/dev/null
  [ "$(field "$a" '.artifact.inspections[-2].digest != .artifact.inspections[-1].digest')" = true ] ||
    fail "the settle inspections did not see the late write"
  local c=0
  H verdict "$a" accept --rev "$(rev "$a")" --check "t=0:$repo/docs/plan.md" >/dev/null 2>&1 || c=$?
  [ "$c" = 3 ] || fail "accepted although the artifact changed inside the settle window ($c)"
  [ "$(field "$a" .claim.state)" = held ] || fail "claim released"
  oracle
  pass "a card that wrongly claims no detaching: the settle double-inspection sees the late write, accept refused"
}

F19() {
  local i n pids=() holders
  setup F19
  export REF_ATTEST=owner
  for i in 1 2 3 4 5 6 7 8; do
    "$harness/ref-host" dispatch --mode ok >>"$scratch/F19/host.$i.log" 2>&1 &
    pids+=("$!")
  done
  for i in "${pids[@]}"; do wait "$i" || true; done
  n="$(cat "$scratch"/F19/host.*.log | grep -c '^outcome .* accepted$' || true)"
  holders="$(cat "$scratch"/F19/host.*.log | grep -c '^step launch' || true)"
  [ "$holders" = 1 ] || fail "$holders workers launched"
  [ "$n" = 1 ] || fail "$n acceptances"
  [ "$(cat "$scratch"/F19/host.*.log | grep -c '^refused 6')" = 7 ] || fail "not every other host was refused"
  ground_truth_accepted="1.1"
  oracle
  pass "eight hosts dispatch at once: one launches and is accepted, seven are refused (exit 6)"
}

F19b() {
  local a
  setup F19b
  host_bg dispatch --mode write-then-sleep
  sleep 0.6
  expect_refused_new "while running"
  wait "$host_pid" || true
  setup F19b-2
  REF_CRASH_AT=after-result host dispatch --mode ok
  a="$(attempt_of)"
  expect_refused_new "while stopped+pending"
  oracle
  scenario=F19b
  pass "a second writer is refused while the first runs, and while it is stopped but pending"
}

F20() {
  setup F20
  REF_ATTEST=owner host dispatch --mode dispatch-external
  grep -q "depth-guard-exit=6" "$journal.events" || fail "the worker's external dispatch was not refused: $(cat "$journal.events" 2>/dev/null)"
  ground_truth_accepted="1.1"
  oracle
  pass "a worker's external dispatch is refused by the depth guard (exit 6)"
}

F21() {
  local p1 p2 s1 s2
  setup F21
  p1="$scratch/F21/planner1"
  p2="$scratch/F21/planner2"
  for p in "$p1" "$p2"; do
    git -C "$repo" clone -q "$repo" "$p"
    git -C "$p" config commit.gpgsign false
  done
  s1="$p1/.git/passdown/attempts"
  s2="$p2/.git/passdown/attempts"
  local c1=0 c2=0
  "$REF_HELPER" --store "$s1" new --task-ref docs/plan.md#1.1 --planner-repo "$p1" --kind write --tier external \
    --reason-code quota --reason t --executor fake --host p1 --place-repo "$repo" --isolation current-checkout \
    >"$scratch/F21/n1" 2>&1 &
  local b1=$!
  "$REF_HELPER" --store "$s2" new --task-ref docs/plan.md#1.1 --planner-repo "$p2" --kind write --tier external \
    --reason-code quota --reason t --executor fake --host p2 --place-repo "$repo" --isolation current-checkout \
    >"$scratch/F21/n2" 2>&1 &
  local b2=$!
  wait "$b1" || c1=$?
  wait "$b2" || c2=$?
  case "$c1/$c2" in 0/6 | 6/0) ;; *) fail "two planners: exits $c1/$c2" ;; esac
  if [ "$c1" = 6 ]; then grep -q "$s2" "$scratch/F21/n1" || fail "refusal does not name the other store"; fi
  if [ "$c2" = 6 ]; then grep -q "$s1" "$scratch/F21/n2" || fail "refusal does not name the other store"; fi
  [ "$(find "$repo/.git/passdown/claims" -name '*.json' -not -path '*/history/*' | wc -l | tr -d ' ')" = 1 ] ||
    fail "more than one claim on the target"
  "$REF_HELPER" --store "$s2" claims --repo "$repo" | grep -q "pd-" || fail "planner 2 cannot see the claim"
  oracle
  pass "two planners with separate stores target one repo: one claim, the other refused naming the holder's store"
}

F22() {
  local o r
  setup F22
  host dispatch --mode no-result
  o="$(attempt_of)"
  host_bg reemit --prev "$o" --mode hang
  sleep 1
  r="$(field "$o" .claim.transferred_to)"
  [ -n "$r" ] && [ "$r" != null ] || fail "no re-emit holds the claim"
  expect_refused_new "while the re-emit is live"
  reap "$r"
  wait "$host_pid" || true
  oracle
  pass "a second writer is refused while a hung re-emit holds the transferred claim"
}

F23() {
  local point a named
  for point in acquire:after-receipt acquire:after-claim-file; do
    setup "F23-${point//:/-}"
    PASSDOWN_TEST_CRASH_AT="$point" host dispatch --mode ok
    named="$(jq -r .holder "$repo/.git/passdown/claims/repo.json" 2>/dev/null || true)"
    a="$(find "$store" -mindepth 1 -maxdepth 1 -name 'pd-*' -exec basename {} \; | head -n 1)"
    case "$point" in
      acquire:after-receipt) [ -z "$named" ] || fail "$point: a claim file exists" ;;
      acquire:after-claim-file) [ "$named" = "$a" ] || fail "$point: claim names $named" ;;
    esac
    [ "$(class_of "$a")" = C1 ] || fail "$point: class $(class_of "$a")"
    oracle
  done
  scenario=F23
  pass "a helper crash inside new leaves a C1 attempt the next claim operation repairs (claim sweep: tests/attempt.sh)"
}

F24() {
  local a
  setup F24
  host_bg dispatch --mode write-then-sleep
  sleep 0.5
  host dispatch --kind read --task 2.1 --mode read-but-writes
  [ "$code" = 6 ] || fail "(a) an unguarded read was launched while the claim is held ($code)"
  wait "$host_pid" || true
  host dispatch --kind read --task 2.1 --mode read-but-writes --card fake-measured@1 --guard readonly:plan-mode \
    --location "$scratch/F24/snapshot"
  a="$(attempt_of)"
  [ "$(field "$a" .claim)" = null ] || fail "(b) guarded read took a claim"
  [ "$(field "$a" '.artifact.target_at_arm == .artifact.target_after')" = true ] || fail "(b) confined write changed the target"
  ground_truth_accepted="1.1 2.1"
  oracle
  setup F24-unconfined
  FAKE_TARGET="$repo" host dispatch --kind read --task 2.1 --mode read-but-writes --card fake-measured@1 \
    --guard readonly:plan-mode --location "$scratch/F24/snapshot2"
  a="$(attempt_of)"
  [ "$(field "$a" '.artifact.target_at_arm != .artifact.target_after')" = true ] || fail "(b') target write not detected"
  [ "$(outcome_of)" = rejected:scope_violation ] || fail "(b') incident not reported: $(outcome_of)"
  oracle
  scenario=F24
  pass "(a) an unguarded read needs the claim; (b) a guarded read is claim-free and a target write is reported"
}

F25() {
  local a r c1 c2 k
  setup F25
  REF_CRASH_AT=after-first-write host dispatch --mode hang
  a="$(attempt_of)"
  for k in 1 2 3; do
    r="$(rev "$a")"
    c1=0
    c2=0
    "$REF_HELPER" --store "$store" result "$a" --rev "$r" --payload "$repo/docs/plan.md" >/dev/null 2>&1 &
    local p1=$!
    "$REF_HELPER" --store "$store" observe "$a" unknown --rev "$r" --note race >/dev/null 2>&1 &
    local p2=$!
    wait "$p1" || c1=$?
    wait "$p2" || c2=$?
    case "$c1/$c2" in 4/5 | 5/0 | 0/5 | 5/4) ;; *) fail "round $k: exits $c1/$c2" ;; esac
  done
  reap "$a"
  oracle
  pass "result and observe planned from one rev: one lands, the other exits 5"
}

F26() {
  setup F26
  local c=0
  H new --task-ref docs/plan.md#1.1 --planner-repo "$repo" --kind write --tier external --reason-code quota --reason t \
    --executor fake --host h --place-repo "$repo" --isolation worktree --worktree-dir "$scratch" \
    --profile shared-db --profile-keys loc,port:5432 >/dev/null 2>&1 || c=$?
  [ "$c" = 6 ] || fail "a profile with port:5432 was accepted ($c)"
  [ -z "$(find "$repo/.git/passdown/claims" -name '*.json' 2>/dev/null)" ] || fail "a claim was written"
  oracle
  pass "a profile with a global key is rejected; no claim is written"
}

# ------------------------------------------------------------ mutation check

mutation() {
  # A helper whose claim check is stubbed out: keys are always free and every
  # attempt is armable. The scenarios that rely on the claim must now fail.
  local mutant="$scratch/mutant/scripts/passdown-attempt" s failed=""
  mkdir -p "$scratch/mutant/scripts"
  cp -R "$repo_root/schemas" "$scratch/mutant/schemas"
  sed -e 's/^keys_free() { #.*/keys_free() { return 0; }\nkeys_free_original() {/' \
    -e 's/^claim_names() { #.*/claim_names() { return 0; }\nclaim_names_original() {/' \
    "$repo_root/scripts/passdown-attempt" >"$mutant"
  chmod +x "$mutant"
  grep -q '^keys_free() { return 0; }' "$mutant" || { scenario=mutation; fail "could not build the mutant"; }
  for s in F11 F15 F19b F22; do
    if (export REF_HELPER="$mutant"; "$s") >"$scratch/mutation.$s.log" 2>&1; then
      :
    else
      failed="$failed $s"
    fi
  done
  scenario=mutation
  [ "$failed" = " F11 F15 F19b F22" ] ||
    fail "with the claim check stubbed out, only [$failed ] failed; the suite is blind to a missing guard"
  pass "with the claim check stubbed out, F11, F15, F19b and F22 all fail (the suite detects the missing guard)"
}

all="F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12 F13 F14 F15 F16 F17 F18 F18b F19 F19b F20 F21 F22 F23 F24 F25 F26 mutation"
[ "$#" -gt 0 ] || read -r -a all_list <<<"$all"
[ "$#" -gt 0 ] || set -- "${all_list[@]}"
for s in "$@"; do
  case " $all " in *" $s "*) "$s" ;; *) echo "unknown scenario $s" >&2; exit 2 ;; esac
done
echo "1..$tests_run"
