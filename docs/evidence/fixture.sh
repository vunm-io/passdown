#!/usr/bin/env bash
# fixture.sh <dir>: build the disposable fixture repository the executor
# measurements (E-KIRO-1, E-CLAUDE-1, E-CODEX-1) run against: a committed
# base and a four-task plan (read, bounded write, ambiguous, long-running).
set -euo pipefail
fx="${1:?fixture directory}"
[ ! -e "$fx" ] || { echo "fixture.sh: $fx exists; use a fresh directory" >&2; exit 2; }
mkdir -p "$fx"
cd "$fx"
git init -q -b main
git config user.email fixture@example.com
git config user.name fixture
git config commit.gpgsign false
mkdir -p docs src config
printf 'line one\nline two\nline three\n' >src/base.txt
printf '[app]\nold_key = 1\n' >config/app.toml
cat >docs/plan.md <<'EOF'
# Plan

## Tasks

- [ ] 1.1 Create the greeting file [dispatch: external-ok]
  - Paths: src/greeting.txt
  - Done criteria: src/greeting.txt contains exactly one line, `hello`
  - Verification: `grep -qx hello src/greeting.txt`

- [ ] 2.1 Count the lines of the base file [dispatch: external-ok]
  - Paths: docs/review/
  - Done criteria: the line count of src/base.txt is reported in the result summary; no file changes
  - Verification: `true`

- [ ] 3.1 Rename the config key to the name the team agreed on [dispatch: external-ok]
  - Paths: config/app.toml
  - Done criteria: `old_key` in config/app.toml is renamed to the agreed name
  - Verification: `! grep -q old_key config/app.toml`

- [ ] 4.1 Write a slow counter [dispatch: external-ok]
  - Paths: src/count.txt
  - Done criteria: src/count.txt holds the numbers 1 to 40, one per line, appended one at a time with a one-second pause between appends (use a shell loop with `sleep 1`)
  - Verification: `[ "$(wc -l < src/count.txt)" -eq 40 ]`
EOF
git add -A
git commit -qm base
