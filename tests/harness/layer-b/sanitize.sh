#!/usr/bin/env bash
# sanitize.sh <out>...: prepare Layer B run directories for publication, as
# was done by hand for docs/evidence/e-claude-1/. Safe to run twice.
#
#   - paths: the fixture's temporary directory becomes /fixture (receipts
#     require absolute paths), other temporary paths /tmp, this repository
#     <repo>, and the home directory ~; the operator's Git e-mail (which a
#     host may repeat from its context) becomes <owner-email>;
#   - init events keep the Claude Code version, the model, the permission
#     mode, counts, and the passdown plugin and skills only: the operator's
#     other tools, MCP servers, plugins and agents are not published;
#   - hook events lose their output (the operator's hooks);
#   - rate-limit events lose the account details;
#   - thinking_tokens events, progress counters with no content, are dropped,
#     and so are the opaque signatures of thinking blocks.
#
# oracle.sh judges the sanitized copy the same way; run it after this.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo="$(cd "$here/../../.." && pwd -P)"
export REPO="$repo"
OWNER_EMAIL="$(git -C "$repo" config user.email || true)"
export OWNER_EMAIL

for out in "$@"; do
  [ -f "$out/scenario" ] || { echo "sanitize.sh: $out is not a run directory" >&2; exit 2; }
  fx=""
  [ ! -f "$out/fixture-path" ] || fx="$(cat "$out/fixture-path")"
  # The fixture can appear as /var/... or through its /private/var/... alias.
  subs=() nfx=0
  if [ -n "$fx" ] && [ "$fx" != /fixture ]; then
    subs+=("/private$fx" "$fx")
    fx_slug="$(printf '%s' "/private$fx" | tr '/._' '---')"
    subs+=("$fx_slug" "$(printf '%s' "$fx" | tr '/._' '---')")
    nfx=4
  fi
  tmp="${TMPDIR:-/tmp/}"
  tmp="${tmp%/}"
  subs+=("/private$tmp" "$tmp" "$repo" "$HOME")
  for t in "$out"/transcripts/*.jsonl; do
    [ -f "$t" ] || continue
    jq -c '
      if .x_note then .
      elif .type == "system" and .subtype == "thinking_tokens" then empty
      elif .type == "system" and .subtype == "init" then
        {type, subtype, session_id, claude_code_version, model, permissionMode,
         tools: (.tools | length), mcp_servers: (.mcp_servers | length),
         plugins: [.plugins[]? | select(.name == "passdown") | {name, source, version: (.path | split("/") | last)}],
         other_plugins: ([.plugins[]? | select(.name != "passdown")] | length),
         skills: [.skills[]? | select(startswith("passdown"))],
         x_note: "reduced for publication: names of the operator'"'"'s tools, MCP servers, plugins, agents and paths removed"}
      elif .type == "system" and (.subtype == "hook_started" or .subtype == "hook_response") then
        {type, subtype, session_id, hook_event, x_note: "hook output omitted"}
      elif .type == "rate_limit_event" then
        {type, session_id, x_note: "account details omitted"}
      else walk(if type == "object" and has("signature") then del(.signature) else . end) end' "$t" >"$t.tmp"
    mv "$t.tmp" "$t"
  done
  # Literal replacement, longest first (the fixture before the home dir).
  while IFS= read -r -d '' f; do
    NFX="$nfx" SUBS="$(printf '%s\n' "${subs[@]}")" perl -0pi -e '
      BEGIN { my @s = split /\n/, $ENV{SUBS}; our @pairs;
        for (my $i = 0; $i < @s; $i++) {
          my $to = $i < $ENV{NFX} ? ($s[$i] =~ m{^-} ? "-fixture" : "/fixture")
                 : $s[$i] eq $ENV{REPO} ? "<repo>"
                 : $s[$i] eq $ENV{HOME} ? "~" : "/tmp";
          push @pairs, [$s[$i], $to] }
        push @pairs, [$ENV{OWNER_EMAIL}, "<owner-email>"] if $ENV{OWNER_EMAIL} ne "" }
      for my $p (our @pairs) { my ($from, $to) = @$p; s/\Q$from\E/$to/g }' "$f"
  done < <(find "$out" -type f ! -name "*.png" -print0)
done
