#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_tag=""

usage() {
  echo "Usage: scripts/check-version.sh [--root <repo>] [--tag <vX.Y.Z>]"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 1
      }
      repo_root="$(cd "$2" && pwd)"
      shift 2
      ;;
    --tag)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 1
      }
      release_tag="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

version_file="$repo_root/VERSION"
[ -f "$version_file" ] || {
  echo "ERROR: VERSION is missing" >&2
  exit 1
}

version="$(tr -d '[:space:]' <"$version_file")"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([-+][0-9A-Za-z.-]+)?$ ]]; then
  echo "ERROR: VERSION '$version' is not valid SemVer" >&2
  exit 1
fi

declare -a labels=(
  "Claude marketplace metadata"
  "Claude marketplace plugin"
  "Claude plugin"
  "Codex plugin"
)
declare -a values=(
  "$(jq -r '.metadata.version' "$repo_root/.claude-plugin/marketplace.json")"
  "$(jq -r '.plugins[] | select(.name == "passdown") | .version' "$repo_root/.claude-plugin/marketplace.json")"
  "$(jq -r '.version' "$repo_root/plugins/passdown/.claude-plugin/plugin.json")"
  "$(jq -r '.version' "$repo_root/plugins/passdown/.codex-plugin/plugin.json")"
)

for i in "${!labels[@]}"; do
  if [ "${values[$i]}" != "$version" ]; then
    echo "ERROR: ${labels[$i]} version '${values[$i]}' != VERSION '$version'" >&2
    exit 1
  fi
done

codex_marketplace_name="$(
  jq -r '.plugins[] | select(.name == "passdown") | .name' \
    "$repo_root/.agents/plugins/marketplace.json"
)"
[ "$codex_marketplace_name" = "passdown" ] || {
  echo "ERROR: Codex marketplace does not expose passdown" >&2
  exit 1
}

if [ -n "$release_tag" ] && [ "$release_tag" != "v$version" ]; then
  echo "ERROR: release tag '$release_tag' != 'v$version'" >&2
  exit 1
fi

echo "Version check passed: $version"
