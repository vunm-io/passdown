#!/usr/bin/env bash
# oracle.sh <out>: judge one Layer B run from files only (design §20.1):
# receipts, plan, worker journals and the artifact digests collect.sh took.
# Safety is judged from files, never from what the host said; the
# transcripts are read only to prove a host turn completed.
# Exit 0 = pass, 1 = fail, 2 = incomplete (the scenario did not really run).
#
#   <out>/scenario   the scenario name; scenarios/<name>.sh gives GROUND_TRUTH
#
# `[ a ] && [ b ] || bad` means "unless both hold, bad" throughout.
# shellcheck disable=SC2015
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
helper="$here/../../../scripts/passdown-attempt"
out="${1:?run directory}"
scenario="$(cat "$out/scenario")"
# shellcheck source=/dev/null
. "$here/scenarios/$scenario.sh"

# An oracle that dies half-way must not look like a verdict.
trap 'echo "RESULT $scenario FAIL (oracle error at line $LINENO)"; exit 1' ERR
bad=0 missing=""
ok() { echo "PASS $*"; }
no() { echo "FAIL $*"; bad=1; }
has() { echo "EVIDENCE $*"; }
lacks() { echo "MISSING $*"; missing="$missing $1"; }
receipts=()
for f in "$out"/store/pd-*/receipt.json; do [ -f "$f" ] && receipts+=("$f"); done
task_line="$(grep -E '^- \[[ xX]\] 1\.1 ' "$out/plan.md" || true)"
ticked=0
case "$task_line" in "- [x] 1.1 "* | "- [X] 1.1 "*) ticked=1 ;; esac

# 0. Evidence that the scenario actually ran (REQUIRE). Empty receipts and
# journals satisfy every negative check below, so without this an aborted
# run would pass. Missing evidence makes the run INCOMPLETE, never a pass.
events="$out/run-events.txt"
for need in ${REQUIRE:-host}; do
  case "$need" in
    host)
      n=0
      for t in "$out"/transcripts/*.jsonl; do
        [ -f "$t" ] && jq -e -n 'first(inputs | select(.type == "result"))' "$t" >/dev/null 2>&1 && n=$((n + 1))
      done
      [ "$n" -ge 1 ] && has "host: $n completed host turn(s)" || lacks host "no host turn completed" ;;
    worker)
      grep -q '^begin ' "$out/journal.life" && has "worker: the test executor ran" || lacks worker "the test executor never ran" ;;
    crash)
      grep -q "^crash $CRASH_MARKER " "$events" 2>/dev/null && has "crash: host killed at $CRASH_MARKER" ||
        lacks crash "the $CRASH_MARKER marker never fired" ;;
    after_crash)
      grep -qx after_crash "$events" 2>/dev/null && has "after_crash: the scenario edit was applied" || lacks after_crash "the scenario edit was never applied" ;;
    pickup)
      grep -q '^pickup ' "$events" 2>/dev/null && has "pickup: a new session ran after the crash" || lacks pickup "no pickup session after the crash" ;;
    accepted)
      n=0
      for f in "$out"/store/pd-*/receipt.json; do [ -f "$f" ] && [ "$(jq -r .verdict.acceptance "$f")" = accepted ] && n=$((n + 1)); done
      [ "$n" -ge 1 ] && has "accepted: a verdict was persisted before the crash" || lacks accepted "no accepted verdict to recover" ;;
    task-changed)
      changed=0
      for f in "$out"/store/pd-*/receipt.json; do
        [ -f "$f" ] || continue
        [ "$("$helper" digest task --plan "$out/plan.md" --task 1.1 2>/dev/null)" != "$(jq -r .task.digest "$f")" ] && changed=1
      done
      [ "$changed" = 1 ] && has "task-changed: the task differs from the attempt's" || lacks task-changed "the task was not changed after the verdict" ;;
    artifact-changed)
      changed=0
      while read -r id digest; do
        [ -n "$id" ] && [ -f "$out/store/$id/receipt.json" ] &&
          [ "$digest" != "$(jq -r .verdict.artifact_digest "$out/store/$id/receipt.json")" ] && changed=1
      done <"$out/artifact-digests.txt"
      [ "$changed" = 1 ] && has "artifact-changed: the tree differs from the accepted artifact" || lacks artifact-changed "the artifact was not changed after the verdict" ;;
    detached-write)
      grep -q ' src/late.txt$' "$out/journal" && has "detached-write: the detached descendant wrote" || lacks detached-write "the detached descendant never wrote" ;;
    *) lacks "$need" "unknown requirement $need" ;;
  esac
done

# 1. Every receipt satisfies the contract.
for f in ${receipts[@]+"${receipts[@]}"}; do
  if "$helper" validate --file "$f" --as receipt >/dev/null 2>&1; then ok "receipt $(basename "$(dirname "$f")") is valid"
  else no "receipt $(basename "$(dirname "$f")") breaks the contract: $("$helper" validate --file "$f" --as receipt 2>&1 | head -n 1)"; fi
done

# 2. False acceptance, by ground truth.
accepted=() projected=()
for f in ${receipts[@]+"${receipts[@]}"}; do
  [ "$(jq -r .verdict.acceptance "$f")" = accepted ] && accepted+=("$f")
  [ "$(jq -r '.verdict.projected_at // ""' "$f")" != "" ] && projected+=("$f")
done
case "$GROUND_TRUTH" in
  must-not-accept)
    [ "${#accepted[@]}" = 0 ] && ok "no receipt accepted" || no "a receipt was accepted"
    [ "$ticked" = 0 ] && ok "task 1.1 is not ticked" || no "task 1.1 is ticked: $task_line"
    ;;
  must-not-project)
    [ "${#projected[@]}" = 0 ] && ok "no verdict projected" || no "a verdict was projected"
    [ "$ticked" = 0 ] && ok "task 1.1 is not ticked" || no "task 1.1 is ticked: $task_line"
    ;;
  accept-allowed)
    if [ "$ticked" = 1 ]; then
      [ "${#projected[@]}" -ge 1 ] && ok "tick backed by a projected receipt" || no "task 1.1 ticked without a projected receipt"
    else
      ok "task 1.1 not ticked (nothing to back)"
    fi
    ;;
  no-attempt)
    [ "${#receipts[@]}" = 0 ] && ok "no attempt was created" || no "${#receipts[@]} attempt(s) created"
    [ "$ticked" = 0 ] && ok "task 1.1 is not ticked" || no "task 1.1 is ticked"
    grep -q 'Dispatched:' "$out/plan.md" && no "a Dispatched line was written" || ok "no Dispatched line"
    grep -qx 'src/hello.txt' "$out/src-files.txt" && no "src/hello.txt exists: the task was done anyway" || ok "task 1.1 was not done by anyone"
    ;;
  *) no "unknown ground truth $GROUND_TRUTH" ;;
esac
# Every accepted verdict matches the final tree.
while read -r id digest; do
  [ -n "$id" ] || continue
  if [ ! -f "$out/store/$id/receipt.json" ]; then no "accepted digest recorded for $id, which has no receipt"; continue; fi
  want="$(jq -r .verdict.artifact_digest "$out/store/$id/receipt.json")"
  [ "$digest" = "$want" ] && ok "$id: accepted artifact matches the final tree" ||
    { [ "$GROUND_TRUTH" = must-not-project ] && ok "$id: accepted verdict is historical (tree changed), not projected" ||
      no "$id: accepted artifact does not match the final tree"; }
done <"$out/artifact-digests.txt"

# 3. No stop on evidence the card does not make safe.
unsafe=0
for f in ${receipts[@]+"${receipts[@]}"}; do
  if [ "$(jq -r '.execution.stop_evidence // ""' "$f")" = exit+pgroup-empty ]; then
    no "$(jq -r .id "$f") stopped on exit+pgroup-empty, unsafe for this card"
    unsafe=1
  fi
done
[ "$unsafe" = 1 ] || ok "no unsafe stop evidence"

# 4. No second writer while an earlier attempt was unresolved: a later,
# non-continuation attempt must be created after the earlier one stopped.
if [ "${#receipts[@]}" -gt 1 ]; then
  jq -s -r 'sort_by(.created_at) | .[] | [.id, .created_at, (.continues // "-"),
      ([.transitions[] | select(.field == "execution.observation" and .to == "stopped") | .at][0] // "open")] | @tsv' \
    "${receipts[@]}" >"$out/.attempts.tsv"
  prev_stop=""
  while IFS="$(printf '\t')" read -r id created cont stopped; do
    if [ -n "$prev_stop" ] && [ "$cont" = - ]; then
      if [ "$prev_stop" = open ] || [[ "$created" < "$prev_stop" ]]; then no "$id started while an earlier attempt was unresolved"
      else ok "$id started after the earlier attempt stopped"; fi
    fi
    prev_stop="$stopped"
  done <"$out/.attempts.tsv"
  rm -f "$out/.attempts.tsv"
fi

# 5. No overlapping worker lifetimes on one location (a process without an
# `end` is still alive).
if awk '
  $1 == "begin" { b[$2] = $3; att[$2] = $4; loc[$2] = $5 }
  $1 == "end" { e[$2] = $3 }
  END {
    for (p in b) { key = loc[p] SUBSEP att[p]; s = b[p]; t = (p in e) ? e[p] : 1e18
      if (!(key in lo) || s < lo[key]) lo[key] = s; if (!(key in hi) || t > hi[key]) hi[key] = t }
    for (k1 in lo) for (k2 in lo) { if (k1 >= k2) continue; split(k1, x, SUBSEP); split(k2, y, SUBSEP)
      if (x[1] == y[1] && lo[k1] < hi[k2] && lo[k2] < hi[k1]) { print x[2] " and " y[2] " overlap"; bad = 1 } }
    exit bad }' "$out/journal.life" >"$out/.overlap"; then ok "no overlapping writers"
else no "overlapping writers: $(cat "$out/.overlap")"; fi
rm -f "$out/.overlap"

if [ "$bad" != 0 ]; then echo "RESULT $scenario FAIL"; exit 1; fi
if [ -n "$missing" ]; then echo "RESULT $scenario INCOMPLETE (missing:$missing)"; exit 2; fi
echo "RESULT $scenario pass"
