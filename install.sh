#!/usr/bin/env bash
# Install passdown skills and schema into user-level locations so they are
# available in every repo, for every tool that reads them.
#
#   ./install.sh                         # Claude Code (+ Kiro if present) + schema
#   ./install.sh --host codex            # selected host + schema
#   ./install.sh --host claude --host kiro
#   ./install.sh --into <repo>           # repo-local schema only
#
# Claude Code skills are installed as REAL copies: its desktop skill browser
# does not list symlinked entries (the CLI runtime does, but the UI is the
# stricter consumer). Re-run this script after editing skills to sync.
# Codex and Kiro receive the same real copies when selected explicitly.
#
# The OpenSpec schema is also installed as a REAL copy: the openspec CLI
# (1.5.0) ignores symlinked schema directories in `new change`, `status`, and
# `instructions apply` ("Unknown schema"), even though `schema which` resolves
# them. Re-run this script after editing the schema to sync.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_DIR/plugins/passdown/skills"

usage() {
  cat <<'EOF'
Usage:
  ./install.sh
  ./install.sh --host <claude|codex|kiro> [--host <host> ...]
  ./install.sh --into <existing-repo-dir>
  ./install.sh --help

Without --host, installs Claude Code skills, Kiro skills when ~/.kiro exists,
and the user-level OpenSpec schema. Use one install channel per host: plugin or
script, never both.
EOF
}

copy_skill() { # copy_skill <skill-src-dir> <dst-parent>
  local src="${1%/}"
  local dst dst_parent tmp
  dst_parent="${2%/}"
  dst="$2/$(basename "$1")"
  if [ -e "$dst" ] && [ ! -d "$dst" ] && [ ! -L "$dst" ]; then
    echo "ERROR: $dst exists and is not a directory — resolve manually" >&2
    return 1
  fi
  mkdir -p "$dst_parent"
  tmp="$(mktemp -d "$dst_parent/.passdown-$(basename "$src").XXXXXX")"
  cp -R "$src/." "$tmp/"
  rm -rf "$dst"
  mv "$tmp" "$dst"
  echo "COPY  $dst <- $src"
}

copy_schema() { # copy_schema <dst-dir>
  local src="$REPO_DIR/schemas/passdown" dst="${1%/}" parent tmp
  if [ -e "$dst" ] && [ ! -d "$dst" ] && [ ! -L "$dst" ]; then
    echo "ERROR: $dst exists and is not a directory — resolve manually" >&2
    return 1
  fi
  parent="$(dirname "$dst")"
  mkdir -p "$parent"
  tmp="$(mktemp -d "$parent/.passdown-schema.XXXXXX")"
  cp -R "$src/." "$tmp/"
  rm -rf "$dst"
  mv "$tmp" "$dst"
  echo "COPY  $dst <- $src"
}

hosts=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --into)
      if [ "$#" -ne 2 ] || [ ! -d "$2" ]; then
        usage >&2
        exit 1
      fi
      copy_schema "${2%/}/openspec/schemas/passdown"
      exit 0
      ;;
    --host)
      if [ "$#" -lt 2 ]; then
        usage >&2
        exit 1
      fi
      case "$2" in
        claude|codex|kiro) hosts+=("$2") ;;
        *)
          echo "ERROR: unknown host '$2'" >&2
          usage >&2
          exit 1
          ;;
      esac
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ "${#hosts[@]}" -eq 0 ]; then
  hosts=(claude)
  if [ -d "$HOME/.kiro" ]; then
    hosts+=(kiro)
  fi
fi

for host in "${hosts[@]}"; do
  case "$host" in
    claude) skills_dst="$HOME/.claude/skills" ;;
    codex) skills_dst="$HOME/.agents/skills" ;;
    kiro) skills_dst="$HOME/.kiro/skills" ;;
  esac
  for skill in "$SKILLS_SRC"/*/; do
    copy_skill "$skill" "$skills_dst"
  done
done

# OpenSpec user-level schema — real copy, see header note
if [ -f "$REPO_DIR/schemas/passdown/schema.yaml" ]; then
  copy_schema "$HOME/.local/share/openspec/schemas/passdown"
else
  echo "NOTE  schemas/passdown/schema.yaml not generated yet — skipping OpenSpec schema copy"
fi

echo "Done."
