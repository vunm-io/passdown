#!/usr/bin/env bash
# Tests for scripts/passdown-attempt, the v0.5 deterministic helper
# (design: docs/design/PDN-0004-v05-acceptance-recovery.md, slice S2).
#
#   tests/attempt.sh                 all groups
#   tests/attempt.sh conformance     one group (see the list at the bottom)
#
# PASSDOWN_STRESS_ROUNDS (default 10) sets the rounds of the concurrent-new
# race; CI's stress job runs 50.
#
# `[ a ] && [ b ] || fail` means "unless both hold, fail" throughout.
# shellcheck disable=SC2015
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
helper="$repo_root/scripts/passdown-attempt"
fixtures="$repo_root/tests/fixtures/attempt"
export PASSDOWN_EXECUTOR_REFS="$fixtures/cards"
unset PASSDOWN_ATTEMPT PASSDOWN_ATTEMPT_DIR PASSDOWN_TEST_CRASH_AT

tests_run=0
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { tests_run=$((tests_run + 1)); echo "ok $tests_run - $*"; }

scratch="$(mktemp -d)"
scratch="$(cd "$scratch" && pwd -P)"
cleanup() {
  local pid
  for pid in ${spawned[@]+"${spawned[@]}"}; do kill -KILL "-$pid" 2>/dev/null || true; done
  rm -rf "$scratch"
}
spawned=()
trap cleanup EXIT

# run <expected exit> <description> <args...>: runs the helper, keeps stdout
# in $out and stderr in $err.
out=""
err=""
run() {
  local want="$1" what="$2" code=0
  shift 2
  out="$("$helper" "$@" 2>"$scratch/stderr")" || code=$?
  err="$(cat "$scratch/stderr")"
  [ "$code" = "$want" ] || fail "$what: expected exit $want, got $code
stdout: $out
stderr: $err"
}
ok() { run 0 "$@"; }

field() { jq -r "$2" "$store/$1/receipt.json"; }
rev() { field "$1" .rev; }

# A fresh fixture repository with a one-task plan, committed.
new_repo() { # <dir>
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  git -C "$dir" config commit.gpgsign false
  mkdir -p "$dir/docs" "$dir/src"
  cat >"$dir/docs/plan.md" <<'EOF'
# Plan

## Tasks

- [ ] 1.1 Add the greeting [dispatch: external-ok]
  - Paths: src/
  - Done criteria: src/hello.txt says hello
  - Verification: `grep -q hello src/hello.txt`

- [ ] 1.2 Review the greeting [dispatch: external-ok]
  - Paths: src/
  - Done criteria: a review exists
  - Verification: `true`
EOF
  echo base >"$dir/src/base.txt"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m base
}

# Standard `new` for a write attempt in the current checkout.
new_write() { # <repo> [extra args...] — sets $id
  local repo="$1"
  shift
  ok "new write" --store "$store" new --task-ref docs/plan.md#1.1 --planner-repo "$repo" --kind write \
    --tier external --reason-code quota --reason "test" --executor fake --card fake@1 --host test \
    --place-repo "$repo" --isolation current-checkout "$@"
  id="$out"
}

prompt_file="$scratch/prompt.txt"
echo "do the task" >"$prompt_file"
check_ok="$scratch/check-ok.txt"
echo "all good" >"$check_ok"

# spawn <command>: start a fake worker in its own process group; sets $wpid.
# The worker waits briefly first so the host can observe it running, as a
# real worker would still be starting up.
# Its start time is read right away, as a host does at launch, so a worker
# that exits before `observe running` is still bound to its pid.
spawn() {
  perl -e 'setpgrp(0, 0); exec @ARGV' sh -c "sleep 0.5; $1" &
  wpid=$!
  spawned+=("$wpid")
  wstart="$(ps -o lstart= -p "$wpid" | sed 's/^ *//; s/ *$//')"
  sleep 0.1
}

result_payload() { # <id> <disposition> -> file
  local f="$scratch/result-$1.json"
  case "$2" in
    submitted) jq -n --arg a "$1" '{schema: "passdown.result/v1", attempt: $a, disposition: "submitted",
      summary: "done", changed_paths: [{path: "src/hello.txt", change: "added"}], evidence: []}' >"$f" ;;
    needs_input) jq -n --arg a "$1" '{schema: "passdown.result/v1", attempt: $a, disposition: "needs_input",
      summary: "unclear", changed_paths: [], evidence: [], question: {text: "which greeting?"}}' >"$f" ;;
    blocked) jq -n --arg a "$1" '{schema: "passdown.result/v1", attempt: $a, disposition: "blocked",
      summary: "denied", changed_paths: [], evidence: [], blocker: {kind: "sandbox", message: "EPERM"}}' >"$f" ;;
    malformed) printf '{"schema": "passdown.result/v1", "attempt": "%s"' "$1" >"$f" ;;
  esac
  printf '%s\n' "$f"
}

# drive <id> <worker command>: arm, launch in a process group, observe
# running, wait for exit, then stop on owner attestation (the test card has
# not measured descendants, so nothing weaker is safe).
drive() {
  local id="$1" cmd="$2" r
  ok "arm $id" --store "$store" arm "$id" --rev "$(rev "$id")" --prompt "$prompt_file"
  spawn "$cmd"
  ok "observe running $id" --store "$store" observe "$id" running --rev "$(rev "$id")" --pid "$wpid" --pid-started "$wstart" --pgid "$wpid"
  wait "$wpid" || true
  ok "observe stopped $id" --store "$store" observe "$id" stopped --rev "$(rev "$id")" \
    --evidence owner-attested --attested-by tester --exit 0
  r="$(rev "$id")"
  : "$r"
}

plan_hash() { git -C "$1" hash-object docs/plan.md; }

tick_plan() { # <repo> <task> <attempt> — the host's projection edit
  perl -0pi -e "s/- \\[ \\] $2 (.*)\\n/- [x] $2 \$1\\n  - Dispatched: fake (2026-09-21) — accepted; verified: grep; attempt: $3\\n/" "$1/docs/plan.md"
}

# ------------------------------------------------------------------ groups

group_conformance() {
  # The helper must reach the schema validator's verdict on every fixture,
  # reject every invalid fixture at the manifest's pointer, and reject every
  # semantic-invalid fixture with the rule its file name names.
  local kind f rel _base pointer name as json bad="" count=0
  for kind in receipts results claims; do
    as="${kind%s}"
    for f in "$fixtures/$kind"/valid/*.json; do
      "$helper" validate --json --file "$f" --as "$as" --attempt pd-20260921T101530Z-3f9a1c2e >/dev/null ||
        bad="$bad ${f#"$fixtures"/}"
      count=$((count + 1))
    done
  done
  [ -z "$bad" ] || fail "helper rejects valid fixtures:$bad"
  pass "helper accepts every valid fixture ($count)"

  count=0
  while IFS=$'\t' read -r rel _base pointer; do
    case "$rel" in \#* | "") continue ;; esac
    kind="${rel%%/*}"
    as="${kind%s}"
    f="$fixtures/$rel"
    name="$(basename "$rel" .json)"
    json="$("$helper" validate --json --file "$f" --as "$as" --attempt pd-20260921T101530Z-3f9a1c2e || true)"
    [ "$(jq -r .valid <<<"$json")" = false ] || { bad="$bad $rel(accepted)"; continue; }
    count=$((count + 1))
    case "$rel" in
      results/*)
        jq -e --arg d "${name%%--*}" '.diagnostics | index($d)' <<<"$json" >/dev/null ||
          bad="$bad $rel(diagnostics $(jq -c .diagnostics <<<"$json"))"
        ;;
      */semantic-invalid/*)
        jq -e --arg n "$name" '.semantic | index($n)' <<<"$json" >/dev/null ||
          bad="$bad $rel(semantic $(jq -c .semantic <<<"$json"))"
        ;;
      *)
        [ "$pointer" = '!parse' ] && continue
        # Git Bash would rewrite a "/pointer" argument for jq.exe.
        MSYS_NO_PATHCONV=1 jq -e --arg p "$pointer" '[.errors[].path] | index($p)' <<<"$json" >/dev/null ||
          bad="$bad $rel(paths $(jq -c '[.errors[].path] | unique' <<<"$json"))"
        ;;
    esac
  done <"$fixtures/MANIFEST.tsv"
  [ -z "$bad" ] || fail "helper verdicts differ from the fixture manifest:$bad"
  pass "helper rejects every invalid fixture for the intended reason ($count)"

  local big="$scratch/big.json"
  jq -n '{schema: "passdown.result/v1", attempt: "pd-20260921T101530Z-3f9a1c2e", disposition: "submitted",
    summary: "x", changed_paths: [range(0; 2000) | {path: ("d/" + ("x" * 150) + "\(.)"), change: "added"}], evidence: []}' >"$big"
  json="$("$helper" validate --json --file "$big" --as result || true)"
  [ "$(jq -c .diagnostics <<<"$json")" = '["parse"]' ] || fail "a payload over 256 KiB is not rejected as parse: $json"
  pass "a result payload over 256 KiB is rejected (parse)"
}

group_lifecycle() {
  local repo="$scratch/life" before
  new_repo "$repo"
  store="$repo/.git/passdown/attempts"
  before="$(plan_hash "$repo")"
  new_write "$repo"
  [ "$(field "$id" .claim.state)" = held ] || fail "new does not hold the claim"
  [ -f "$repo/.git/passdown/claims/repo.json" ] || fail "no claim file after new"
  [ "$(jq -r .holder "$repo/.git/passdown/claims/repo.json")" = "$id" ] || fail "claim file names another attempt"
  [ -f "$store/$id/card.json" ] || fail "card snapshot missing"
  pass "new writes a prepared receipt, snapshots and a repo claim"

  drive "$id" "sleep 0.3; echo hello > '$repo/src/hello.txt'"
  [ "$(field "$id" .execution.observation)" = stopped ] || fail "not stopped"
  [ -f "$store/$id/prompt.md" ] || fail "prompt not stored at arm"
  pass "arm stores the prompt; observe running then stopped (owner-attested)"

  ok "result" --store "$store" result "$id" --rev "$(rev "$id")" --payload "$(result_payload "$id" submitted)"
  [ "$(field "$id" .result.status)" = valid ] || fail "result not valid"
  run 3 "second result" --store "$store" result "$id" --rev "$(rev "$id")" --payload "$(result_payload "$id" submitted)"
  pass "result stores a valid payload once"

  ok "inspect" --store "$store" inspect "$id" --rev "$(rev "$id")"
  [ "$(field "$id" .artifact.changed)" = 1 ] || fail "inspect: expected 1 changed path, got $(field "$id" .artifact.changed)"
  [ "$(field "$id" '.artifact.out_of_scope | length')" = 0 ] || fail "hello.txt is in scope"
  [ "$(field "$id" .artifact.plan_touched)" = false ] || fail "plan wrongly touched"
  pass "inspect computes the artifact against the baseline"

  echo "check output" >"$scratch/c1.txt"
  ok "accept" --store "$store" verdict "$id" accept --rev "$(rev "$id")" --check "grep -q hello src/hello.txt=0:$scratch/c1.txt"
  [ "$(field "$id" .verdict.acceptance)" = accepted ] || fail "not accepted"
  [ "$(field "$id" .claim.state)" = held ] || fail "claim released before projection"
  [ "$(plan_hash "$repo")" = "$before" ] || fail "the helper edited the plan"
  pass "accept persists the verdict; the claim stays until projection; plan bytes unchanged"

  run 3 "projected before the plan edit" --store "$store" projected "$id" --rev "$(rev "$id")" --plan "$repo/docs/plan.md"
  tick_plan "$repo" 1.1 "$id"
  ok "projected" --store "$store" projected "$id" --rev "$(rev "$id")" --plan "$repo/docs/plan.md"
  [ "$(field "$id" .claim.state)" = released ] || fail "projected did not release the claim"
  [ ! -f "$repo/.git/passdown/claims/repo.json" ] || fail "claim file still present"
  ls "$repo/.git/passdown/claims/history/$id".*.json >/dev/null || fail "no history entry"
  ok "validate" --store "$store" validate --all
  ok "list" --store "$store" list --unresolved
  [ -z "$out" ] || fail "resolved attempt listed as unresolved: $out"
  pass "projected checks the plan, releases the claim and resolves the attempt"

  # The task digest ignores the checkbox and Dispatched lines.
  [ "$("$helper" digest task --plan "$repo/docs/plan.md" --task 1.1)" = "$(field "$id" .task.digest)" ] ||
    fail "ticking the box changed the task digest"
  pass "ticking the box and appending Dispatched: keep the task digest"
}

group_transitions() {
  local repo="$scratch/trans" r
  new_repo "$repo"
  store="$repo/.git/passdown/attempts"
  new_write "$repo"
  r="$(rev "$id")"
  run 3 "observe running from prepared" --store "$store" observe "$id" running --rev "$r" --pid $$
  run 3 "observe stopped from prepared" --store "$store" observe "$id" stopped --rev "$r" --evidence owner-attested --attested-by x
  run 3 "inspect before stop" --store "$store" inspect "$id" --rev "$r"
  run 3 "result before launch" --store "$store" result "$id" --rev "$r" --payload "$(result_payload "$id" submitted)"
  run 3 "cancel before launch" --store "$store" cancel "$id" --rev "$r" --method INT
  run 3 "accept before anything" --store "$store" verdict "$id" accept --rev "$r" --check "t=0:$check_ok"
  run 5 "stale rev" --store "$store" arm "$id" --rev "$((r - 1))" --prompt "$prompt_file"
  run 2 "arm without rev" --store "$store" arm "$id" --prompt "$prompt_file"
  pass "prepared refuses every transition but arm/abandon/reject (exit 3), stale rev exits 5"

  ok "arm" --store "$store" arm "$id" --rev "$r" --prompt "$prompt_file"
  run 3 "arm twice" --store "$store" arm "$id" --rev "$(rev "$id")" --prompt "$prompt_file"
  run 3 "abandon after arm" --store "$store" abandon "$id" --rev "$(rev "$id")"
  run 3 "not-launched after launch evidence" --store "$store" observe "$id" stopped --rev "$(rev "$id")" --evidence exit
  run 2 "running without identity" --store "$store" observe "$id" running --rev "$(rev "$id")"
  pass "unknown: no second arm, no abandon, bare exit is not stop evidence"

  spawn "sleep 30"
  ok "running" --store "$store" observe "$id" running --rev "$(rev "$id")" --pid "$wpid" --pid-started "$wstart" --pgid "$wpid"
  run 3 "owner attests a live pid" --store "$store" observe "$id" stopped --rev "$(rev "$id")" --evidence owner-attested --attested-by x
  run 3 "pgroup evidence on an unmeasured card" --store "$store" observe "$id" stopped --rev "$(rev "$id")" --evidence exit+pgroup-empty
  kill -KILL "-$wpid"
  wait "$wpid" 2>/dev/null || true
  run 3 "pgroup evidence after exit, unmeasured card" --store "$store" observe "$id" stopped --rev "$(rev "$id")" --evidence exit+pgroup-empty
  ok "parent exited" --store "$store" observe "$id" unknown --rev "$(rev "$id")" --note "parent exited" --parent-exited
  [ "$(field "$id" '.handle.parent_exited_at != null')" = true ] || fail "parent_exited_at not set"
  [ "$(field "$id" .claim.state)" = held ] || fail "claim released on parent exit"
  "$helper" --store "$store" list --unresolved | grep -q "C3" || fail "parent-exited attempt is not C3"
  pass "a parent exit on an unmeasured card stays unknown (C3) and keeps the claim (F18 core)"

  ok "result while unknown" --store "$store" result "$id" --rev "$(rev "$id")" --payload "$(result_payload "$id" needs_input)"
  run 3 "inspect while unknown" --store "$store" inspect "$id" --rev "$(rev "$id")"
  ok "attested stop" --store "$store" observe "$id" stopped --rev "$(rev "$id")" --evidence owner-attested --attested-by tester
  ok "inspect" --store "$store" inspect "$id" --rev "$(rev "$id")"
  run 3 "accept a needs_input result" --store "$store" verdict "$id" accept --rev "$(rev "$id")" --check "t=0:$check_ok"
  run 2 "reject without reason" --store "$store" verdict "$id" reject --rev "$(rev "$id")" --reason-code needs_input
  run 3 "reject needs_input as worker_failed" --store "$store" verdict "$id" reject --rev "$(rev "$id")" --reason-code worker_failed --reason x
  ok "reject needs_input" --store "$store" verdict "$id" reject --rev "$(rev "$id")" --reason-code needs_input --reason "which greeting"
  [ "$(field "$id" .claim.state)" = held ] || fail "needs_input released the claim"
  run 3 "accept after reject" --store "$store" verdict "$id" accept --rev "$(rev "$id")" --check "t=0:$check_ok"
  "$helper" --store "$store" list --unresolved | grep -q "C11" || fail "claim-holding rejection is not listed as C11"
  pass "needs_input: result valid, rejection is final and holds the claim (C11)"
}

group_acceptance() {
  local repo="$scratch/acc" r
  new_repo "$repo"
  store="$repo/.git/passdown/attempts"

  # no check / failing check / out of scope / plan touched / stale / changed artifact
  new_write "$repo"
  drive "$id" "echo hello > '$repo/src/hello.txt'; echo x > '$repo/README.md'"
  ok "result" --store "$store" result "$id" --rev "$(rev "$id")" --payload "$(result_payload "$id" submitted)"
  ok "inspect" --store "$store" inspect "$id" --rev "$(rev "$id")"
  [ "$(field "$id" '.artifact.out_of_scope | join(",")')" = README.md ] || fail "README.md not out of scope"
  r="$(rev "$id")"
  run 3 "accept without check" --store "$store" verdict "$id" accept --rev "$r"
  run 3 "accept with failing check" --store "$store" verdict "$id" accept --rev "$r" --check "t=1:$check_ok"
  run 3 "accept with a passing and a failing check" --store "$store" verdict "$id" accept --rev "$r" \
    --check "lint=0:$check_ok" --check "test=1:$check_ok"
  run 3 "accept out of scope" --store "$store" verdict "$id" accept --rev "$r" --check "t=0:$check_ok"
  pass "accept needs every check to pass and an in-scope artifact (F7 core)"

  rm "$repo/README.md"
  run 3 "artifact changed after inspection" --store "$store" verdict "$id" accept --rev "$r" --check "t=0:$check_ok" --scope-override "restored"
  ok "re-inspect" --store "$store" inspect "$id" --rev "$r"
  perl -pi -e 's/src\/hello.txt says hello/src\/hello.txt says hi/' "$repo/docs/plan.md"
  run 3 "stale task" --store "$store" verdict "$id" accept --rev "$(rev "$id")" --check "t=0:$check_ok"
  printf '%s' "$err" | grep -q stale || fail "stale refusal does not say stale: $err"
  git -C "$repo" checkout -q docs/plan.md
  ok "accept after restore" --store "$store" verdict "$id" accept --rev "$(rev "$id")" --check "t=0:$check_ok"
  pass "accept refuses a changed artifact and a stale task (F6 core)"

  tick_plan "$repo" 1.1 "$id"
  ok "projected" --store "$store" projected "$id" --rev "$(rev "$id")" --plan "$repo/docs/plan.md"
  git -C "$repo" checkout -q docs/plan.md

  # worker ticks its own checkbox (F1)
  new_write "$repo"
  drive "$id" "perl -pi -e 's/- \\[ \\] 1.1/- [x] 1.1/' '$repo/docs/plan.md'; echo hello > '$repo/src/hello.txt'"
  ok "result" --store "$store" result "$id" --rev "$(rev "$id")" --payload "$(result_payload "$id" submitted)"
  ok "inspect" --store "$store" inspect "$id" --rev "$(rev "$id")"
  [ "$(field "$id" .artifact.plan_touched)" = true ] || fail "checkbox edit not detected"
  [ "$(field "$id" '[.artifact.out_of_scope[] | select(. == "docs/plan.md")] | length')" = 0 ] || fail "plan counted as submission"
  run 3 "accept a tampered plan" --store "$store" verdict "$id" accept --rev "$(rev "$id")" --check "t=0:$check_ok"
  ok "reject plan_tampered" --store "$store" verdict "$id" reject --rev "$(rev "$id")" --reason-code plan_tampered --reason "ticked its own box"
  [ "$(field "$id" .claim.state)" = released ] || fail "plan_tampered is not claim-holding"
  pass "a worker checkbox edit sets plan_touched and is rejected (F1)"

  # An edit to the attempt's own task text is not plan_touched: the task
  # digest goes stale instead, whoever made the edit (F3, F6).
  git -C "$repo" checkout -q docs/plan.md
  rm -f "$repo/src/hello.txt"
  new_write "$repo"
  drive "$id" "echo hello > '$repo/src/hello.txt'"
  ok "result" --store "$store" result "$id" --rev "$(rev "$id")" --payload "$(result_payload "$id" submitted)"
  perl -pi -e 's/src\/hello.txt says hello/src\/hello.txt says hi/' "$repo/docs/plan.md"
  ok "inspect" --store "$store" inspect "$id" --rev "$(rev "$id")"
  [ "$(field "$id" .artifact.plan_touched)" = false ] || fail "an edit to the task's own text counted as plan_touched"
  run 3 "accept a stale task" --store "$store" verdict "$id" accept --rev "$(rev "$id")" --check "t=0:$check_ok"
  printf '%s' "$err" | grep -q stale || fail "not reported stale: $err"
  ok "reject stale" --store "$store" verdict "$id" reject --rev "$(rev "$id")" --reason-code stale --reason "task edited"
  pass "an edit to the task's own text makes it stale, not plan_touched (F3, F6)"
  git -C "$repo" checkout -q docs/plan.md
  rm -f "$repo/src/hello.txt"

  # settle window on a measured card: two equal inspections >= 1 s apart
  ok "new measured" --store "$store" new --task-ref docs/plan.md#1.1 --planner-repo "$repo" --kind write --tier external \
    --reason-code quota --reason t --executor fake --card fake-measured@1 --host test --place-repo "$repo" --isolation current-checkout
  id="$out"
  ok "arm" --store "$store" arm "$id" --rev "$(rev "$id")" --prompt "$prompt_file"
  spawn "echo hello > '$repo/src/hello.txt'"
  ok "running" --store "$store" observe "$id" running --rev "$(rev "$id")" --pid "$wpid" --pid-started "$wstart" --pgid "$wpid"
  wait "$wpid" || true
  ok "pgroup stop on a measured card" --store "$store" observe "$id" stopped --rev "$(rev "$id")" --evidence exit+pgroup-empty --exit 0
  ok "result" --store "$store" result "$id" --rev "$(rev "$id")" --payload "$(result_payload "$id" submitted)"
  ok "inspect 1" --store "$store" inspect "$id" --rev "$(rev "$id")"
  run 3 "accept after one inspection" --store "$store" verdict "$id" accept --rev "$(rev "$id")" --check "t=0:$check_ok"
  sleep 1.1
  ok "inspect 2" --store "$store" inspect "$id" --rev "$(rev "$id")"
  ok "accept after settle" --store "$store" verdict "$id" accept --rev "$(rev "$id")" --check "t=0:$check_ok"
  pass "exit+pgroup-empty is safe only on a measured card; settle needs two equal inspections (F18b core)"

  # exit+scope-empty: safe on any card once the scope the host launched the
  # worker in is empty. A cgroup v2 directory is simulated by its
  # cgroup.procs file.
  local scope="$scratch/cgroup-sim"
  mkdir -p "$scope"
  tick_plan "$repo" 1.1 "$id"
  ok "projected" --store "$store" projected "$id" --rev "$(rev "$id")" --plan "$repo/docs/plan.md"
  git -C "$repo" checkout -q docs/plan.md
  new_write "$repo"
  ok "arm" --store "$store" arm "$id" --rev "$(rev "$id")" --prompt "$prompt_file"
  spawn "true"
  printf '%s\n' "$wpid" >"$scope/cgroup.procs"
  ok "running in a scope" --store "$store" observe "$id" running --rev "$(rev "$id")" --pid "$wpid" \
    --pid-started "$wstart" --pgid "$wpid" --containment scope --scope "$scope"
  wait "$wpid" || true
  printf '%s\n' 99999 >"$scope/cgroup.procs"
  run 3 "scope still has a process" --store "$store" observe "$id" stopped --rev "$(rev "$id")" --evidence exit+scope-empty
  : >"$scope/cgroup.procs"
  ok "scope empty" --store "$store" observe "$id" stopped --rev "$(rev "$id")" --evidence exit+scope-empty --exit 0
  [ "$(field "$id" .execution.stop_evidence)" = exit+scope-empty ] || fail "scope evidence not recorded"
  ok "reject" --store "$store" verdict "$id" reject --rev "$(rev "$id")" --reason-code worker_failed --reason t
  pass "exit+scope-empty needs the recorded scope to be empty, on any card"
}

group_claims() {
  local repo="$scratch/claims" first second
  new_repo "$repo"
  store="$repo/.git/passdown/attempts"
  new_write "$repo"
  first="$id"
  run 6 "second writer while prepared" --store "$store" new --task-ref docs/plan.md#1.2 --planner-repo "$repo" \
    --kind write --tier external --reason-code quota --reason t --executor fake --host test --place-repo "$repo" --isolation current-checkout
  printf '%s' "$err" | grep -q "$first" || fail "refusal does not name the holder: $err"
  [ "$(find "$store" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" = 1 ] || fail "a refused new left an attempt directory"
  ok "arm" --store "$store" arm "$first" --rev "$(rev "$first")" --prompt "$prompt_file"
  run 6 "second writer while unknown" --store "$store" new --task-ref docs/plan.md#1.2 --planner-repo "$repo" \
    --kind write --tier external --reason-code quota --reason t --executor fake --host test --place-repo "$repo" --isolation current-checkout
  ok "attested stop" --store "$store" observe "$first" stopped --rev "$(rev "$first")" --evidence owner-attested --attested-by t
  run 6 "second writer while stopped+pending" --store "$store" new --task-ref docs/plan.md#1.2 --planner-repo "$repo" \
    --kind write --tier external --reason-code quota --reason t --executor fake --host test --place-repo "$repo" --isolation current-checkout
  pass "no second writer while the first is prepared, unknown or stopped+pending (F19b)"

  # read attempts: no guard -> needs the claim; unverified guard -> refused
  run 6 "unguarded read while the claim is held" --store "$store" new --task-ref docs/plan.md#1.2 --planner-repo "$repo" \
    --kind read --tier native --reason-code fresh-context --reason t --executor fake --card fake@1 --host test \
    --place-repo "$repo" --isolation read-only
  run 6 "read guard the card has not verified" --store "$store" new --task-ref docs/plan.md#1.2 --planner-repo "$repo" \
    --kind read --tier native --reason-code fresh-context --reason t --executor fake --card fake@1 --host test \
    --place-repo "$repo" --isolation read-only --mutation-guard readonly:plan-mode
  ok "verified read guard is claim-free" --store "$store" new --task-ref docs/plan.md#1.2 --planner-repo "$repo" \
    --kind read --tier native --reason-code fresh-context --reason t --executor fake --card fake-measured@1 --host test \
    --place-repo "$repo" --isolation read-only --mutation-guard readonly:plan-mode
  second="$out"
  [ "$(field "$second" .claim)" = null ] || fail "guarded read took a claim"
  ok "arm read" --store "$store" arm "$second" --rev "$(rev "$second")" --prompt "$prompt_file"
  echo intruder >"$repo/src/intruder.txt"
  ok "stop read" --store "$store" observe "$second" stopped --rev "$(rev "$second")" --evidence owner-attested --attested-by t
  ok "inspect read" --store "$store" inspect "$second" --rev "$(rev "$second")"
  [ "$(field "$second" '.artifact.target_at_arm != .artifact.target_after')" = true ] || fail "target change not recorded"
  [ "$(field "$second" '.artifact.out_of_scope | index("src/intruder.txt") != null')" = true ] || fail "read write not reported"
  rm "$repo/src/intruder.txt"
  pass "reads take the claim unless a card-verified guard applies; a guarded read's write is reported (F24)"

  # depth guard
  local code=0
  PASSDOWN_ATTEMPT="$first" "$helper" --store "$store" new --task-ref docs/plan.md#1.2 --planner-repo "$repo" --kind write \
    --tier external --reason-code quota --reason t --executor fake --host test --place-repo "$repo" \
    --isolation current-checkout >/dev/null 2>&1 || code=$?
  [ "$code" = 6 ] || fail "depth guard: expected exit 6, got $code"
  pass "depth guard refuses external dispatch from inside an attempt (F20)"

  # profiles: loc keys only
  local wt="$scratch/worktrees" p1 p2
  mkdir -p "$wt"
  ok "reject first" --store "$store" verdict "$first" reject --rev "$(rev "$first")" --reason-code worker_failed --reason t
  [ "$(field "$first" .claim.state)" = released ] || fail "non-holding rejection kept the claim"
  run 6 "profile with a global key" --store "$store" new --task-ref docs/plan.md#1.1 --planner-repo "$repo" --kind write \
    --tier external --reason-code quota --reason t --executor fake --host test --place-repo "$repo" \
    --isolation worktree --worktree-dir "$wt" --profile docs-only --profile-keys loc,port:5432
  [ -z "$(ls "$repo/.git/passdown/claims/loc" 2>/dev/null)" ] && [ ! -f "$repo/.git/passdown/claims/repo.json" ] ||
    fail "a rejected profile wrote a claim"
  ok "profile attempt 1" --store "$store" new --task-ref docs/plan.md#1.1 --planner-repo "$repo" --kind write \
    --tier external --reason-code quota --reason t --executor fake --host test --place-repo "$repo" \
    --isolation worktree --worktree-dir "$wt" --profile docs-only
  p1="$out"
  ok "profile attempt 2" --store "$store" new --task-ref docs/plan.md#1.2 --planner-repo "$repo" --kind write \
    --tier external --reason-code quota --reason t --executor fake --host test --place-repo "$repo" \
    --isolation worktree --worktree-dir "$wt" --profile docs-only
  p2="$out"
  [ "$(field "$p1" .claim.key)" != "$(field "$p2" .claim.key)" ] || fail "two worktrees share a loc key"
  run 6 "profile-less writer while loc keys are held" --store "$store" new --task-ref docs/plan.md#1.2 --planner-repo "$repo" \
    --kind write --tier external --reason-code quota --reason t --executor fake --host test --place-repo "$repo" --isolation current-checkout
  ok "abandon p1" --store "$store" abandon "$p1" --rev "$(rev "$p1")"
  ok "abandon p2" --store "$store" abandon "$p2" --rev "$(rev "$p2")"
  pass "profiles take disjoint loc: keys, never a global key, and block the exclusive repo key (F26)"

  # two planners (separate stores), one target
  local p1repo="$scratch/planner1" p2repo="$scratch/planner2" s1 s2
  new_repo "$p1repo"
  new_repo "$p2repo"
  s1="$p1repo/.git/passdown/attempts"
  s2="$p2repo/.git/passdown/attempts"
  ok "planner 1 targets the repo" --store "$s1" new --task-ref docs/plan.md#1.1 --planner-repo "$p1repo" --kind write \
    --tier external --reason-code quota --reason t --executor fake --host test --place-repo "$repo" --isolation current-checkout
  first="$out"
  run 6 "planner 2 targets the same repo" --store "$s2" new --task-ref docs/plan.md#1.1 --planner-repo "$p2repo" --kind write \
    --tier external --reason-code quota --reason t --executor fake --host test --place-repo "$repo" --isolation current-checkout
  printf '%s' "$err" | grep -q "$s1" || fail "refusal does not name the other planner's store: $err"
  "$helper" --store "$s2" claims --repo "$repo" | grep -q "$first" || fail "claims does not show the foreign claim"
  store="$s1"
  ok "abandon" --store "$s1" abandon "$first" --rev "$(rev "$first")"
  pass "a claim lives with the target: a second planner is refused and sees the holder (F21)"

  # abandon with writes needs attestation
  store="$repo/.git/passdown/attempts"
  new_write "$repo"
  echo stray >"$repo/src/stray.txt"
  run 3 "abandon with writes" --store "$store" abandon "$id" --rev "$(rev "$id")"
  ok "abandon attested" --store "$store" abandon "$id" --rev "$(rev "$id")" --attested-by owner
  [ "$(field "$id" .execution.stop_evidence)" = owner-attested ] || fail "attested abandon evidence"
  rm "$repo/src/stray.txt"
  pass "abandon refuses when the location has writes unless the owner attests (C1 -> C2)"
}

group_chains() {
  local repo="$scratch/chains" o r s c art
  new_repo "$repo"
  store="$repo/.git/passdown/attempts"

  # F4: malformed result, one no-write re-emit, acceptance on R with O's artifact
  new_write "$repo"
  o="$id"
  drive "$o" "echo hello > '$repo/src/hello.txt'"
  run 4 "malformed result" --store "$store" result "$o" --rev "$(rev "$o")" --payload "$(result_payload "$o" malformed)"
  [ "$(field "$o" '.result.diagnostics | join(",")')" = parse ] || fail "diagnostics: $(field "$o" .result.diagnostics)"
  ok "inspect O" --store "$store" inspect "$o" --rev "$(rev "$o")"
  art="$(field "$o" .artifact.digest)"
  run 6 "re-emit before O is rejected" --store "$store" new --task-ref docs/plan.md#1.1 --kind reemit --tier external \
    --reason-code quota --reason t --executor fake --card fake@1 --host test --continues "$o"
  ok "reject O" --store "$store" verdict "$o" reject --rev "$(rev "$o")" --reason-code invalid_result --reason "parse"
  [ "$(field "$o" .claim.state)" = held ] || fail "invalid_result released the claim"
  ok "new R" --store "$store" new --task-ref docs/plan.md#1.1 --kind reemit --tier external \
    --reason-code quota --reason t --executor fake --card fake@1 --host test --continues "$o"
  r="$out"
  [ "$(field "$o" .claim.state)/$(field "$o" .claim.transferred_to)" = "transferred/$r" ] || fail "claim not transferred to R"
  [ "$(field "$r" .artifact.expected)" = "$art" ] || fail "R.expected is not O's artifact"
  run 6 "another writer while R holds the claim" --store "$store" new --task-ref docs/plan.md#1.2 --planner-repo "$repo" --kind write --tier external \
    --reason-code quota --reason t --executor fake --host test --place-repo "$repo" --isolation current-checkout
  drive "$r" "true"
  ok "R result" --store "$store" result "$r" --rev "$(rev "$r")" --payload "$(result_payload "$r" submitted)"
  ok "inspect R" --store "$store" inspect "$r" --rev "$(rev "$r")"
  [ "$(field "$r" .artifact.at_arm)" = "$art" ] && [ "$(field "$r" .artifact.digest)" = "$art" ] ||
    fail "R's chain artifact is not O's artifact"
  ok "accept R" --store "$store" verdict "$r" accept --rev "$(rev "$r")" --check "t=0:$check_ok"
  tick_plan "$repo" 1.1 "$r"
  ok "projected R" --store "$store" projected "$r" --rev "$(rev "$r")" --plan "$repo/docs/plan.md"
  [ ! -f "$repo/.git/passdown/claims/repo.json" ] || fail "claim survives projected R"
  run 6 "second re-emit in the chain" --store "$store" new --task-ref docs/plan.md#1.1 --kind reemit --tier external \
    --reason-code quota --reason t --executor fake --host test --continues "$o"
  pass "re-emit: O rejected first, claim transferred, R accepted on O's artifact, one re-emit per chain (F4)"
  git -C "$repo" checkout -q docs/plan.md
  rm -f "$repo/src/hello.txt"

  # F5: re-emit that writes, then salvage by transfer
  new_write "$repo"
  o="$id"
  drive "$o" "echo hello > '$repo/src/hello.txt'"
  ok "inspect O" --store "$store" inspect "$o" --rev "$(rev "$o")"
  ok "reject O" --store "$store" verdict "$o" reject --rev "$(rev "$o")" --reason-code invalid_result --reason "no result"
  ok "new R" --store "$store" new --task-ref docs/plan.md#1.1 --kind reemit --tier external \
    --reason-code quota --reason t --executor fake --card fake@1 --host test --continues "$o"
  r="$out"
  drive "$r" "echo more >> '$repo/src/hello.txt'"
  ok "inspect R" --store "$store" inspect "$r" --rev "$(rev "$r")"
  [ "$(field "$r" '.artifact.digest != .artifact.expected')" = true ] || fail "R's write not visible"
  ok "reject R" --store "$store" verdict "$r" reject --rev "$(rev "$r")" --reason-code reemit_wrote --reason "wrote"
  [ "$(field "$r" .claim.state)" = held ] || fail "reemit_wrote released the claim"
  ok "salvage" --store "$store" new --task-ref docs/plan.md#1.1 --kind salvage --tier current \
    --reason-code host-work --reason "host salvages" --executor host --host test --continues "$r"
  s="$out"
  [ "$(field "$s" .claim.state)" = held ] && [ "$(field "$r" .claim.transferred_to)" = "$s" ] || fail "salvage did not receive the claim"
  ok "abandon salvage" --store "$store" abandon "$s" --rev "$(rev "$s")" --attested-by host
  pass "a writing re-emit is rejected reemit_wrote and salvage takes its claim by transfer (F5)"
  rm -f "$repo/src/hello.txt"

  # F8: needs_input -> continuation with the answer, accepted on C
  new_write "$repo"
  o="$id"
  drive "$o" "true"
  ok "result" --store "$store" result "$o" --rev "$(rev "$o")" --payload "$(result_payload "$o" needs_input)"
  ok "inspect" --store "$store" inspect "$o" --rev "$(rev "$o")"
  ok "reject needs_input" --store "$store" verdict "$o" reject --rev "$(rev "$o")" --reason-code needs_input --reason "which"
  echo "say hello" >"$scratch/answer.md"
  ok "continuation" --store "$store" new --task-ref docs/plan.md#1.1 --kind write --tier external --reason-code quota \
    --reason t --executor fake --card fake@1 --host test --continues "$o" --answer "$scratch/answer.md"
  c="$out"
  [ "$(field "$c" .chain_root)" = "$o" ] || fail "chain root"
  [ "$(field "$c" '.task.inputs | map(.path | endswith("answer.md")) | any')" = true ] || fail "answer not an input"
  "$helper" --store "$store" list --unresolved | grep "$c" | grep -q C10 || fail "continuation not C10"
  drive "$c" "echo hello > '$repo/src/hello.txt'"
  ok "result C" --store "$store" result "$c" --rev "$(rev "$c")" --payload "$(result_payload "$c" submitted)"
  ok "inspect C" --store "$store" inspect "$c" --rev "$(rev "$c")"
  ok "accept C" --store "$store" verdict "$c" accept --rev "$(rev "$c")" --check "t=0:$check_ok"
  pass "needs_input continues in a new attempt with the answer as input, accepted on C (F8)"
}

group_crash() {
  # F23: kill the helper after every claim sub-step, then check that the
  # claim file names at most one attempt, only that attempt can arm, and the
  # next claim operation repairs the projections.
  local point repo code ids holder a named
  for point in acquire:after-receipt acquire:after-claim-file \
    transfer:after-successor transfer:after-claim-file transfer:after-successor-held \
    release:after-history release:after-claim-removed; do
    repo="$scratch/crash-${point//:/-}"
    new_repo "$repo"
    store="$repo/.git/passdown/attempts"
    case "$point" in
      acquire:*)
        code=0
        (PASSDOWN_TEST_CRASH_AT="$point" "$helper" --store "$store" new --task-ref docs/plan.md#1.1 --planner-repo "$repo" \
          --kind write --tier external --reason-code quota --reason t --executor fake --host test --place-repo "$repo" \
          --isolation current-checkout; exit $?) >/dev/null 2>&1 || code=$?
        ;;
      transfer:*)
        new_write "$repo"
        drive "$id" "true"
        ok "reject" --store "$store" verdict "$id" reject --rev "$(rev "$id")" --reason-code invalid_result --reason t
        code=0
        (PASSDOWN_TEST_CRASH_AT="$point" "$helper" --store "$store" new --task-ref docs/plan.md#1.1 --kind salvage \
          --tier current --reason-code host-work --reason t --executor host --host test --continues "$id"; exit $?) >/dev/null 2>&1 || code=$?
        ;;
      release:*)
        new_write "$repo"
        code=0
        (PASSDOWN_TEST_CRASH_AT="$point" "$helper" --store "$store" abandon "$id" --rev "$(rev "$id")"; exit $?) >/dev/null 2>&1 || code=$?
        ;;
    esac
    [ "$code" = 137 ] || fail "$point: helper was not killed at the crash point (exit $code)"
    named="$(jq -r .holder "$repo/.git/passdown/claims/repo.json" 2>/dev/null || true)"
    ids="$(cd "$store" && ls -d pd-* 2>/dev/null || true)"
    for a in $ids; do
      [ -f "$store/$a/receipt.json" ] || continue
      [ "$(jq -r .execution.observation "$store/$a/receipt.json")" = prepared ] || continue
      code=0
      "$helper" --store "$store" arm "$a" --rev "$(rev "$a")" --prompt "$prompt_file" >/dev/null 2>&1 || code=$?
      if [ "$a" = "$named" ]; then
        [ "$code" = 0 ] || fail "$point: the named holder $a cannot arm (exit $code)"
      else
        [ "$code" = 6 ] || fail "$point: $a is not named by the claim file but arm exited $code"
      fi
    done
    # The arm calls above took the mutex and repaired projections; every
    # receipt now agrees with the claim file.
    run 0 "$point: validate after repair" --store "$store" validate --all
    for a in $ids; do
      [ -f "$store/$a/receipt.json" ] || continue
      holder="$(jq -r '.claim.state // ""' "$store/$a/receipt.json")"
      if [ "$a" = "$named" ]; then
        [ "$holder" = held ] || fail "$point: named $a projects $holder"
      else
        [ "$holder" != held ] && [ "$holder" != requested ] || fail "$point: unnamed $a projects $holder"
      fi
    done
  done
  pass "crash after every acquire/transfer/release sub-step: one named holder, only it arms, projections repaired (F23)"
}

group_races() {
  # F19: N parallel `new` against one target; some rounds kill a helper
  # mid-flight. Exactly one holder per round; the others exit 6.
  local repo="$scratch/race" rounds="${PASSDOWN_STRESS_ROUNDS:-10}" n=8 round i pids codes holders named killer
  new_repo "$repo"
  store="$repo/.git/passdown/attempts"
  for round in $(seq 1 "$rounds"); do
    pids=()
    for i in $(seq 1 "$n"); do
      "$helper" --store "$store" new --task-ref docs/plan.md#1.1 --planner-repo "$repo" --kind write --tier external \
        --reason-code quota --reason t --executor fake --host test --place-repo "$repo" --isolation current-checkout \
        >"$scratch/race.$i.out" 2>"$scratch/race.$i.err" &
      pids+=("$!")
    done
    killer=""
    if [ $((round % 3)) = 0 ]; then
      killer="${pids[$((RANDOM % n))]}"
      kill -KILL "$killer" 2>/dev/null || true
    fi
    codes=""
    for i in $(seq 0 $((n - 1))); do
      if wait "${pids[$i]}"; then codes="$codes 0"; else codes="$codes $?"; fi
    done
    named="$(jq -r .holder "$repo/.git/passdown/claims/repo.json" 2>/dev/null || true)"
    holders="$(for f in "$store"/pd-*/receipt.json; do [ -f "$f" ] && jq -r 'select(.claim.state == "held") | .id' "$f"; done | wc -l | tr -d ' ')"
    [ "$holders" -le 1 ] || fail "round $round: $holders receipts project a held claim"
    case " $codes " in *" 0 "*) ;; *) [ -n "$killer" ] || fail "round $round: nobody obtained the claim ($codes)" ;; esac
    [ "$(tr ' ' '\n' <<<"$codes" | grep -c '^0$')" -le 1 ] || fail "round $round: more than one new succeeded ($codes)"
    for i in $codes; do
      case "$i" in 0 | 6 | 137) ;; *) fail "round $round: unexpected exit $i ($codes)" ;; esac
    done
    # Tidy up as a host would: abandon the prepared holder (C1).
    if [ -n "$named" ]; then
      ok "round $round abandon" --store "$store" abandon "$named" --rev "$(rev "$named")"
    fi
    ok "round $round validate" --store "$store" validate --all
    [ ! -f "$repo/.git/passdown/claims/repo.json" ] || fail "round $round: claim left behind"
  done
  pass "concurrent new: at most one holder per round over $rounds rounds of $n, killed helpers leave no second holder (F19)"

  # F25: two mutations planned against the same rev; one wins, one exits 5.
  new_write "$repo"
  ok "arm" --store "$store" arm "$id" --rev "$(rev "$id")" --prompt "$prompt_file"
  spawn "sleep 30"
  ok "running" --store "$store" observe "$id" running --rev "$(rev "$id")" --pid "$wpid" --pid-started "$wstart" --pgid "$wpid"
  local r c1=0 c2=0 k
  for k in 1 2 3 4 5; do
    r="$(rev "$id")"
    "$helper" --store "$store" cancel "$id" --rev "$r" --method INT >/dev/null 2>&1 &
    local a=$!
    "$helper" --store "$store" observe "$id" unknown --rev "$r" --note race >/dev/null 2>&1 &
    local b=$!
    c1=0
    c2=0
    wait "$a" || c1=$?
    wait "$b" || c2=$?
    case "$c1/$c2" in
      0/5 | 5/0) ;;
      3/5 | 5/3 | 3/0 | 0/3) ;; # cancel refuses a second request after the first round
      *) fail "CAS race round $k: exits $c1/$c2" ;;
    esac
    [ "$c1" = 0 ] || [ "$c2" = 0 ] || fail "CAS race round $k: nobody won ($c1/$c2)"
  done
  ok "validate after races" --store "$store" validate "$id"
  jq -e '[.transitions[].rev] as $v | $v == ($v | sort) and ($v | unique | length) == .rev' "$store/$id/receipt.json" >/dev/null ||
    fail "transition log lost a write"
  kill -KILL "-$wpid" 2>/dev/null || true
  pass "concurrent mutations from one rev: exactly one wins, the other exits 5, no lost write (F25)"
}

group_digests() {
  # Golden digests: stable across runs and platforms.
  local repo="$scratch/golden"
  new_repo "$repo"
  store="$repo/.git/passdown/attempts"
  local td
  td="$("$helper" digest task --plan "$repo/docs/plan.md" --task 1.1)"
  [ "$td" = "$(cat "$fixtures/golden/task-1.1.digest")" ] || fail "task digest $td differs from the golden value"
  pass "task digest matches the golden value"

  new_write "$repo"
  ok "arm" --store "$store" arm "$id" --rev "$(rev "$id")" --prompt "$prompt_file"
  printf 'hello\n' >"$repo/src/hello.txt"
  printf 'changed\n' >"$repo/src/base.txt"
  mkdir -p "$repo/src/deep"
  printf 'z\n' >"$repo/src/deep/z.txt"
  printf 'ignored\n' >"$repo/ignored.log"
  printf '*.log\n' >"$repo/.gitignore"
  git -C "$repo" add .gitignore
  ok "digest artifact" --store "$store" digest artifact "$id"
  [ "$out" = "$(cat "$fixtures/golden/artifact.digest")" ] || fail "artifact digest $out differs from the golden value"
  pass "artifact digest matches the golden value (tracked, staged, untracked; ignored excluded)"

  # Pre-existing dirty paths are not the attempt's, unless it changes them.
  local repo2="$scratch/golden2"
  new_repo "$repo2"
  store="$repo2/.git/passdown/attempts"
  printf 'user edit\n' >"$repo2/src/base.txt"
  new_write "$repo2"
  ok "arm" --store "$store" arm "$id" --rev "$(rev "$id")" --prompt "$prompt_file"
  ok "digest" --store "$store" --json digest artifact "$id"
  [ "$(jq .changed <<<"$out")" = 0 ] || fail "a pre-existing user edit counted as the attempt's"
  printf 'worker edit\n' >"$repo2/src/base.txt"
  ok "digest" --store "$store" --json digest artifact "$id"
  [ "$(jq -c .overlaps_baseline <<<"$out")" = '["src/base.txt"]' ] || fail "overlap with a user edit not flagged: $out"
  pass "baseline dirt is excluded unless the attempt changes it (overlaps_baseline)"
}

group_plan_freshness() {
  local repo="$scratch/plan-freshness"
  new_repo "$repo"
  store="$repo/.git/passdown/attempts"
  new_write "$repo"
  drive "$id" "echo hello > '$repo/src/hello.txt'"
  ok result --store "$store" result "$id" --rev "$(rev "$id")" --payload "$(result_payload "$id" submitted)"
  ok inspect --store "$store" inspect "$id" --rev "$(rev "$id")"
  tick_plan "$repo" 1.1 "$id"
  run 3 "checkbox changed after inspection" --store "$store" verdict "$id" accept --rev "$(rev "$id")" --check "t=0:$check_ok"
  [ "$(field "$id" .verdict.acceptance)" = pending ] || fail "stale plan inspection accepted"
  [ "$(field "$id" .claim.state)" = held ] || fail "claim released on stale plan inspection"
  git -C "$repo" checkout -q -- docs/plan.md
  ok "accept after restoring plan" --store "$store" verdict "$id" accept --rev "$(rev "$id")" --check "t=0:$check_ok"
  pass "accept rechecks plan integrity after the last inspection"
}

group_symlinks() {
  local repo="$scratch/symlinks" before after expected target
  new_repo "$repo"
  printf 'same bytes\n' >"$repo/src/a"
  printf 'same bytes\n' >"$repo/src/b"
  git -C "$repo" add src/a src/b
  git -C "$repo" commit -q -m targets
  store="$repo/.git/passdown/attempts"
  new_write "$repo"
  drive "$id" "ln -s a '$repo/src/link'"
  ok result --store "$store" result "$id" --rev "$(rev "$id")" --payload "$(result_payload "$id" submitted)"
  ok inspect --store "$store" inspect "$id" --rev "$(rev "$id")"
  before="$(field "$id" .artifact.digest)"
  rm "$repo/src/link"
  ln -s b "$repo/src/link"
  after="$("$helper" --store "$store" digest artifact "$id")"
  [ "$before" != "$after" ] || fail "symlink target changed but artifact digest did not"
  run 3 "retargeted symlink after inspection" --store "$store" verdict "$id" accept --rev "$(rev "$id")" --check "t=0:$check_ok"
  # A dangling link is a valid Git artifact; preserve trailing newlines in
  # its target and hash the link bytes, never the referent's contents.
  rm "$repo/src/link"
  target=$'missing\n'
  ln -s "$target" "$repo/src/link"
  expected="$(printf '%s' "$target" | git hash-object --stdin)"
  ok "digest dangling symlink" --store "$store" --json digest artifact "$id"
  [ "$(jq -r '.entries[] | select(.path == "src/link") | .hash' <<<"$out")" = "$expected" ] || fail "symlink bytes were not preserved"
  pass "artifact hashes symlink bytes and rejects retargeting after inspection"
}

group_list() {
  local repo="$scratch/list" a b
  new_repo "$repo"
  store="$repo/.git/passdown/attempts"
  new_write "$repo"
  a="$id"
  "$helper" --store "$store" list --unresolved | grep "$a" | grep -q C1 || fail "prepared is not C1"
  ok "arm" --store "$store" arm "$a" --rev "$(rev "$a")" --prompt "$prompt_file"
  "$helper" --store "$store" list --unresolved | grep "$a" | grep -q C2 || fail "armed without handle is not C2"
  spawn "sleep 30"
  ok "running" --store "$store" observe "$a" running --rev "$(rev "$a")" --pid "$wpid" --pid-started "$wstart" --pgid "$wpid"
  "$helper" --store "$store" list --unresolved | grep "$a" | grep -q C3 || fail "running is not C3"
  ok "cancel" --store "$store" cancel "$a" --rev "$(rev "$a")" --method "INT pgroup"
  "$helper" --store "$store" list --unresolved | grep "$a" | grep -q C8 || fail "cancel requested is not C8"
  kill -KILL "-$wpid"
  wait "$wpid" 2>/dev/null || true
  ok "stop" --store "$store" observe "$a" stopped --rev "$(rev "$a")" --evidence owner-attested --attested-by t
  "$helper" --store "$store" list --unresolved | grep "$a" | grep -q C5 || fail "stopped without result is not C5"
  ok "result" --store "$store" result "$a" --rev "$(rev "$a")" --payload "$(result_payload "$a" submitted)"
  "$helper" --store "$store" list --unresolved | grep "$a" | grep -q C4 || fail "stopped with result is not C4"
  perl -pi -e 's/Add the greeting/Add a greeting/' "$repo/docs/plan.md"
  "$helper" --store "$store" list --unresolved | grep "$a" | grep -q C7 || fail "edited task is not C7"
  git -C "$repo" checkout -q docs/plan.md
  ok "inspect" --store "$store" inspect "$a" --rev "$(rev "$a")"
  ok "accept" --store "$store" verdict "$a" accept --rev "$(rev "$a")" --check "t=0:$check_ok"
  "$helper" --store "$store" list --unresolved | grep "$a" | grep -q C6 || fail "accepted, unprojected is not C6"
  ok "json list" --store "$store" --json list --unresolved
  [ "$(jq -r '.[0].verdict' <<<"$out")" = accepted ] || fail "json list"
  pass "list classifies C1, C2, C3, C8, C5, C4, C7 and C6"

  # Inactivity is measured from the last transition, not from creation (C9).
  local idle="$scratch/list-idle"
  new_repo "$idle"
  store="$idle/.git/passdown/attempts"
  new_write "$idle"
  b="$id"
  sleep 2
  ok "arm later" --store "$store" arm "$b" --rev "$(rev "$b")" --prompt "$prompt_file"
  ok "json list" --store "$store" --json list --unresolved
  [ "$(jq -r --arg b "$b" '.[] | select(.id == $b) | (.age_seconds >= 2 and .idle_seconds <= 1)' <<<"$out")" = true ] ||
    fail "idle_seconds does not follow the last transition: $out"
  # An absent store is reported, not mistaken for a verified empty one.
  ok "list without a store" --store "$scratch/list-no-store/attempts" --json list --unresolved
  [ "$out" = "[]" ] && grep -q "absent, not empty" <<<"$err" || fail "absent store not reported: $err"
  store="$repo/.git/passdown/attempts"
  pass "list measures inactivity from the last transition and reports an absent store"

  # validate catches a projection that disagrees with the claim file.
  b="$a"
  jq '.claim.state = "held"' "$store/$b/receipt.json" >"$scratch/r.json"
  cp "$store/$b/receipt.json" "$scratch/orig.json"
  rm "$repo/.git/passdown/claims/repo.json"
  run 4 "validate a held projection without claim file" --store "$store" validate "$b"
  printf '%s' "$out" | grep -q held-claim-not-in-claim-file || fail "validate did not report it: $out"
  pass "validate reports a held projection the claim file does not back"
}

group_cards() {
  local dir="$scratch/cards" good bad
  mkdir -p "$dir"
  good="$dir/demo.md"
  cat >"$good" <<'CARD'
---
card: demo
card_version: 1
measured:
  date: 2026-09-25
  host_os: test
  cli_version: 1.0.0
  engine: null
  by: tests/attempt.sh
  evidence: docs/evidence/demo/run.log
capabilities:
  headless: verified
  descendants_may_outlive: unverified
invocation:
  headless: 'demo --print "<prompt>"'
  output_capture: stdout
  result_extraction: last line that is a JSON object
  resume: null
  cancel: { signal: INT, target: pgroup, grace_seconds: 5, then: TERM }
stop:
  containment: [pgroup]
  settle_seconds: 3
permissions:
  mechanism: none needed
environment_constraints: []
discovery_hint: pgrep -fl demo
toolchain_check: null
---
A test card.
CARD
  ok "a complete card" validate --file "$good" --as card
  # Each broken variant must be refused with the rule it breaks.
  expect_card() { # <sed expression> <expected message>
    bad="$dir/bad/demo.md"
    mkdir -p "$dir/bad"
    sed "$1" "$good" >"$bad"
    run 4 "card: $2" validate --file "$bad" --as card
    grep -q -- "$2" <<<"$out" || fail "card: expected '$2', got: $out"
  }
  expect_card '/^  headless: .demo/d' "invocation.headless is required"
  expect_card '/result_extraction:/d' "invocation.result_extraction is required"
  expect_card 's/settle_seconds: 3/settle_seconds: 0/' "settle_seconds must be above zero"
  expect_card 's/headless: verified/headless: yes/' "is not verified, unsupported or unverified"
  expect_card 's/  headless: verified/  headless: verified\n  telepathy: verified/' "unknown-capability"
  expect_card 's#evidence: docs/evidence/demo/run.log#evidence: none#' "needs recorded evidence"
  expect_card 's/resume: null/resume: demo --resume <id>/' "only with resume_session verified"
  expect_card 's/^card: demo/card: other/' "does not match the file name"
  expect_card 's/date: 2026-09-25/date: 2026-09-2x/' "must be YYYY-MM-DD"
  mkdir -p "$dir/clash"
  sed 's/^card: demo/card: claude/' "$good" >"$dir/clash/claude.md"
  run 4 "card: a name that is an agent instruction file" validate --file "$dir/clash/claude.md" --as card
  grep -q "agent instruction file" <<<"$out" || fail "claude.md was not refused: $out"
  # A measured no-detach card may keep a zero settle window.
  sed -e 's/descendants_may_outlive: unverified/descendants_may_outlive: unsupported/' \
    -e 's/settle_seconds: 3/settle_seconds: 0/' "$good" >"$dir/bad/demo.md"
  ok "measured no-detach with zero settle" validate --file "$dir/bad/demo.md" --as card
  pass "validate --as card enforces the card format, evidence and launch eligibility"
}

groups="conformance lifecycle transitions acceptance claims chains crash races digests plan_freshness symlinks list cards"
selected="${*:-$groups}"
for g in $selected; do
  case " $groups " in *" $g "*) "group_$g" ;; *) fail "unknown group $g" ;; esac
done
echo "1..$tests_run"
