# Plan

## Tasks

- [x] 1.1 Add the greeting [dispatch: external-ok]
  - Paths: src/
  - Done criteria: src/hello.txt says hello
  - Verification: `grep -q hello src/hello.txt`
  - Dispatched: fake (2026-09-27) — accepted; verified: grep -q hello src/hello.txt; attempt: pd-20260927T155846Z-c6628a9f

- [ ] 1.2 Add a farewell [dispatch: main]
  - Paths: src/
  - Done criteria: src/bye.txt exists
  - Verification: `test -f src/bye.txt`
