# Release checklist

How to cut a passdown release and take the repo public. Everything here is a
manual gate — run it top to bottom. Nothing in this file changes repo
visibility automatically.

## 0. Version sync

A release bumps `version` in **both** manifests to the same value:

- `.claude-plugin/marketplace.json` — top-level `metadata.version` **and** the
  `passdown` plugin entry's `version`.
- `plugins/passdown/.claude-plugin/plugin.json` — `version`.

For `v0.1.0` these are already `0.1.0`. Bump all three together for any later
release.

```bash
grep -R '"version"' .claude-plugin/marketplace.json plugins/passdown/.claude-plugin/plugin.json
```

## 1. Green CI

Push the branch and confirm the `ci` workflow passes: JSON validation,
shellcheck, strict plugin validation, OpenSpec schema validation, schema-sync.

```bash
gh pr checks   # or watch the Actions tab
```

## 2. Strict plugin validation (local)

```bash
./scripts/validate-plugin.sh
```

On Windows (PowerShell), use the native counterpart instead — Git Bash/WSL
path conversion can mangle the paths passed to `claude plugin validate`:

```powershell
.\scripts\validate-plugin.ps1
```

Both marketplace + plugin manifests must print `✔ Validation passed` with
exit 0. Optionally, sanity-check the release tag agreement:

```bash
claude plugin tag plugins/passdown   # validates plugin.json vs. marketplace entry
```

## 3. Smoke test

Run `docs/SMOKE_TEST.md` end to end. The isolated sections (0, 2, 6) are the
same checks CI runs; section 4 (Codex/Antigravity executor config) is a doc
sanity check you can run any time. Sections 3 and 5 (plugin channel + live
skill triggering) can only be fully exercised once the repo is public — do
those right after step 7 (Go public).

## 4. Secrets / privacy scan

```bash
git grep -nIE 'ghp_|sk-[a-zA-Z0-9]{10,}|xox[baprs]-|BEGIN [A-Z]+ PRIVATE KEY|AKIA[0-9A-Z]{16}|@gmail\.com|/Users/[a-z]+' -- . ':!*.lock'
```

Expect no matches. Confirm README / examples / logs contain no tokens,
credentials, or private workspace paths.

## 5. Doc clarity gate (host vs. executor)

Before going public, re-read `README.md` end to end and confirm it cannot be
misread as:

- [ ] Codex or Antigravity being install targets rather than dispatch
      executors (the "Support matrix" section must draw this line)
- [ ] Kiro being anything other than a secondary, user-level skill host
- [ ] Temporal status notes in the README (e.g. "not yet public",
      "coming soon") — the shipped README should read as a finished public
      project; keep any private-window caveats in this checklist, not in
      user-facing copy

If any of the above reads ambiguously, fix the wording before tagging.

## 6. Tag

Follow the repo convention (`vX.Y.Z`, annotated):

```bash
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

## 7. Go public

> Do this only when you have decided to publish. It is not reversible in the
> same way a code change is — the code and history become world-readable.

```bash
gh repo edit vunm-io/passdown --visibility public --accept-visibility-change-consequences
```

## 8. Verify the public install path

From a clean machine / fresh Claude Code session:

```bash
claude plugin marketplace add vunm-io/passdown
claude plugin install passdown@passdown
```

- Plugin appears under Personal plugins.
- `passdown:passdown-intake`, `passdown:passdown-dispatch`,
  `passdown:passdown-handoff` load under the `passdown` namespace.
- No double-load (do not also run `./install.sh`).

## 9. (Optional) Submit to the community marketplace

Once the public install is verified, submit the repo to the Claude community
marketplace via the Console / claude.ai submission form. The official
Anthropic-curated marketplace has no direct application process — nothing to
submit there.
