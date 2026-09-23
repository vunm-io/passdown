---
card: fake-overclaims
card_version: 1
measured:
  date: 2026-09-23
  host_os: test
  cli_version: 0.0.0
  engine: null
  by: tests/interrupt.sh
  evidence: none (test card)
capabilities:
  headless: verified
  structured_output: verified
  descendants_may_outlive: unsupported   # wrong on purpose: the worker does detach
stop:
  containment: [pgroup]
  settle_seconds: 2
---
Test-only card that wrongly claims its executor never detaches (fixture F18b).
Its settle window is the only thing between a late write and acceptance.
