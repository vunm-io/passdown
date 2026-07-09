# Release checklist

Recurring process for publishing passdown. Releases move forward from
protected `main`; v0 does not maintain old minor release branches.

Repository merge methods and the `main` ruleset must match
[`GITHUB_SETTINGS.md`](GITHUB_SETTINGS.md).

## Historical follow-up

The annotated `v0.1.0` tag exists, but its GitHub prerelease is still pending.
Create it from the existing tag after GitHub CLI authentication is restored:

```bash
gh release create v0.1.0 \
  --repo vunm-io/passdown \
  --verify-tag \
  --prerelease \
  --title "passdown v0.1.0 — initial dogfooding release" \
  --notes "Initial snapshot of the three passdown skills, installer, and OpenSpec schema. Later public-readiness changes remained on main and are released in v0.2.0."
```

Never move, delete, or recreate the historical tag.

## 1. Prepare a release branch

Create a short-lived branch such as `release/v0.2.0`. Update:

- `VERSION`
- `.claude-plugin/marketplace.json` metadata + plugin versions
- `plugins/passdown/.claude-plugin/plugin.json`
- `plugins/passdown/.codex-plugin/plugin.json`
- `CHANGELOG.md`

Run:

```bash
./scripts/check-version.sh
./scripts/release-notes.sh "$(cat VERSION)"
```

## 2. Run the complete gate

```bash
bash -n install.sh scripts/*.sh tests/*.sh
shellcheck install.sh scripts/*.sh tests/*.sh
./tests/install.sh
./tests/skills.sh
./tests/version.sh
./tests/release.sh
./scripts/validate-plugin.sh

scratch="$(mktemp -d)"
./install.sh --into "$scratch"
(cd "$scratch" && openspec schema validate passdown)
diff -r schemas/passdown examples/basic-workspace/openspec/schemas/passdown
```

Run the live Claude Code and Codex sections in `docs/SMOKE_TEST.md`.

## 3. Merge through a PR

Push the release branch, open a PR, and wait for the `validate` job. Squash or
rebase into `main`; do not use a merge commit. Delete the release branch after
merge.

Confirm `main` CI is green before tagging.

## 4. Tag the release

Create an annotated tag from the verified `main` commit:

```bash
version="$(cat VERSION)"
git switch main
git pull --ff-only
./scripts/check-version.sh --tag "v$version"
git tag -a "v$version" -m "passdown v$version"
git push origin "v$version"
```

The `release` workflow validates the tagged tree again and creates the GitHub
Release from the matching CHANGELOG section. Do not create or move the tag if
any gate is red.

## 5. Verify distribution

From clean Claude Code and Codex homes:

```bash
claude plugin marketplace add vunm-io/passdown
claude plugin install passdown@passdown

codex plugin marketplace add vunm-io/passdown
codex plugin add passdown@passdown
```

Confirm all three skills load exactly once and the installed version matches
`VERSION`. Do not combine plugin and direct skill installs for the same host.

## 6. Optional marketplace submission

After both public install paths pass, update or submit the plugin listing in
the relevant community directory. Marketplace submission is downstream of the
GitHub Release, never a substitute for it.
