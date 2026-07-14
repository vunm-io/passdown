#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
doctor="$repo_root/scripts/doctor.sh"
installer="$repo_root/install.sh"
tests_run=0

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { tests_run=$((tests_run + 1)); echo "ok $tests_run - $*"; }
new_home() { mktemp -d; }

run_doctor() { # run_doctor <home> -> prints output, never aborts the suite
  HOME="$1" CODEX_HOME="$1/.codex" "$doctor" 2>&1 || true
}

doctor_status() { # doctor_status <home> -> exit code as text
  local code=0
  HOME="$1" CODEX_HOME="$1/.codex" "$doctor" >/dev/null 2>&1 || code=$?
  echo "$code"
}

test_clean_home_passes() {
  local home
  home="$(new_home)"
  [ "$(doctor_status "$home")" = 0 ] || fail "clean home reported issues"
  run_doctor "$home" | grep -q "not installed" ||
    fail "clean home did not report missing installs"
  pass "clean home passes with a not-installed note"
}

test_direct_in_sync_passes() {
  local home
  home="$(new_home)"
  HOME="$home" "$installer" --host claude --skills-only >/dev/null
  [ "$(doctor_status "$home")" = 0 ] ||
    fail "in-sync direct install reported issues"
  run_doctor "$home" | grep -q "direct channel only" ||
    fail "direct channel was not reported"
  pass "in-sync direct install passes"
}

test_stale_direct_install_fails() {
  local home
  home="$(new_home)"
  HOME="$home" "$installer" --host claude --skills-only >/dev/null
  echo "stale local edit" >>"$home/.claude/skills/passdown-intake/SKILL.md"
  [ "$(doctor_status "$home")" != 0 ] || fail "stale direct install passed"
  run_doctor "$home" | grep -q "out of sync" ||
    fail "stale direct install was not named"
  pass "stale direct install is reported"
}

test_dual_channel_fails() {
  local home
  home="$(new_home)"
  HOME="$home" "$installer" --host codex --skills-only >/dev/null
  mkdir -p "$home/.codex"
  printf '[plugins."passdown@passdown"]\nenabled = true\n' \
    >"$home/.codex/config.toml"
  [ "$(doctor_status "$home")" != 0 ] || fail "dual-channel install passed"
  run_doctor "$home" | grep -q "BOTH" || fail "dual channel was not named"
  pass "dual plugin/direct channel is reported"
}

test_plugin_only_passes() {
  local home
  home="$(new_home)"
  mkdir -p "$home/.claude/plugins"
  printf '{"passdown@passdown": {}}\n' \
    >"$home/.claude/plugins/installed_plugins.json"
  [ "$(doctor_status "$home")" = 0 ] || fail "plugin-only install reported issues"
  run_doctor "$home" | grep -q "plugin channel only" ||
    fail "plugin channel was not reported"
  pass "plugin-only install passes"
}

test_clean_home_passes
test_direct_in_sync_passes
test_stale_direct_install_fails
test_dual_channel_fails
test_plugin_only_passes

echo "1..$tests_run"
