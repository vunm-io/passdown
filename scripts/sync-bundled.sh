#!/usr/bin/env bash
# Copy the canonical attempt helper and protocol schemas into every skill
# that ships them. Each install channel copies skill directories wholesale,
# and a skill can only rely on files inside its own directory, so the copies
# must be byte-identical to the canonical sources.
#
#   scripts/sync-bundled.sh           write the copies
#   scripts/sync-bundled.sh --check   exit 1 if any copy has drifted (CI)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skills="$repo_root/plugins/passdown/skills"
check=0
case "${1:-}" in
  --check) check=1 ;;
  "") ;;
  *)
    echo "usage: scripts/sync-bundled.sh [--check]" >&2
    exit 2
    ;;
esac

# <canonical source> <path inside the skill directory>
bundle=(
  "scripts/passdown-attempt" "scripts/passdown-attempt"
  "schemas/protocol/receipt.v1.schema.json" "schemas/receipt.v1.schema.json"
  "schemas/protocol/result.v1.schema.json" "schemas/result.v1.schema.json"
  "schemas/protocol/claim.v1.schema.json" "schemas/claim.v1.schema.json"
)

drift=0
for skill in passdown-dispatch passdown-pickup passdown-handoff; do
  i=0
  while [ "$i" -lt "${#bundle[@]}" ]; do
    src="$repo_root/${bundle[$i]}"
    dst="$skills/$skill/${bundle[$((i + 1))]}"
    i=$((i + 2))
    if [ "$check" = 1 ]; then
      if ! cmp -s "$src" "$dst"; then
        echo "DRIFT: ${dst#"$repo_root"/} differs from ${src#"$repo_root"/}" >&2
        drift=1
      elif [ -x "$src" ] && [ ! -x "$dst" ]; then
        echo "DRIFT: ${dst#"$repo_root"/} is not executable" >&2
        drift=1
      fi
    else
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      [ ! -x "$src" ] || chmod +x "$dst"
    fi
  done
done

if [ "$check" = 1 ]; then
  [ "$drift" = 0 ] || {
    echo "Run scripts/sync-bundled.sh and commit the result." >&2
    exit 1
  }
  echo "Bundled helper and schemas match their canonical sources."
fi
