# Plan

## Tasks

- [x] 1.1 Add the greeting [dispatch: fake]
  - Paths: src/
  - Done criteria: src/hello.txt says hello
  - Verification: `grep -q hello src/hello.txt`
  - Dispatched: fake (2026-09-28) — rejected: invalid result; verified: -; attempt: pd-20260928T162825Z-654f6346
  - Dispatched: fake (2026-09-28) — accepted; verified: grep -q hello src/hello.txt; attempt: pd-20260928T164421Z-8b87d095

- [ ] 1.2 Add a farewell [dispatch: main]
  - Paths: src/
  - Done criteria: src/bye.txt exists
  - Verification: `test -f src/bye.txt`
