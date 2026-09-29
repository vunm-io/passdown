# Plan

## Tasks

- [x] 1.1 Add the greeting [dispatch: fake]
  - Paths: src/
  - Done criteria: src/hello.txt says hello
  - Verification: `grep -q hello src/hello.txt`
  - Dispatched: fake (2026-09-27) — rejected: plan tampered; verified: -; attempt: pd-20260926T173842Z-0c67dcab
  - Dispatched: main (2026-09-27) — accepted; verified: grep -q hello src/hello.txt

- [ ] 1.2 Add a farewell [dispatch: main]
  - Paths: src/
  - Done criteria: src/bye.txt exists
  - Verification: `test -f src/bye.txt`
