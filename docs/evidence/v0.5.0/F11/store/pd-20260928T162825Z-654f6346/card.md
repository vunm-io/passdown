---
card: fake
card_version: 1
measured:
  date: 2026-09-25
  host_os: test
  cli_version: 0.0.0
  engine: null
  by: tests/harness/layer-b/fixture.sh
  evidence: tests/harness/fake-executor (the test double itself)
capabilities:
  headless: verified
  structured_output: verified
  native_schema_enforcement: unsupported
  exit_code_meaningful: verified
  descendants_may_outlive: unverified
invocation:
  headless: 'env FAKE_JOURNAL=/fixture.journal FAKE_PLAN=docs/plan.md FAKE_TASK=1.1 FAKE_DELAY=0.3 FAKE_SLEEP=20 <repo>/tests/harness/layer-b/../fake-executor write-then-sleep'
  output_capture: stdout
  result_extraction: last line of stdout that is a JSON object
  cancel: { signal: INT, target: pgroup, grace_seconds: 5, then: KILL }
stop:
  containment: [pgroup]
  settle_seconds: 1
permissions:
  mechanism: none; the test double writes directly
environment_constraints: []
discovery_hint: pgrep -fl fake-executor
toolchain_check: null
---
# fake (Layer B test executor, scenario F11)

A test double, not an agent. It ignores the prompt text, performs the
`write-then-sleep` behavior from tests/harness/fake-executor on task 1.1, and prints
its passdown.result/v1 payload as the last line of stdout. It reads the
attempt ID from `PASSDOWN_ATTEMPT`, which the host must export (dispatch
step 6). Launch it from the attempt location, in a new process group, with
stdin closed.
