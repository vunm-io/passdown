#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-}"

if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([-+][0-9A-Za-z.-]+)?$ ]]; then
  echo "Usage: scripts/release-notes.sh <X.Y.Z>" >&2
  exit 1
fi

awk -v version="$version" '
  $0 == "## [" version "]" || index($0, "## [" version "] - ") == 1 {
    found = 1
    next
  }
  found && /^## \[/ {
    exit
  }
  found {
    print
  }
  END {
    if (!found) {
      exit 1
    }
  }
' "$repo_root/CHANGELOG.md"
