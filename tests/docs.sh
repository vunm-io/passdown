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

require_text_block() {
  local file="$1" pattern="$2" description="$3"
  tr '\n' ' ' <"$file" | grep -Eq -- "$pattern" || fail "$description"
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

require_text "$readme" "skills-only" \
  "README documents the --skills-only install mode"
require_text "$readme" "optional" \
  "README states that the integrations are optional"
require_text "$readme" "dispatch gate|pre-execution gate" \
  "README documents the pre-execution dispatch gate"
require_text "$readme" "templates/plan\\.md" \
  "README documents the standalone markdown plan template"
require_text "$readme" "docs/INTEGRATIONS\\.md" \
  "README links the integrations guide"
reject_text "$readme" "trigger automatically on their descriptions, and" \
  "README no longer presents description triggering as deterministic"

require_text "$smoke" "Codex plugin channel" \
  "smoke test covers the Codex plugin channel"
require_text "$smoke" "CODEX_HOME" \
  "smoke test isolates Codex installation state"
require_text "$smoke" "cross-repo.*permission|permission.*cross-repo" \
  "smoke test covers cross-repo permissions"
require_text "$smoke" "Passdown only" \
  "smoke test covers standalone Passdown"
require_text "$smoke" "Passdown \\+ OpenSpec$" \
  "smoke test covers Passdown with OpenSpec"
require_text "$smoke" "Passdown \\+ Superpowers" \
  "smoke test covers Passdown with Superpowers"
require_text "$smoke" "Passdown \\+ OpenSpec \\+ Superpowers" \
  "smoke test covers the combined integration"
require_text_block "$smoke" "before.*Superpowers.*executing-plans" \
  "smoke test verifies Superpowers cannot bypass dispatch"

integrations="$repo_root/docs/INTEGRATIONS.md"
require_text "$integrations" "Standalone Passdown" \
  "integrations guide covers standalone Passdown"
require_text "$integrations" "OpenSpec" \
  "integrations guide covers OpenSpec"
require_text "$integrations" "Superpowers" \
  "integrations guide covers Superpowers"
require_text "$integrations" "skills-only" \
  "integrations guide documents the skills-only install"

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
