#!/usr/bin/env bash
# Install passdown skills and optional OpenSpec schema into user-level locations.
#
#   ./install.sh                         # Claude Code (+ Kiro if present) + schema
#   ./install.sh --host codex            # selected host + schema
#   ./install.sh --host claude --skills-only
#   ./install.sh --into <repo>           # repo-local schema only
#
# Skills and the OpenSpec schema are installed as real copies. Re-run this
# script after editing source files to synchronize an existing direct install.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_DIR/plugins/passdown/skills"

usage() {
  cat <<'EOF'
Usage:
  ./install.sh
  ./install.sh --host <claude|codex|kiro> [--host <host> ...] [--skills-only]
  ./install.sh --into <existing-repo-dir>
  ./install.sh --help

Without --host, installs Claude Code skills, Kiro skills when ~/.kiro exists,
and the user-level OpenSpec schema. Add --skills-only to install Passdown
without copying the optional OpenSpec schema. --into copies only the repo-local
OpenSpec schema and cannot be combined with --host or --skills-only. Use one
install channel per host: plugin or script, never both.
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
install_schema=true
into_dir=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --skills-only)
      install_schema=false
      shift
      ;;
    --into)
      if [ "$#" -lt 2 ] || [ ! -d "$2" ] || [ -n "$into_dir" ]; then
        usage >&2
        exit 1
      fi
      into_dir="${2%/}"
      shift 2
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

if [ -n "$into_dir" ]; then
  if [ "${#hosts[@]}" -gt 0 ] || [ "$install_schema" = false ]; then
    echo "ERROR: --into cannot be combined with --host or --skills-only" >&2
    usage >&2
    exit 1
  fi
  copy_schema "$into_dir/openspec/schemas/passdown"
  exit 0
fi

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

if [ "$install_schema" = true ]; then
  if [ -f "$REPO_DIR/schemas/passdown/schema.yaml" ]; then
    copy_schema "$HOME/.local/share/openspec/schemas/passdown"
  else
    echo "NOTE  schemas/passdown/schema.yaml not generated yet — skipping OpenSpec schema copy"
  fi
else
  echo "SKIP  optional OpenSpec schema (--skills-only)"
fi

echo "Done."
