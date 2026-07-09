#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tests_run=0

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  tests_run=$((tests_run + 1))
  echo "ok $tests_run - $*"
}

require_text() {
  local file="$1" pattern="$2" description="$3"
  grep -Eq -- "$pattern" "$file" || fail "$description"
  pass "$description"
}

reject_text() {
  local file="$1" pattern="$2" description="$3"
  if grep -Eq -- "$pattern" "$file"; then
    fail "$description"
  fi
  pass "$description"
}

readme="$repo_root/README.md"
smoke="$repo_root/docs/SMOKE_TEST.md"

require_text "$readme" "\\*\\*Codex\\*\\*.*host.*Supported|\\*\\*Codex\\*\\*.*Supported.*host" \
  "README lists Codex as a supported host"
require_text "$readme" "codex plugin marketplace add vunm-io/passdown" \
  "README documents Codex marketplace installation"
require_text "$readme" "codex plugin add passdown@passdown" \
  "README documents Codex plugin installation"
require_text "$readme" "one.*channel|ONE.*channel" \
  "README warns users to choose one install channel"
reject_text "$readme" "Codex and Antigravity are dispatch targets, not places passdown installs into" \
  "README no longer says Codex cannot host passdown"
reject_text "$readme" "Neither runs passdown skills directly" \
  "README no longer groups Codex with executor-only tools"

require_text "$smoke" "Codex plugin channel" \
  "smoke test covers the Codex plugin channel"
require_text "$smoke" "CODEX_HOME" \
  "smoke test isolates Codex installation state"
require_text "$smoke" "cross-repo.*permission|permission.*cross-repo" \
  "smoke test covers cross-repo permissions"

design="$repo_root/schemas/passdown/templates/design.md"
require_text "$design" "^## Migration Plan" \
  "design template includes Migration Plan"
require_text "$design" "^## Open Questions" \
  "design template includes Open Questions"

diff -r "$repo_root/schemas/passdown" \
  "$repo_root/examples/basic-workspace/openspec/schemas/passdown" >/dev/null ||
  fail "example schema copy differs from the source schema"
pass "example schema copy is synchronized"

echo "1..$tests_run"
