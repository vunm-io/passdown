# Plan

## Tasks

- [ ] 1.1 Add the greeting [dispatch: external-ok]
  - Paths: src/
  - Done criteria: src/hello.txt says hello
  - Verification: `grep -q hello src/hello.txt`
  - Dispatched: fake (2026-09-28) — rejected: plan tampered; verified: -; attempt: pd-20260928T103121Z-124d1761

- [ ] 1.2 Add a farewell [dispatch: main]
  - Paths: src/
  - Done criteria: src/bye.txt exists
  - Verification: `test -f src/bye.txt`
