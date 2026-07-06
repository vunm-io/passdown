#!/usr/bin/env bash
# Validate the passdown marketplace + plugin manifests with the Claude Code CLI.
#
#   scripts/validate-plugin.sh
#
# Runs `claude plugin validate --strict` against both the marketplace manifest
# (repo root) and the plugin manifest (plugins/passdown). `--strict` treats
# warnings (unrecognized fields, missing metadata) as errors, so this is the
# gate to run before tagging a release and before flipping the repo public.
#
# Used by CI (which installs the CLI first) and as a manual pre-release gate.
# If the `claude` CLI is not installed, this exits non-zero — install it with
# `npm i -g @anthropic-ai/claude-code` (or Homebrew) and re-run.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: 'claude' CLI not found on PATH." >&2
  echo "       Install it: npm i -g @anthropic-ai/claude-code" >&2
  echo "       (plugin validation is offline and does not need auth/login)" >&2
  exit 1
fi

echo "claude $(claude --version 2>/dev/null || echo '(version unknown)')"

echo "==> Validating marketplace manifest (strict)"
claude plugin validate "$repo_root" --strict

echo "==> Validating plugin manifest (strict)"
claude plugin validate "$repo_root/plugins/passdown" --strict

echo "==> Plugin validation passed."
