#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skills_root="$repo_root/plugins/passdown/skills"
tests_run=0

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { tests_run=$((tests_run + 1)); echo "ok $tests_run - $*"; }

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
  if grep -Eq -- "$pattern" "$file"; then fail "$description"; fi
  pass "$description"
}

for skill in passdown-intake passdown-dispatch passdown-handoff; do
  require_text "$skills_root/$skill/SKILL.md" \
    "root.*nearest|root.*current|root-to-nearest" \
    "$skill defines root-to-nearest configuration inheritance"
done

dispatch="$skills_root/passdown-dispatch/SKILL.md"
require_text "$dispatch" "before executing|before execution" \
  "dispatch is defined as a pre-execution gate"
require_text_block "$dispatch" "Superpowers.*executing-plans|executing-plans.*Superpowers" \
  "dispatch explicitly gates Superpowers executing-plans"
require_text "$dispatch" "three or more pending tasks|3.*pending tasks" \
  "dispatch defines a deterministic multi-task threshold"
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
reject_text "$dispatch" "Return/relay the executor's result \*\*verbatim\*\*" \
  "dispatch no longer relays successful output verbatim"
require_text "$dispatch" "[Mm]aterialize" \
  "dispatch materializes routing decisions in the plan file"
require_text "$dispatch" "Dispatched: <executor>" \
  "dispatch records an outcome line under the task"

intake="$skills_root/passdown-intake/SKILL.md"
require_text "$intake" "planning: markdown \| openspec" \
  "intake supports both markdown and openspec planning"
require_text "$intake" "plan_dir" \
  "intake defines the markdown plan directory key"
require_text_block "$intake" "planning: markdown.*templates/plan\.md" \
  "intake defines markdown planning artifact creation"
reject_text "$intake" "<other convention>" \
  "intake no longer leaves the planning convention unspecified"
require_text "$intake" "write access|writable" \
  "intake checks cross-repo write access"
require_text "$intake" "Do not redirect.*HOME|no HOME redirects|Never redirect.*HOME" \
  "intake forbids sandbox workarounds"

handoff="$skills_root/passdown-handoff/SKILL.md"
require_text "$handoff" "collision|already exists" \
  "handoff handles filename collisions"
require_text "$handoff" "agent.*time|timestamp|HHMMSS" \
  "handoff uses an agent/time suffix"
require_text "$handoff" "frontmatter" \
  "handoff logs start with machine-readable frontmatter"
for key in "status:" "branch:" "agent:" "plan:"; do
  require_text "$handoff" "$key" "handoff frontmatter defines $key"
done
require_text "$handoff" "host name" \
  "handoff defines where the agent identity comes from"

template="$repo_root/templates/AGENTS.thin.md"
require_text "$template" "executors: agy, subagent, main" \
  "consumer template uses the portable subagent executor name"
require_text_block "$template" "MUST invoke.*passdown-dispatch|passdown-dispatch.*MUST" \
  "consumer template makes the dispatch gate mandatory"
require_text_block "$template" "Superpowers.*executing-plans|executing-plans.*Superpowers" \
  "consumer template prevents Superpowers from bypassing dispatch"

plan="$repo_root/templates/plan.md"
require_text "$plan" "dispatch: external-ok" \
  "standalone markdown plan includes external routing tags"
require_text "$plan" "dispatch: main" \
  "standalone markdown plan includes main-session routing tags"
require_text "$plan" "Paths:" \
  "standalone markdown tasks require paths"
require_text "$plan" "Done criteria" \
  "standalone markdown tasks require done criteria"
require_text "$plan" "Verification" \
  "standalone markdown tasks require verification"
require_text "$plan" "Dispatched:" \
  "standalone plan documents the dispatch outcome line"

echo "1..$tests_run"
