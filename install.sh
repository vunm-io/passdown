#!/usr/bin/env bash
# Install passdown skills and schema into user-level locations so they are
# available in every repo, for every tool that reads them.
#
# Skills are installed as REAL directories containing symlinked files: some
# UIs (e.g. Claude Code's skill browser) skip symlinked directories, while
# runtimes follow file symlinks fine — this layout satisfies both, and edits
# in the repo still apply immediately.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_DIR/plugins/passdown/skills"

install_skill() { # install_skill <skill-src-dir> <dst-parent>
  local src="${1%/}" dst="$2/$(basename "$1")"
  if [ -L "$dst" ]; then rm "$dst"; fi
  if [ -e "$dst" ] && [ ! -d "$dst" ]; then
    echo "SKIP  $dst exists and is not a directory — resolve manually"
    return
  fi
  mkdir -p "$dst"
  local f name
  for f in "$src"/*; do
    name="$(basename "$f")"
    if [ -e "$dst/$name" ] && [ ! -L "$dst/$name" ]; then
      echo "SKIP  $dst/$name exists and is not a symlink — resolve manually"
      continue
    fi
    ln -sfn "$f" "$dst/$name"
  done
  echo "SKILL $dst -> $src"
}

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
  install_skill "$skill" "$HOME/.claude/skills"
done

# Kiro (user-level skills), only if Kiro is present
if [ -d "$HOME/.kiro" ]; then
  for skill in "$SKILLS_SRC"/*/; do
    install_skill "$skill" "$HOME/.kiro/skills"
  done
fi

# OpenSpec user-level schema
if [ -f "$REPO_DIR/schemas/passdown/schema.yaml" ]; then
  link "$REPO_DIR/schemas/passdown" "$HOME/.local/share/openspec/schemas/passdown"
else
  echo "NOTE  schemas/passdown/schema.yaml not generated yet — skipping OpenSpec schema link"
fi

echo "Done."
