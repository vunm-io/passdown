#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validate the passdown marketplace + plugin manifests with the Claude Code CLI.

.DESCRIPTION
    Windows/PowerShell counterpart to scripts/validate-plugin.sh. Runs
    `claude plugin validate --strict` against both the marketplace manifest
    (repo root) and the plugin manifest (plugins/passdown). `--strict` treats
    warnings (unrecognized fields, missing metadata) as errors, so this is the
    gate to run before tagging a release and before flipping the repo public.

    Exists because Git Bash / WSL path conversion can mangle the paths
    `validate-plugin.sh` passes to `claude plugin validate` on Windows.
    This script uses native PowerShell paths instead. It does not replace
    validate-plugin.sh; use whichever matches your shell.

.EXAMPLE
    .\scripts\validate-plugin.ps1
#>

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Error "ERROR: 'claude' CLI not found on PATH. Install it: npm i -g @anthropic-ai/claude-code`n       (plugin validation is offline and does not need auth/login)"
    exit 1
}

$claudeVersion = (claude --version 2>$null)
if (-not $claudeVersion) { $claudeVersion = "(version unknown)" }
Write-Host "claude $claudeVersion"

Write-Host "==> Validating marketplace manifest (strict)"
claude plugin validate "$repoRoot" --strict
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "==> Validating plugin manifest (strict)"
claude plugin validate (Join-Path $repoRoot "plugins\passdown") --strict
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "==> Plugin validation passed."
