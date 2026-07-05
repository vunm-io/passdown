#!/usr/bin/env bash
# Install passdown skills and schema into user-level locations so they are
# available in every repo, for every tool that reads them.
#
#   ./install.sh                 # user-level install (skills + OpenSpec schema)
#   ./install.sh --into <repo>   # copy the schema into <repo>/openspec/schemas/
#
# Claude Code skills are installed as REAL copies: its desktop skill browser
# does not list symlinked entries (the CLI runtime does, but the UI is the
# stricter consumer). Re-run this script after editing skills to sync.
# Kiro gets symlinked files inside real directories (no such UI constraint).
#
# The OpenSpec schema is also installed as a REAL copy: the openspec CLI
# (1.5.0) ignores symlinked schema directories in `new change`, `status`, and
# `instructions apply` ("Unknown schema"), even though `schema which` resolves
# them. Re-run this script after editing the schema to sync.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_DIR/plugins/passdown/skills"

install_skill() { # install_skill <skill-src-dir> <dst-parent>
  local src="${1%/}"
  local dst
  dst="$2/$(basename "$1")"
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

copy_skill() { # copy_skill <skill-src-dir> <dst-parent>
  local src="${1%/}"
  local dst
  dst="$2/$(basename "$1")"
  if [ -L "$dst" ]; then rm "$dst"; fi
  if [ -d "$dst" ]; then
    find "$dst" -type l -delete
  fi
  mkdir -p "$dst"
  cp -f "$src"/* "$dst"/
  echo "COPY  $dst <- $src"
}

copy_schema() { # copy_schema <dst-dir>
  local src="$REPO_DIR/schemas/passdown" dst="${1%/}"
  if [ -L "$dst" ]; then rm "$dst"; fi
  if [ -e "$dst" ] && [ ! -d "$dst" ]; then
    echo "SKIP  $dst exists and is not a directory — resolve manually"
    return 1
  fi
  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  cp -R "$src" "$dst"
  echo "COPY  $dst <- $src"
}

# --into <repo>: copy the schema into a target repo and exit. Use this to make
# a repo self-contained (collaborators/CI get the schema without passdown).
if [ "${1:-}" = "--into" ]; then
  if [ -z "${2:-}" ] || [ ! -d "$2" ]; then
    echo "Usage: ./install.sh --into <existing-repo-dir>" >&2
    exit 1
  fi
  copy_schema "${2%/}/openspec/schemas/passdown"
  exit 0
fi

# Claude Code (user-level skills) — real copies, see header note
for skill in "$SKILLS_SRC"/*/; do
  copy_skill "$skill" "$HOME/.claude/skills"
done

# Kiro (user-level skills), only if Kiro is present
if [ -d "$HOME/.kiro" ]; then
  for skill in "$SKILLS_SRC"/*/; do
    install_skill "$skill" "$HOME/.kiro/skills"
  done
fi

# OpenSpec user-level schema — real copy, see header note
if [ -f "$REPO_DIR/schemas/passdown/schema.yaml" ]; then
  copy_schema "$HOME/.local/share/openspec/schemas/passdown"
else
  echo "NOTE  schemas/passdown/schema.yaml not generated yet — skipping OpenSpec schema copy"
fi

echo "Done."
