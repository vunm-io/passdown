---
card: fake
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
  structured_output: verified
  native_schema_enforcement: unsupported
  resume_session: unverified
  session_id_observable: unverified
  exit_code_meaningful: verified
  descendants_may_outlive: unverified
  cancel_signal_honored: unverified
  read_only_mode: unverified
  sandbox_confined_writes: unverified
stop:
  containment: [pgroup]
  settle_seconds: 0
---
Test-only card: nothing measured about descendants, so a parent exit is never
a safe stop.
