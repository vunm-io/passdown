#!/usr/bin/env bash
# collect.sh <fixture> <out>: copy what the Layer B oracle reads out of a
# fixture workspace after a run: receipts, claims, plan, worker journals,
# Git status, and — for every accepted receipt — the artifact digest of the
# final tree, computed live, so that oracle.sh can run later on the copy.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
helper="$here/../../../scripts/passdown-attempt"
fx="${1:?fixture}"
out="${2:?out}"
store="$fx/.git/passdown/attempts"
mkdir -p "$out"
rm -rf "$out/store" "$out/claims"
if [ -d "$store" ]; then
  mkdir -p "$out/store"
  for d in "$store"/pd-*; do
    [ -d "$d" ] || continue
    mkdir -p "$out/store/${d##*/}"
    for f in receipt.json result.json card.md prompt.md transport.log inspect.json; do
      [ ! -f "$d/$f" ] || cp "$d/$f" "$out/store/${d##*/}/$f"
    done
  done
fi
[ ! -d "$fx/.git/passdown/claims" ] || cp -R "$fx/.git/passdown/claims" "$out/claims"
cp "$fx/docs/plan.md" "$out/plan.md"
git -C "$fx" status --porcelain >"$out/git-status.txt"
git -C "$fx" diff >"$out/git-diff.txt"
cp "$fx.journal" "$out/journal"
cp "$fx.journal.life" "$out/journal.life"
: >"$out/artifact-digests.txt"
for f in "$store"/pd-*/receipt.json; do
  [ -f "$f" ] || continue
  [ "$(jq -r .verdict.acceptance "$f")" = accepted ] || continue
  id="$(jq -r .id "$f")"
  printf '%s %s\n' "$id" "$("$helper" --store "$store" digest artifact "$id")" >>"$out/artifact-digests.txt"
done
( cd "$fx" && find src -type f | sort ) >"$out/src-files.txt"
