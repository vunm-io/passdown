# Contributing

passdown is a small, dogfooding project (public beta) — contributions are
welcome, but keep changes focused and validated before opening a PR.

## Before opening a PR

1. Read [`AGENTS.md`](AGENTS.md) — it's the source of truth for how this
   repo is built and what to run before committing each kind of change
   (schema, `install.sh`, JSON manifests, skills).
2. Run the relevant validation for what you touched:
   ```bash
   ./scripts/validate-plugin.sh        # bash/macOS/Linux
   .\scripts\validate-plugin.ps1       # Windows PowerShell
   ```
3. If your change touches `install.sh`, the plugin manifests, or
   `schemas/passdown/`, run through [`docs/SMOKE_TEST.md`](docs/SMOKE_TEST.md)
   for the sections that apply.
4. Use [Conventional Commits](https://www.conventionalcommits.org/)
   (`fix:`, `feat:`, `docs:`, `chore:`, ...), English, imperative mood.

## Scope

- One PR = one logical change. No merge commits — rebase, don't merge `main`
  into your branch.
- Don't add features or abstractions beyond what's asked — see the project's
  own bias toward small, workspace-agnostic skills over configuration
  sprawl.

## Reporting bugs vs. security issues

Regular bugs: open a GitHub issue. Security or private-data issues: see
[`SECURITY.md`](SECURITY.md) instead — don't post those publicly.
