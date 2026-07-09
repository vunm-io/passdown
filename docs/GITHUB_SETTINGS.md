# GitHub repository settings

Code cannot enforce repository settings until this branch is merged. Apply
these settings to `vunm-io/passdown` before accepting further contributions.

## Pull request merge methods

- Disable merge commits.
- Enable squash merge and rebase merge.
- Enable automatic deletion of head branches.

## Active `main` ruleset

Target the default branch and enable:

- Require a pull request before merging, with zero required approvals while
  the project has one maintainer.
- Require the `validate` status check.
- Require linear history.
- Require all review conversations to be resolved.
- Block force pushes.
- Restrict branch deletion.

Maintainer bypass may be allowed for repository recovery, but normal releases
and implementation changes still go through short-lived branches and green
pull requests.

## Tag and release policy

- Tags matching `v*.*.*` are created only from a green `main` commit.
- Never move or recreate a published version tag.
- Let `.github/workflows/release.yml` create the GitHub Release after its
  validation gate passes.
- Optionally enable immutable releases after the v0.2.0 workflow is proven.
