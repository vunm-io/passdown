#!/usr/bin/env bash
# Contract tests for the v0.5 protocol schemas (schemas/protocol/) against the
# fixture corpus in tests/fixtures/attempt/. A pinned JSON Schema validator
# (ajv, draft 2020-12, dev-only) must accept every valid/ fixture, reject every
# invalid/ fixture at the JSON pointer MANIFEST.tsv names, and accept every
# semantic-invalid/ fixture, which only the helper's `validate` rejects (S2).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
schemas="$repo_root/schemas/protocol"
fixtures="$repo_root/tests/fixtures/attempt"
manifest="$fixtures/MANIFEST.tsv"
ajv_version="8.17.1"
tests_run=0

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { tests_run=$((tests_run + 1)); echo "ok $tests_run - $*"; }

command -v node >/dev/null 2>&1 || fail "node is required for the contract tests"
command -v jq >/dev/null 2>&1 || fail "jq is required for the contract tests"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# ajv is a dev-only dependency: install it once into PASSDOWN_AJV_DIR (cached)
# or a scratch prefix, never into the repository.
ajv_dir="${PASSDOWN_AJV_DIR:-$scratch/ajv}"
installed="$(jq -r '.version // empty' "$ajv_dir/node_modules/ajv/package.json" 2>/dev/null || true)"
if [ "$installed" != "$ajv_version" ]; then
  mkdir -p "$ajv_dir"
  npm install --silent --no-save --no-package-lock --no-audit --no-fund \
    --prefix "$ajv_dir" "ajv@$ajv_version" >/dev/null ||
    fail "could not install ajv@$ajv_version"
fi

for schema in receipt result claim; do
  file="$schemas/$schema.v1.schema.json"
  jq -e --arg id "passdown.$schema/v1" \
    '.["$schema"] == "https://json-schema.org/draft/2020-12/schema" and .title == $id' \
    "$file" >/dev/null || fail "$schema schema declares draft 2020-12 and title passdown.$schema/v1"
  pass "$schema schema declares draft 2020-12 and its protocol id"
done

# One validator run per schema over its whole corpus; results land in a TSV:
# <relative fixture path> <valid|invalid|parse> <comma-separated instancePaths>
verdicts="$scratch/verdicts.tsv"
: >"$verdicts"
for kind in receipts results claims; do
  schema="${kind%s}"
  files=()
  for dir in valid invalid semantic-invalid; do
    for f in "$fixtures/$kind/$dir"/*.json; do
      [ -e "$f" ] && files+=("$f")
    done
  done
  [ "${#files[@]}" -gt 0 ] || fail "no $kind fixtures found"
  NODE_PATH="$ajv_dir/node_modules" node "$repo_root/tests/contracts/validate.cjs" \
    "$schemas/$schema.v1.schema.json" "${files[@]}" >>"$verdicts" ||
    fail "$schema schema does not compile in ajv strict mode"
  pass "$schema schema compiles in ajv strict mode and ran over ${#files[@]} fixtures"
done
sed -i.bak "s#^$fixtures/##" "$verdicts" && rm -f "$verdicts.bak"

verdict_of() { awk -F '\t' -v f="$1" '$1 == f { print $2 }' "$verdicts"; }
paths_of() { awk -F '\t' -v f="$1" '$1 == f { print $3 }' "$verdicts"; }

# valid/ fixtures are accepted
bad=""
while IFS=$'\t' read -r file verdict paths; do
  case "$file" in */valid/*) [ "$verdict" = valid ] || bad="$bad $file($paths)" ;; esac
done <"$verdicts"
[ -z "$bad" ] || fail "valid fixtures rejected:$bad"
pass "every valid/ fixture is accepted"

# Every invalid/ and semantic-invalid/ fixture is listed in the manifest, and
# every manifest entry exists.
listed="$(grep -v '^#' "$manifest" | cut -f1 | sort)"
present="$(awk -F '\t' '$1 !~ /\/valid\// { print $1 }' "$verdicts" | sort)"
[ "$listed" = "$present" ] ||
  fail "MANIFEST.tsv and the invalid fixtures disagree: $(diff <(echo "$listed") <(echo "$present") | grep '^[<>]' | tr '\n' ' ')"
pass "MANIFEST.tsv lists exactly the invalid and semantic-invalid fixtures"

# invalid/ fixtures are rejected, and for the intended reason: the manifest's
# JSON pointer is among the error locations. semantic-invalid/ fixtures are
# schema-valid by construction; their rejection is the helper's job.
bad=""
while IFS=$'\t' read -r file base pointer; do
  [ -n "$file" ] || continue
  case "$file" in \#*) continue ;; esac
  [ -f "$fixtures/${file%%/*}/valid/$base.json" ] || bad="$bad $file(no base $base)"
  verdict="$(verdict_of "$file")"
  paths="$(paths_of "$file")"
  case "$pointer" in
    -) [ "$verdict" = valid ] || bad="$bad $file(expected schema-valid, got $verdict at $paths)" ;;
    '!parse') [ "$verdict" = parse ] || bad="$bad $file(expected parse failure, got $verdict)" ;;
    *)
      if [ "$verdict" != invalid ]; then
        bad="$bad $file(expected invalid at '$pointer', got $verdict)"
      elif ! printf ',%s,' "$paths" | grep -Fq ",$pointer,"; then
        bad="$bad $file(expected error at '$pointer', got '$paths')"
      fi
      ;;
  esac
done <"$manifest"
[ -z "$bad" ] || fail "invalid fixtures not rejected as intended:$bad"
pass "every invalid/ fixture is rejected at its manifest pointer"
pass "every semantic-invalid/ fixture is schema-valid (left to passdown-attempt validate)"

# Coverage: every invalid combination of design section 8.5 and every result
# validation rule of section 7 has a fixture.
require_fixture() {
  local pattern="$1" description="$2"
  compgen -G "$fixtures/$pattern" >/dev/null || fail "no fixture for: $description ($pattern)"
  pass "fixture covers: $description"
}
require_fixture "receipts/invalid/accepted-while-prepared.json" "8.5 prepared + accepted"
require_fixture "receipts/invalid/accepted-while-unknown.json" "8.5 unknown + accepted"
require_fixture "receipts/invalid/accepted-while-running.json" "8.5 running + accepted"
require_fixture "receipts/invalid/stop-evidence-unsafe--bare-exit.json" "8.5 stopped with bare exit evidence"
require_fixture "receipts/invalid/stop-evidence-unsafe--provider-event.json" "8.5 stopped with provider-event evidence"
require_fixture "receipts/invalid/accepted-without-reconciled.json" "8.5 accepted without reconciled_at"
require_fixture "receipts/invalid/accepted-without-artifact-digest.json" "8.5 accepted without artifact digest"
require_fixture "receipts/invalid/accepted-without-checks.json" "8.5 accepted without a check"
require_fixture "receipts/semantic-invalid/accepted-task-digest-mismatch.json" "8.5 accepted with task_digest != task.digest"
require_fixture "receipts/invalid/ownership-risk-claim-released.json" "8.5 ownership risk without a held claim"
require_fixture "results/invalid/question--needs-input-without-question.json" "8.5 needs_input without question"
require_fixture "results/semantic-invalid/attempt-mismatch--*.json" "8.5 result attempt != receipt id"
for rule in parse schema-version attempt-mismatch disposition question blocker path unknown-member length; do
  require_fixture "results/*invalid/$rule--*.json" "7 result rule '$rule'"
done

# Coverage of valid states: each observation x verdict pair section 8.5 marks
# valid, every stop evidence, claim state, kind and worker disposition.
receipt_facts="$(jq -r '[.execution.observation, .verdict.acceptance] | join("/")' \
  "$fixtures"/receipts/valid/*.json | sort -u | tr '\n' ' ')"
for pair in prepared/pending prepared/rejected unknown/pending unknown/rejected running/pending \
  running/rejected stopped/pending stopped/accepted stopped/rejected; do
  case " $receipt_facts " in *" $pair "*) ;; *) fail "no valid receipt fixture for $pair" ;; esac
done
pass "valid receipts cover every observation/verdict pair section 8.5 allows"

check_values() {
  local filter="$1" description="$2"; shift 2
  local seen
  seen=" $(jq -r "$filter" "$fixtures"/receipts/valid/*.json | sort -u | tr '\n' ' ') "
  for value in "$@"; do
    case "$seen" in *" $value "*) ;; *) fail "no valid receipt fixture with $description = $value" ;; esac
  done
  pass "valid receipts cover every $description"
}
check_values '.execution.stop_evidence // empty' "stop evidence" \
  not-launched exit+scope-empty exit+pgroup-empty owner-attested
check_values '.claim.state // "claim-free"' "claim state" requested held transferred released claim-free
check_values '.kind' "kind" write read reemit salvage
check_values '.result.status' "result status" none valid invalid
check_values 'if .verdict.acceptance == "accepted" then (if .verdict.projected_at then "projected" else "unprojected" end) else empty end' \
  "accepted projection state" projected unprojected
check_values 'if .handle.parent_exited_at then "parent-exited" else empty end' "parent-exit marker" parent-exited

seen=" $(jq -r '.disposition' "$fixtures"/results/valid/*.json | sort -u | tr '\n' ' ') "
for value in submitted needs_input blocked failed; do
  case "$seen" in *" $value "*) ;; *) fail "no valid result fixture with disposition $value" ;; esac
done
pass "valid results cover every worker disposition"

echo "1..$tests_run"
