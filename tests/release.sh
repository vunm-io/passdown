#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_workflow="$repo_root/.github/workflows/release.yml"
ci_workflow="$repo_root/.github/workflows/ci.yml"
notes_script="$repo_root/scripts/release-notes.sh"
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
  rg -q -- "$pattern" "$file" || fail "$description"
  pass "$description"
}

[ -f "$release_workflow" ] || fail ".github/workflows/release.yml is missing"
[ -x "$notes_script" ] || fail "scripts/release-notes.sh is missing or not executable"

require_text "$release_workflow" "tags:" \
  "release workflow is triggered by tags"
require_text "$release_workflow" "contents: write" \
  "release workflow has scoped contents permission"
require_text "$release_workflow" "check-version\\.sh --tag" \
  "release workflow checks tag/version agreement"
require_text "$release_workflow" "uses: \\./\\.github/workflows/ci\\.yml" \
  "release workflow reuses the complete CI gate"
require_text "$ci_workflow" "tests/install\\.sh" \
  "CI runs installer regressions"
require_text "$ci_workflow" "tests/skills\\.sh" \
  "CI runs skill contracts"
require_text "$ci_workflow" "codex plugin add" \
  "CI smoke-tests Codex installation"
require_text "$release_workflow" "gh release create" \
  "release workflow publishes a GitHub Release"

notes="$("$notes_script" 0.2.0)"
printf '%s\n' "$notes" | rg -q '^### Added|^### Changed|^### Fixed' ||
  fail "v0.2.0 release notes contain no change categories"
printf '%s\n' "$notes" | rg -q 'Codex' ||
  fail "v0.2.0 release notes omit Codex support"
pass "release notes are extracted from the v0.2.0 changelog section"

if "$notes_script" 9.9.9 >/dev/null 2>&1; then
  fail "missing changelog version was accepted"
fi
pass "missing changelog versions are rejected"

require_text "$repo_root/AGENTS.md" "Never push directly to \`main\`|Do not push directly to \`main\`" \
  "repository policy forbids direct pushes to main"
require_text "$repo_root/AGENTS.md" "short-lived" \
  "repository policy uses short-lived branches"
require_text "$repo_root/docs/RELEASE.md" "v0\\.1\\.0.*pending|pending.*v0\\.1\\.0" \
  "release docs record the missing v0.1.0 GitHub prerelease"

if rg -q 'gh repo edit .*--visibility public' "$repo_root/docs/RELEASE.md"; then
  fail "recurring release docs still contain the one-time go-public command"
fi
pass "recurring release docs omit the completed visibility change"

echo "1..$tests_run"
