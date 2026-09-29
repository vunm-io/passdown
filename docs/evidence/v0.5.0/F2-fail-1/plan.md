# Plan

## Tasks

- [x] 1.1 Add the greeting [dispatch: external-ok]
  - Dispatched: fake (2026-09-28) — accepted; verified: grep -q hello src/hello.txt; attempt: pd-20260927T170232Z-60bff59d
  - Paths: src/
  - Done criteria: src/hello.txt says hello
  - Verification: `grep -q hello src/hello.txt`

- [x] 1.2 Add a farewell [dispatch: main]
  - Dispatched: main (2026-09-28) — accepted; verified: test -f src/bye.txt
  - Paths: src/
  - Done criteria: src/bye.txt exists
  - Verification: `test -f src/bye.txt`
