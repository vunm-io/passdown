---
card: fake-measured
card_version: 1
measured:
  date: 2026-09-21
  host_os: test
  cli_version: 0.0.0
  engine: null
  by: tests/attempt.sh
  evidence: none (test card)
capabilities:
  headless: verified
  descendants_may_outlive: unsupported   # measured: never detaches
  read_only_mode: verified               # measured: plan mode removes write tools
  sandbox_confined_writes: unverified
stop:
  containment: [pgroup]
  settle_seconds: 1
---
Test-only card: measured not to detach, with a read-only mode and a one-second
settle window.
