#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$repo_root/scripts/check-version.sh"
tests_run=0

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  tests_run=$((tests_run + 1))
  echo "ok $tests_run - $*"
}

[ -x "$checker" ] || fail "scripts/check-version.sh is missing or not executable"
"$checker"
pass "all repository manifests match VERSION"

version="$(tr -d '[:space:]' <"$repo_root/VERSION")"
"$checker" --tag "v$version"
pass "release tag matches VERSION"

if "$checker" --tag "v9.9.9" >/dev/null 2>&1; then
  fail "mismatched tag was accepted"
fi
pass "mismatched release tag is rejected"

scratch="$(mktemp -d)"
mkdir -p "$scratch/scripts" "$scratch/.claude-plugin" \
  "$scratch/.agents/plugins" \
  "$scratch/plugins/passdown/.claude-plugin" \
  "$scratch/plugins/passdown/.codex-plugin"
cp "$checker" "$scratch/scripts/check-version.sh"
cp "$repo_root/VERSION" "$scratch/VERSION"
cp "$repo_root/.claude-plugin/marketplace.json" "$scratch/.claude-plugin/"
cp "$repo_root/.agents/plugins/marketplace.json" "$scratch/.agents/plugins/"
cp "$repo_root/plugins/passdown/.claude-plugin/plugin.json" \
  "$scratch/plugins/passdown/.claude-plugin/"
cp "$repo_root/plugins/passdown/.codex-plugin/plugin.json" \
  "$scratch/plugins/passdown/.codex-plugin/"
jq '.version = "9.9.9"' \
  "$scratch/plugins/passdown/.codex-plugin/plugin.json" \
  >"$scratch/plugins/passdown/.codex-plugin/plugin.json.tmp"
mv "$scratch/plugins/passdown/.codex-plugin/plugin.json.tmp" \
  "$scratch/plugins/passdown/.codex-plugin/plugin.json"

if "$scratch/scripts/check-version.sh" --root "$scratch" >/dev/null 2>&1; then
  fail "manifest version drift was accepted"
fi
pass "manifest version drift is rejected"

echo "1..$tests_run"
