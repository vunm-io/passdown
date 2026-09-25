#!/usr/bin/env bash
# executor-run.sh — the E-KIRO-1 runner (e-kiro-1/run.sh) generalized to
# the executors passdown ships cards for: kiro-cli, claude, codex. Drives one
# measured run through the real v0.5 attempt lifecycle and records what
# happened. Operator tool, not a test: it spends the executor's quota and
# needs a logged-in CLI.
#
#   executor-run.sh <part> <task id> <kind> [--flags "<extra CLI flags>"] [--native-schema]
#          [--interrupt INT|KILL@<seconds>|INT|KILL@file:<path>+<seconds>]
#          [--continues <attempt> --answer <file> --resume <session id> [--minimal]]
#   executor-run.sh --finish <part> --attested-by <who>
#              resume a run left unknown, after a person has confirmed that no
#              process for the attempt remains
#   --minimal  leave the task text out of the prompt (part D: does a resumed
#              session still know the task?)
#
# Environment:
#   EK_EXECUTOR  kiro-cli | claude | codex (default kiro-cli)
#   EK_FIXTURE   disposable fixture repository (plan at docs/plan.md)
#   EK_OUT       directory for this run's records
#   EK_CARD_DIR  directory holding the executor's card used for the run
# The prompt text holds literal backticks (SC2016); ps is filtered on
# purpose to show every related process with its group and session (SC2009).
# shellcheck disable=SC2009,SC2016
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
helper="$here/../../scripts/passdown-attempt"
fx="${EK_FIXTURE:?}"
out="${EK_OUT:?}"
cards="${EK_CARD_DIR:?}"
exe="${EK_EXECUTOR:-kiro-cli}"
case "$exe" in
  kiro-cli) pat=kiro ;;
  claude) pat=claude ;; # its card is claude-code: claude.md would be CLAUDE.md on macOS
  codex) pat=codex ;;
  *) echo "unknown executor $exe" >&2; exit 2 ;;
esac
store="$fx/.git/passdown/attempts"
finish="" attested_by=""
if [ "${1:-}" = --finish ]; then
  finish=1 part="${2:?part}"
  shift 2
  if [ "${1:-}" != --attested-by ]; then echo "--finish needs --attested-by <who>" >&2; exit 2; fi
  attested_by="${2:?who}"
  set --
else
  part="${1:?part}" task="${2:?task}" kind="${3:?kind}"
  shift 3
fi
flags="" native_schema="" interrupt="" continues="" answer="" resume="" minimal=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --flags) flags="$2"; shift 2 ;;
    --native-schema) native_schema=1; shift ;;
    --interrupt) interrupt="$2"; shift 2 ;;
    --continues) continues="$2"; shift 2 ;;
    --answer) answer="$2"; shift 2 ;;
    --resume) resume="$2"; shift 2 ;;
    --minimal) minimal=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
mkdir -p "$out"
log="$out/$part.md"
H() { "$helper" --store "$store" --card-dir "$cards" "$@"; }
rev() { jq -r .rev "$store/$1/receipt.json"; }
note() { printf '%s\n' "$*" >>"$log"; }
procs() { # executor-related processes: pid, ppid, pgid, session, state, command
  ps -A -o pid=,ppid=,pgid=,sess=,stat=,command= | grep -E "$pat|sleep 1|seq " | grep -v -E 'grep|executor-run\.sh' | cut -c1-240 || true
}
kiro_pids() { # pid<TAB>start time of every executor process now running
  ps -A -o pid=,lstart=,command= | grep -i "$pat" | grep -v -E 'grep|executor-run\.sh' |
    awk '{ printf "%s\t%s %s %s %s %s\n", $1, $2, $3, $4, $5, $6 }' | sort || true
}
# tree_poll <root pid> <file>: until the root exits, record every descendant
# as "pid<TAB>pgid<TAB>session<TAB>start<TAB>command".
tree_poll() {
  local root="$1" f="$2"
  while kill -0 "$root" 2>/dev/null; do
    ps -A -o pid=,ppid=,pgid=,sess=,lstart=,command= | awk -v r="$root" '
      { pid[NR] = $1; ppid[NR] = $2; pg[$1] = $3; se[$1] = $4
        st[$1] = $5 " " $6 " " $7 " " $8 " " $9
        c = ""; for (i = 10; i <= NF; i++) c = c (c == "" ? "" : " ") $i; cmd[$1] = c; par[$1] = $2 }
      END {
        in_tree[r] = 1; changed = 1
        while (changed) { changed = 0
          for (p in par) if (!(p in in_tree) && (par[p] in in_tree)) { in_tree[p] = 1; changed = 1 } }
        for (p in in_tree) if (p != r && (p in pg)) printf "%s\t%s\t%s\t%s\t%s\n", p, pg[p], se[p], st[p], cmd[p]
      }' >>"$f"
    sleep 0.3
  done
}

finish_tail() {
  # Result: the card rule per executor. final_text prints the final agent text;
  # status_of prints how the run ended.
  final_text() {
    case "$exe" in
      kiro-cli) jq -r 'select(.type == "runFinished") | .data.finalText' "$transport" ;;
      claude) jq -r 'select(.type == "result") | .result // empty' "$transport" ;;
      codex) jq -r 'select(.type == "item.completed" and .item.type == "agent_message") | .item.text' "$transport" | tail -n 1 ;;
    esac 2>/dev/null
  }
  case "$exe" in
    kiro-cli)
      final="$(jq -r 'select(.type == "runFinished") | .data | "\(.status) truncated=\(.finalTextTruncated)"' "$transport" 2>/dev/null | tail -n 1)"
      session="$(jq -r 'select(.data.sessionId != null) | .data.sessionId' "$transport" 2>/dev/null | head -n 1)" ;;
    claude)
      final="$(jq -r 'select(.type == "result") | "\(.subtype) is_error=\(.is_error) denials=\(.permission_denials | length)"' "$transport" 2>/dev/null | tail -n 1)"
      session="$(jq -r 'select(.session_id != null) | .session_id' "$transport" 2>/dev/null | head -n 1)" ;;
    codex)
      final="$(jq -r 'select(.type == "turn.completed" or .type == "turn.failed") | .type' "$transport" 2>/dev/null | tail -n 1)"
      session="$(jq -r 'select(.type == "thread.started") | .thread_id' "$transport" 2>/dev/null | head -n 1)" ;;
  esac
  note "- session id: ${session:-none}"
  note "- end of run: ${final:-none}"
  payload="$store/$id/payload.extracted"
  final_text | grep -E '^[[:space:]]*\{.*\}[[:space:]]*$' | tail -n 1 >"$payload" || true
  if [ -s "$payload" ]; then
    if H result "$id" --rev "$(rev "$id")" --payload "$payload" >"$out/$part.result.txt" 2>&1; then
      note "- result: valid ($(jq -r .result.disposition "$store/$id/receipt.json" 2>/dev/null || jq -r .disposition "$payload"))"
    else
      note "- result: invalid — $(tr '\n' ' ' <"$out/$part.result.txt")"
    fi
  else
    note "- result: no JSON object in the final text"
  fi
  obs="$(jq -r .execution.observation "$store/$id/receipt.json")"
  if [ "$obs" = stopped ]; then
    H inspect "$id" --rev "$(rev "$id")" >/dev/null
    note "- inspect: $(jq -r .artifact.changed "$store/$id/receipt.json") changed path(s), out of scope $(jq -c .artifact.out_of_scope "$store/$id/receipt.json"), plan touched $(jq -r .artifact.plan_touched "$store/$id/receipt.json")"
  fi
  # Verdict (section 12), so the claim does not block the next part.
  if [ "$obs" = stopped ]; then
    disp="$(jq -r '.result.disposition // ""' "$store/$id/receipt.json")"
    status="$(jq -r .result.status "$store/$id/receipt.json")"
    verify="$(sed -n "/^- \[[ xX]\] $task /,/^- \[/p" "$fx/docs/plan.md" | sed -n 's/.*Verification: `\(.*\)`.*/\1/p' | head -n 1)"
    code_v=0
    (cd "$fx" && sh -c "$verify") >"$out/$part.check.txt" 2>&1 || code_v=$?
    note "- host check \`$verify\`: exit $code_v"
    reason=""
    if [ "$status" != valid ]; then reason=invalid_result
    elif [ "$disp" = needs_input ] || [ "$disp" = blocked ]; then reason="$disp"
    elif [ "$disp" = failed ]; then reason=worker_failed
    elif [ "$(jq -r .artifact.plan_touched "$store/$id/receipt.json")" = true ]; then reason=plan_tampered
    elif [ "$(jq -r '.artifact.out_of_scope | length' "$store/$id/receipt.json")" != 0 ]; then reason=scope_violation
    elif [ "$code_v" != 0 ]; then reason=verification_failed
    fi
    if [ -z "$reason" ]; then
      settle="$(jq -r '."stop.settle_seconds" // "0"' "$store/$id/card.json")"
      sleep "$settle"
      H inspect "$id" --rev "$(rev "$id")" >/dev/null
      if H verdict "$id" accept --rev "$(rev "$id")" --check "$verify=0:$out/$part.check.txt" >"$out/$part.verdict.txt" 2>&1; then
        TASK="$task" LINE="  - Dispatched: kiro-cli ($(date +%F)) — accepted; verified: $verify; attempt: $id" perl -0pi -e \
          's/(^- \[ \] \Q$ENV{TASK}\E [^\n]*\n(?:  [^\n]*\n)*)/$1$ENV{LINE}\n/m; s/^- \[ \] \Q$ENV{TASK}\E /- [x] $ENV{TASK} /m' "$fx/docs/plan.md"
        H projected "$id" --rev "$(rev "$id")" --plan "$fx/docs/plan.md" >/dev/null
        note "- verdict: accepted and projected"
      else
        note "- verdict: accept refused — $(tr '\n' ' ' <"$out/$part.verdict.txt")"
      fi
    else
      H verdict "$id" reject --rev "$(rev "$id")" --reason-code "$reason" --reason "$exe measurement part $part" >/dev/null
      note "- verdict: rejected ($reason); claim $(jq -r .claim.state "$store/$id/receipt.json")"
    fi
  fi
  note "- git status: \`$(cd "$fx" && git status --porcelain | tr '\n' ';')\`"
  case "$exe" in
    kiro-cli) calls="$(jq -r 'select(.type == "sessionUpdate") | .data.update | select(.sessionUpdate == "tool_call") | .title // .kind // "tool"' "$transport" 2>/dev/null)" ;;
    claude) calls="$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | "\(.name) \(.input.command // .input.file_path // "")"' "$transport" 2>/dev/null)
  $(jq -r 'select(.type == "result") | .permission_denials[]? | "DENIED \(.tool_name)"' "$transport" 2>/dev/null)" ;;
    codex) calls="$(jq -r 'select(.type == "item.completed") | .item | select(.type != "agent_message" and .type != "reasoning") | "\(.type) \(.command // ([.changes[]?.path] | join(",")) // "") exit=\(.exit_code // "-") \(.status // "")"' "$transport" 2>/dev/null)" ;;
  esac
  note "- tool calls: $(printf '%s' "$calls" | tr '\n' ';' | cut -c1-600)"
  note "- stderr: \`$(tr '\n' ' ' <"$out/$part.stderr" | cut -c1-400)\`"
  cp "$transport" "$out/$part.transport.jsonl"
  cp "$store/$id/receipt.json" "$out/$part.receipt.json"
  echo "$id"
}

if [ -n "$finish" ]; then
  # shellcheck disable=SC1090
  . "$out/$part.state"
  transport="$store/$id/transport.log"
  H observe "$id" stopped --rev "$(rev "$id")" --evidence owner-attested --attested-by "$attested_by" --exit "$code" >/dev/null
  note "- stop: owner-attested by $attested_by, after checking the listings above"
  rm -f "$out/$part.state"
  finish_tail
  exit 0
fi

: >"$log"
note "# $exe part $part — task $task ($kind)"
note ""
note "- date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
note "- $exe: $("$exe" --version 2>&1 | head -n 1)"
note "- host OS: $(sw_vers -productName 2>/dev/null || uname -s) $(sw_vers -productVersion 2>/dev/null || uname -r)"

args=(--task-ref "docs/plan.md#$task" --planner-repo "$fx" --kind "$kind" --executor "$exe" --card "$([ "$exe" = claude ] && echo claude-code || echo "$exe")@1"
  --host claude --session card-measurement --place-repo "$fx")
if [ -n "$continues" ]; then
  args+=(--tier external --reason-code review-experiment --reason "$exe measurement continuation" --continues "$continues")
  [ -z "$answer" ] || args+=(--answer "$answer")
else
  args+=(--tier external --reason-code review-experiment --reason "$exe measurement part $part")
  if [ "$kind" = read ]; then args+=(--isolation read-only); else args+=(--isolation current-checkout); fi
fi
id="$(H new "${args[@]}")"
note "- attempt: $id"

block="$(awk -v id="$task" '$0 ~ "^- \\[[ xX]\\] " id " " { p = 1; print; next } p && /^- \[/ { exit } p && NF { print }' "$fx/docs/plan.md")"
prompt="$out/$part.prompt.md"
{
  printf 'You are a delegated worker. Implement only task docs/plan.md#%s. Do not edit the plan file: no checkbox changes, no `Dispatched:` lines, no edits to done criteria or verification. Report your outcome, changed paths and verification evidence; the host decides whether the task is complete.\n\n' "$task"
  printf 'If a command fails because of sandbox, permission, or network restrictions, STOP and report the error verbatim. Do not work around it (no HOME redirects, no local caches, no config or project-file edits).\n\n'
  printf 'End with one JSON object matching `passdown.result/v1` for attempt %s as your final output, alone on the last line. If the task is ambiguous, do not guess and do not write: return `needs_input` with your question. If a command is denied by sandbox, permission or network rules, stop and return `blocked` with the error verbatim.\n\nThe object must validate against this JSON Schema:\n\n```json\n%s\n```\n\n' "$id" "$(jq -c . "$here/../../schemas/protocol/result.v1.schema.json")"
  printf 'Do not dispatch this work, or any part of it, to another external agent CLI. Your provider'"'"'s own native subagents are your provider'"'"'s business.\n\n'
  if [ -z "$minimal" ]; then printf 'The task:\n\n%s\n' "$block"; else printf 'Continue the task you were working on in this conversation.\n'; fi
  if [ -n "$answer" ]; then printf '\nAnswer to your earlier question: %s\n' "$(cat "$answer")"; fi
} >"$prompt"
H arm "$id" --rev "$(rev "$id")" --prompt "$prompt" >/dev/null
kiro_pids >"$out/$part.kiro-before"

schema="$here/../../schemas/protocol/result.v1.schema.json"
read -r -a extra <<<"$flags"
case "$exe" in
  kiro-cli)
    argv=(kiro-cli chat --output-format stream-json ${extra[@]+"${extra[@]}"})
    [ -z "$resume" ] || argv+=(--resume-id "$resume")
    ;;
  claude)
    argv=(claude -p --output-format stream-json --verbose ${extra[@]+"${extra[@]}"})
    [ -z "$native_schema" ] || argv+=(--json-schema "$(jq -c . "$schema")")
    [ -z "$resume" ] || argv+=(--resume "$resume")
    ;;
  codex)
    if [ -n "$resume" ]; then argv=(codex exec resume --json --skip-git-repo-check ${extra[@]+"${extra[@]}"})
    else argv=(codex exec --json --skip-git-repo-check ${extra[@]+"${extra[@]}"}); fi
    [ -z "$native_schema" ] || argv+=(--output-schema "$schema")
    [ -z "$resume" ] || argv+=("$resume")
    ;;
esac
argv+=("$(cat "$prompt")")
note "- argv: \`${argv[*]:0:${#argv[@]}-1} \"<prompt: $part.prompt.md>\"\`"
transport="$store/$id/transport.log"
(cd "$fx" && exec perl -e 'setpgrp(0, 0); exec @ARGV' "${argv[@]}") </dev/null >"$transport" 2>"$out/$part.stderr" &
wpid=$!
wstart="$(ps -o lstart= -p "$wpid" | sed 's/^ *//; s/ *$//')"
H observe "$id" running --rev "$(rev "$id")" --pid "$wpid" --pid-started "$wstart" --pgid "$wpid" >/dev/null
note "- launched pid/pgid $wpid"
: >"$out/$part.tree"
tree_poll "$wpid" "$out/$part.tree" &
poller=$!

code=0
if [ -n "$interrupt" ]; then
  sig="${interrupt%@*}" after="${interrupt#*@}"
  case "$after" in
    file:*) # file:<path>+<seconds>: wait until the worker starts writing <path>
      wfile="${after#file:}" after="${wfile##*+}" wfile="${wfile%+*}" n=0
      until [ -e "$fx/$wfile" ] || [ "$n" -ge 600 ]; do sleep 0.5; n=$((n + 1)); done
      note "- $wfile appeared; signalling ${after}s later" ;;
  esac
  sleep "$after"
  note ""
  note "## Before the signal"
  note '```'
  procs >>"$log"
  note '```'
  H cancel "$id" --rev "$(rev "$id")" --method "$sig to the process group" >/dev/null
  kill "-$sig" "-$wpid" 2>/dev/null || true
  note "- sent SIG$sig to process group $wpid after ${after}s"
fi
wait "$wpid" || code=$?
note "- exit code: $code"
wait "$poller" 2>/dev/null || true
sleep 2
sort -u "$out/$part.tree" -o "$out/$part.tree"
note ""
note "## Descendants seen while the worker ran (pid, pgid, session, start, command)"
note '```'
cut -c1-200 "$out/$part.tree" >>"$log"
note '```'
note "- descendants in another process group: $(awk -F '\t' -v g="$wpid" '$2 != g' "$out/$part.tree" | wc -l | tr -d ' ')"
survivors=""
while IFS="$(printf '\t')" read -r dpid _ _ dstart _; do
  [ -n "$dpid" ] || continue
  [ "$(ps -o lstart= -p "$dpid" 2>/dev/null | awk '{ print $1, $2, $3, $4, $5 }')" = "$dstart" ] && survivors="$survivors $dpid"
done <"$out/$part.tree"
kiro_pids >"$out/$part.kiro-after"
new_kiro="$(comm -13 "$out/$part.kiro-before" "$out/$part.kiro-after" | cut -f1 | tr '\n' ' ')"
note "- descendants alive 2 s after the parent exited:${survivors:- none}"
note "- $exe processes started during the run and still alive: ${new_kiro:-none}"
note ""
note "## Processes 2 s after the parent exited"
note '```'
procs >>"$log"
note '```'
facts="$(H probe "$id")"
note "- probe: \`$facts\`"

# Stop: only safe machine evidence ends the attempt here. Otherwise the
# attempt stays unknown and a person must confirm (dispatch steps 10-11):
# the operator checks the listings above, then runs
#   executor-run.sh --finish <part> --attested-by <who>
if jq -e '.safe_evidence | index("exit+pgroup-empty") or index("exit+scope-empty")' <<<"$facts" >/dev/null; then
  H observe "$id" stopped --rev "$(rev "$id")" --evidence "$(jq -r '.safe_evidence | map(select(. != "owner-attested"))[0]' <<<"$facts")" --exit "$code" >/dev/null
  note "- stop: $(jq -r '.safe_evidence | map(select(. != "owner-attested"))[0]' <<<"$facts")"
else
  H observe "$id" unknown --rev "$(rev "$id")" --note "parent exited ($code); descendants not ruled out" --parent-exited >/dev/null
  printf 'id=%s\ntask=%s\nkind=%s\ncode=%s\n' "$id" "$task" "$kind" "$code" >"$out/$part.state"
  note "- stop: unknown, waiting for the operator's confirmation (group members $(jq -r .pgroup_members <<<"$facts"), surviving descendants:${survivors:- none}, new $exe processes: ${new_kiro:-none})"
  echo "attempt $id is unknown: check the listings in $log, then run: $0 --finish $part --attested-by <who>" >&2
  echo "$id"
  exit 0
fi

finish_tail
