#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skills_root="$repo_root/plugins/passdown/skills"
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

for skill in passdown-intake passdown-dispatch passdown-handoff; do
  require_text \
    "$skills_root/$skill/SKILL.md" \
    "root.*nearest|root.*current|root-to-nearest" \
    "$skill defines root-to-nearest configuration inheritance"
done

dispatch="$skills_root/passdown-dispatch/SKILL.md"
require_text "$dispatch" "Detect the current host|current host" \
  "dispatch detects the current host"
require_text "$dispatch" "non-Codex host|host is not Codex" \
  "dispatch only treats Codex as external from another host"
require_text "$dispatch" "explicitly asks|explicit authorization|explicitly requested" \
  "dispatch requires explicit authorization for subagents"
require_text "$dispatch" "baseline" \
  "dispatch captures a pre-dispatch baseline"
require_text "$dispatch" "pre-existing.*changes|preexisting.*changes" \
  "dispatch preserves pre-existing changes"
require_text "$dispatch" "structured summary" \
  "dispatch returns a structured summary"
require_text "$dispatch" "environment error.*verbatim|errors? verbatim" \
  "dispatch preserves environment errors verbatim"
reject_text "$dispatch" "claude-subagent" \
  "dispatch no longer exposes the Claude-specific subagent name"
reject_text "$dispatch" "Return/relay the executor's result \\*\\*verbatim\\*\\*" \
  "dispatch no longer relays successful output verbatim"

intake="$skills_root/passdown-intake/SKILL.md"
require_text "$intake" "write access|writable" \
  "intake checks cross-repo write access"
require_text "$intake" "Do not redirect.*HOME|no HOME redirects|Never redirect.*HOME" \
  "intake forbids sandbox workarounds"

handoff="$skills_root/passdown-handoff/SKILL.md"
require_text "$handoff" "collision|already exists" \
  "handoff handles filename collisions"
require_text "$handoff" "agent.*time|timestamp|HHMMSS" \
  "handoff uses an agent/time suffix"

template="$repo_root/templates/AGENTS.thin.md"
require_text "$template" "executors: agy, subagent, main" \
  "consumer template uses the portable subagent executor name"

echo "1..$tests_run"
