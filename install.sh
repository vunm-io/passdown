#!/usr/bin/env bash
# Symlink passdown skills and schema into user-level locations so they are
# available in every repo, for every tool that reads them.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_DIR/plugins/passdown/skills"

link() { # link <src> <dst>
  mkdir -p "$(dirname "$2")"
  if [ -e "$2" ] && [ ! -L "$2" ]; then
    echo "SKIP  $2 exists and is not a symlink — resolve manually"
    return
  fi
  ln -sfn "$1" "$2"
  echo "LINK  $2 -> $1"
}

# Claude Code (user-level skills)
for skill in "$SKILLS_SRC"/*/; do
  name="$(basename "$skill")"
  link "${skill%/}" "$HOME/.claude/skills/$name"
done

# Kiro (user-level skills), only if Kiro is present
if [ -d "$HOME/.kiro" ]; then
  for skill in "$SKILLS_SRC"/*/; do
    name="$(basename "$skill")"
    link "${skill%/}" "$HOME/.kiro/skills/$name"
  done
fi

# OpenSpec user-level schema (once schema.yaml has been generated — see schemas/passdown/README.md)
if [ -f "$REPO_DIR/schemas/passdown/schema.yaml" ]; then
  link "$REPO_DIR/schemas/passdown" "$HOME/.local/share/openspec/schemas/passdown"
else
  echo "NOTE  schemas/passdown/schema.yaml not generated yet — skipping OpenSpec schema link"
fi

echo "Done."
