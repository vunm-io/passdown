#!/usr/bin/env bash
# run.sh <scenario> <out> — run one Layer B scenario (design PDN-0004 §20.1)
# against a real host: `claude -p` with the passdown v0.5 skills.
#
# 1. Build the scenario's fixture (fixture.sh) and ask the host to execute
#    task 1.1 through passdown-dispatch.
# 2. If the scenario has a crash marker, kill the host's process group as
#    soon as a receipt reaches it (after-arm, after-result, after-verdict).
#    Apply the scenario's after_crash edit, then start a NEW host session
#    that runs pickup and reconciles.
# 3. Show the owner each host reply and pass the owner's answer back
#    verbatim (`claude -p --resume`). This script never answers for the
#    owner and never records an attestation. An empty answer ends the run.
# 4. Copy the files (collect.sh) and judge them (oracle.sh).
#
# Interactive: the owner answers on /dev/tty. Transcripts, the owner's
# answers and the oracle verdict go into <out>.
#
# Environment: LB_WORK (where fixtures are built; default a temp dir),
# LB_OPERATOR (the owner's name, recorded with the answers).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
scenario="${1:?scenario}"
out="${2:?out}"
[ -f "$here/scenarios/$scenario.sh" ] || { echo "unknown scenario $scenario" >&2; exit 2; }
# shellcheck source=/dev/null
. "$here/scenarios/$scenario.sh"
mkdir -p "$out/transcripts"
out="$(cd "$out" && pwd -P)"
echo "$scenario" >"$out/scenario"
work="${LB_WORK:-$(mktemp -d)}"
fx="$("$here/fixture.sh" "$work/$scenario" "$scenario")"
store="$fx/.git/passdown/attempts"
operator="${LB_OPERATOR:-owner}"
: >"$out/owner-answers.txt"
# What happened, for oracle.sh: "turn <n>", "crash <marker> <n>",
# "after_crash", "pickup <n>".
events="$out/run-events.txt"
: >"$events"

DISPATCH_PROMPT="You are the host session for this repository. Execute task 1.1 of docs/plan.md. Follow the passdown workflow exactly: invoke the passdown-dispatch skill first and do what it says, using this repository's AGENTS.md for configuration and routing. If the skill tells you to ask the user something, stop and ask instead of assuming."
PICKUP_PROMPT="You are a new host session for this repository; an earlier session was interrupted. Invoke the passdown-pickup skill and brief me. Then carry out what it proposes through the Reconcile section of the passdown-dispatch skill, using this repository's AGENTS.md. If a skill tells you to ask the user something, stop and ask instead of assuming."

case "$CRASH_MARKER" in
  none) marker="" ;;
  after-arm) marker='.execution.observation == "unknown" and .handle.pid == null and .handle.provider_session == null' ;;
  after-result) marker='.result.status == "valid"' ;;
  after-verdict) marker='.verdict.acceptance == "accepted" and .verdict.projected_at == null' ;;
  *) echo "unknown crash marker $CRASH_MARKER" >&2; exit 2 ;;
esac
marker_hit() {
  local f
  for f in "$store"/pd-*/receipt.json; do
    [ -f "$f" ] && jq -e "$marker" "$f" >/dev/null 2>&1 && return 0
  done
  return 1
}

turn=0 session="" crashed=""
# host <session or empty> <prompt> [marker]: one host turn; sets $session,
# and $crashed when the marker killed it.
host() {
  turn=$((turn + 1))
  local label args hpid watch="${3:-}"
  label="$(printf '%02d' "$turn")"
  args=(claude -p --output-format stream-json --verbose --permission-mode acceptEdits --allowedTools=Bash)
  [ -z "$1" ] || args+=(--resume "$1")
  printf '%s\n' "$2" >"$out/transcripts/$label.prompt.txt"
  (cd "$fx" && exec perl -e 'setpgrp(0, 0); exec @ARGV' "${args[@]}" "$2") </dev/null \
    >"$out/transcripts/$label.jsonl" 2>"$out/transcripts/$label.stderr" &
  hpid=$!
  if [ -n "$watch" ]; then
    while kill -0 "$hpid" 2>/dev/null; do
      if marker_hit; then
        kill -KILL "-$hpid" 2>/dev/null || true
        crashed="$CRASH_MARKER"
        echo "crash $CRASH_MARKER $label" >>"$events"
        echo "--- host killed at $CRASH_MARKER (turn $label)" | tee -a "$out/owner-answers.txt"
        break
      fi
      sleep 0.2
    done
  fi
  wait "$hpid" 2>/dev/null || true
  echo "turn $label" >>"$events"
  # first(): a `| head -n 1` would SIGPIPE jq on a long transcript, and
  # pipefail would then end the script.
  session="$(jq -r -n 'first(inputs | select(.session_id != null) | .session_id)' "$out/transcripts/$label.jsonl" 2>/dev/null || true)"
}

show() { # the host's last words in the latest turn
  local label
  label="$(printf '%02d' "$turn")"
  echo
  echo "================ host, turn $label ================"
  jq -r 'select(.type == "result") | .result // empty' "$out/transcripts/$label.jsonl" 2>/dev/null | tail -n 40
  echo "==================================================="
}

# turn <session or empty> <prompt>: a host turn watched for the crash marker
# until it fires once, in whichever turn that is (F14's verdict comes only
# after the owner's attestation). The crash is handled right there: the
# scenario's edit, then a new session that runs pickup.
recovered=""
turn_() {
  if [ -n "$marker" ] && [ -z "$recovered" ]; then host "$1" "$2" "$marker"; else host "$1" "$2"; fi
  if [ -n "$crashed" ] && [ -z "$recovered" ]; then
    recovered=1
    if declare -F after_crash >/dev/null; then
      after_crash "$fx"
      echo "after_crash" >>"$events"
      echo "--- after_crash applied" | tee -a "$out/owner-answers.txt"
    fi
    host "" "$PICKUP_PROMPT"
    echo "pickup $(printf '%02d' "$turn")" >>"$events"
  fi
}

turn_ "" "$DISPATCH_PROMPT"
while :; do
  show
  printf 'Answer the host as %s (empty line ends the run): ' "$operator"
  answer=""
  IFS= read -r answer </dev/tty || answer=""
  [ -n "$answer" ] || break
  printf '[%s] %s\n' "$operator" "$answer" >>"$out/owner-answers.txt"
  turn_ "$session" "$answer"
done

"$here/collect.sh" "$fx" "$out"
echo "$fx" >"$out/fixture-path"
"$here/oracle.sh" "$out" | tee "$out/oracle.txt"
