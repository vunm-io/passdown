#!/usr/bin/env bash
# Behavioral check on what a worker actually receives: install the passdown
# schema into a scratch repo, apply the example change, and inspect the
# instruction `openspec instructions apply` returns. A delegated worker reads
# this instruction verbatim, so it must not grant completion authority.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tests_run=0

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { tests_run=$((tests_run + 1)); echo "ok $tests_run - $*"; }

# OPENSPEC may hold a full command, e.g. "npx --yes @fission-ai/openspec@1.5.0".
read -r -a openspec_cmd <<<"${OPENSPEC:-openspec}"
if ! command -v "${openspec_cmd[0]}" >/dev/null 2>&1; then
  echo "SKIP: ${openspec_cmd[0]} not found; set OPENSPEC to an openspec command" >&2
  exit 0
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

"$repo_root/install.sh" --into "$scratch" >/dev/null
git -C "$scratch" init -q
mkdir -p "$scratch/openspec/changes"
cp -R "$repo_root/examples/basic-workspace/openspec/changes/pkg-0001-demo" \
  "$scratch/openspec/changes/pkg-0001-demo"

json="$(cd "$scratch" && "${openspec_cmd[@]}" instructions apply --change pkg-0001-demo --json)"
instruction="$(jq -r '.instruction' <<<"$json")"
state="$(jq -r '.state' <<<"$json")"

[[ "$state" == "ready" ]] || fail "example change is ready to apply (state: $state)"
pass "example change is ready to apply"

grep -q "assigned" <<<"$instruction" ||
  fail "apply instruction addresses a worker assigned one task"
pass "apply instruction addresses a worker assigned one task"

grep -q "Do not edit tasks.md" <<<"$instruction" ||
  fail "apply instruction forbids a delegated worker from editing tasks.md"
pass "apply instruction forbids a delegated worker from editing tasks.md"

grep -Eqi "only .*host.*marks|host.*marks.*complete" <<<"$instruction" ||
  fail "apply instruction reserves completion for the accepting host"
pass "apply instruction reserves completion for the accepting host"

grep -q "mark each task complete as you go" <<<"$instruction" ||
  fail "apply instruction keeps mark-as-you-go for the owning session"
pass "apply instruction keeps mark-as-you-go for the owning session"

if grep -Eqi "next pending task" <<<"$instruction"; then
  fail "apply instruction does not let a worker pick the next pending task"
fi
pass "apply instruction does not let a worker pick the next pending task"

echo "1..$tests_run"
