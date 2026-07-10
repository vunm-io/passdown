#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/install.sh"
tests_run=0

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { tests_run=$((tests_run + 1)); echo "ok $tests_run - $*"; }
new_home() { mktemp -d; }

test_help_has_no_side_effects() {
  local home
  home="$(new_home)"
  HOME="$home" "$installer" --help >/dev/null
  [ ! -e "$home/.claude" ] || fail "--help created Claude files"
  [ ! -e "$home/.agents" ] || fail "--help created Codex files"
  [ ! -e "$home/.local" ] || fail "--help created schema files"
  pass "--help prints usage without installing"
}

test_unknown_argument_fails_without_side_effects() {
  local home
  home="$(new_home)"
  if HOME="$home" "$installer" --definitely-invalid >/dev/null 2>&1; then
    fail "unknown argument exited successfully"
  fi
  [ ! -e "$home/.claude" ] || fail "unknown argument created Claude files"
  [ ! -e "$home/.local" ] || fail "unknown argument created schema files"
  pass "unknown arguments fail without installing"
}

test_into_requires_exactly_one_directory() {
  local home target
  home="$(new_home)"
  target="$(mktemp -d)"
  if HOME="$home" "$installer" --into "$target" extra >/dev/null 2>&1; then
    fail "--into accepted an extra argument"
  fi
  [ ! -e "$target/openspec" ] || fail "invalid --into invocation copied schema"
  HOME="$home" "$installer" --into "$target" >/dev/null
  [ -f "$target/openspec/schemas/passdown/schema.yaml" ] ||
    fail "valid --into invocation did not copy schema"
  pass "--into enforces exact arity and copies the schema"
}

test_copy_removes_stale_and_preserves_nested_resources() {
  local home nested_src nested_dst
  home="$(new_home)"
  mkdir -p "$home/.claude/skills/passdown-intake"
  touch "$home/.claude/skills/passdown-intake/obsolete.md"
  nested_src="$repo_root/plugins/passdown/skills/passdown-intake/references/.install-test"
  nested_dst="$home/.claude/skills/passdown-intake/references/.install-test"
  mkdir -p "$(dirname "$nested_src")"
  printf 'nested resource\n' >"$nested_src"
  trap 'rm -f "$nested_src"; rmdir "$(dirname "$nested_src")" 2>/dev/null || true' RETURN
  HOME="$home" "$installer" --host claude >/dev/null
  [ ! -e "$home/.claude/skills/passdown-intake/obsolete.md" ] ||
    fail "stale installed file survived sync"
  [ -f "$nested_dst" ] || fail "nested resource was not copied"
  pass "skill sync removes stale files and copies nested resources"
}

test_host_selection_is_scoped() {
  local home
  home="$(new_home)"
  HOME="$home" "$installer" --host codex >/dev/null
  [ -f "$home/.agents/skills/passdown-dispatch/SKILL.md" ] ||
    fail "Codex host install is missing"
  [ ! -e "$home/.claude" ] || fail "Codex-only install wrote Claude files"
  [ ! -e "$home/.kiro" ] || fail "Codex-only install wrote Kiro files"
  pass "--host installs only the selected host"
}

test_skills_only_omits_openspec_schema() {
  local home
  home="$(new_home)"
  HOME="$home" "$installer" --host claude --skills-only >/dev/null
  [ -f "$home/.claude/skills/passdown-dispatch/SKILL.md" ] ||
    fail "skills-only install omitted Passdown skills"
  [ ! -e "$home/.local/share/openspec/schemas/passdown" ] ||
    fail "skills-only install copied the optional OpenSpec schema"
  pass "--skills-only installs Passdown without OpenSpec schema files"
}

test_help_has_no_side_effects
test_unknown_argument_fails_without_side_effects
test_into_requires_exactly_one_directory
test_copy_removes_stale_and_preserves_nested_resources
test_host_selection_is_scoped
test_skills_only_omits_openspec_schema

echo "1..$tests_run"
