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

for skill in passdown-intake passdown-dispatch passdown-handoff passdown-pickup; do
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

# Completion authority (PDN-0003): a delegated worker never accepts its own
# work; only the accepting host records canonical completion.
require_text "$dispatch" "^## Completion authority" \
  "dispatch defines a completion-authority section"
require_text_block "$dispatch" "worker never accepts its own work" \
  "dispatch states that a delegated worker never accepts its own work"
require_text_block "$dispatch" "native subagent.*delegated worker|delegated worker.*native subagent" \
  "dispatch treats native subagents as delegated workers too"
require_text_block "$dispatch" "Do not edit .*checkbox|must not (edit|mutate|tick).*checkbox" \
  "dispatch forbids delegated workers from editing plan checkboxes"
require_text_block "$dispatch" "exact task +reference" \
  "dispatch assigns external work by exact task reference"
reject_text "$dispatch" "next pending task" \
  "dispatch no longer lets a worker pick the next pending task"
reject_text "$dispatch" "mark it \\[x\\]" \
  "dispatch no longer tells a worker to mark its task [x]"
reject_text "$dispatch" "how to record completion" \
  "dispatch no longer asks the worker to record completion"
require_text_block "$dispatch" "restore .*from the baseline" \
  "dispatch restores worker edits to plan authority fields"
require_text_block "$dispatch" "Dispatched: <executor> \\(<YYYY-MM-DD>\\) — accepted" \
  "dispatch outcome line records host acceptance"
require_text_block "$dispatch" "keep a +\`\\[dispatch: external-ok\\]\` +task in the current session, change its tag" \
  "dispatch retags an external-ok task that stays in main"
require_text_block "$dispatch" "restore it from the +baseline only when the change is +unambiguously the worker's" \
  "dispatch restores only authority-field edits attributable to the worker"
require_text_block "$dispatch" "cannot attribute the +change safely.*do not overwrite it" \
  "dispatch stops instead of overwriting unattributable plan edits"
require_text_block "$dispatch" "^.*Accepted verdict" \
  "dispatch defines the accepted-verdict rule"
require_text_block "$dispatch" "same actor.*mark.*complete as you go|mark.*complete as you go.*same actor" \
  "dispatch keeps mark-as-you-go for main, where host and worker are the same actor"

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

require_text_block "$handoff" "[Nn]ever tick a delegated +task" \
  "handoff never ticks a delegated task on the worker's report"
require_text_block "$handoff" "accepted.*Dispatched:|Dispatched:.*accepted" \
  "handoff ticks delegated tasks only with a host acceptance line"
require_text_block "$handoff" "unverified.*\\[ \\]|\\[ \\].*unverified" \
  "handoff returns unverified delegated completion to [ ]"

# One accepted-verdict rule across dispatch, handoff and pickup, including
# legacy success lines written before the `accepted` wording (PDN-0003 review).
for skill in passdown-dispatch passdown-handoff passdown-pickup; do
  require_text_block "$skills_root/$skill/SKILL.md" \
    "written before the +\`accepted\` +wording +existed count as +accepted when +they report success and name a host +check after +\`verified:\`" \
    "$skill accepts legacy success lines that name a host check"
done
reject_text "$handoff" "records +\`accepted\` with a check the host ran\. Never" \
  "handoff no longer requires the literal accepted word for legacy lines"

pickup="$skills_root/passdown-pickup/SKILL.md"
require_text "$pickup" "frontmatter" \
  "pickup reads log frontmatter before full logs"
require_text "$pickup" "newest" \
  "pickup locates the most recent handoff"
require_text "$pickup" "mismatch" \
  "pickup verifies log claims against the working tree"
require_text "$pickup" "never starts executing" \
  "pickup ends with a briefing, not execution"
require_text "$pickup" "passdown-dispatch" \
  "pickup routes multi-task plans through the dispatch gate"
require_text "$pickup" "[Nn]ever modify" \
  "pickup never modifies a previous shift's log"

require_text_block "$pickup" "[Ii]nconsistent" \
  "pickup flags inconsistent dispatched completion"
require_text_block "$pickup" "\\[x\\].*Dispatched:.*accepted|\\[x\\].*accepted.*Dispatched:" \
  "pickup checks a dispatched [x] against a host acceptance line"
require_text_block "$pickup" "not accepted|still pending|as pending" \
  "pickup treats unverified delegated completion as not accepted"

schema="$repo_root/schemas/passdown/schema.yaml"
apply_instruction="$(sed -n '/^apply:/,$p' "$schema")"
grep -q "assigned" <<<"$apply_instruction" ||
  fail "schema apply.instruction addresses delegated workers"
pass "schema apply.instruction addresses delegated workers"
grep -Eq "Do not edit tasks\.md" <<<"$apply_instruction" ||
  fail "schema apply.instruction forbids delegated tasks.md edits"
pass "schema apply.instruction forbids delegated tasks.md edits"
if grep -Eq "^    Read context files, work through pending tasks, mark complete as you go\.$" <<<"$apply_instruction"; then
  fail "schema apply.instruction no longer grants unconditional mark-as-you-go"
fi
pass "schema apply.instruction no longer grants unconditional mark-as-you-go"

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

require_text_block "$plan" "Dispatched:.*accepted" \
  "standalone plan shows the host acceptance outcome"
require_text_block "$plan" "delegated worker.*never|never.*delegated worker" \
  "standalone plan states that delegated workers never tick tasks"

echo "1..$tests_run"
