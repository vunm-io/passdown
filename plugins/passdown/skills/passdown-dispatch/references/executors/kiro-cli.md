---
card: kiro-cli
card_version: 1
measured:
  date: 2026-09-25
  host_os: macOS 26.6.2
  cli_version: 2.24.0
  engine: v2
  by: E-KIRO-1 (passdown maintainer session, Claude)
  evidence: docs/evidence/e-kiro-1/README.md
capabilities:
  headless: verified
  structured_output: verified
  native_schema_enforcement: unsupported
  resume_session: verified
  session_id_observable: verified
  exit_code_meaningful: verified
  descendants_may_outlive: unverified
  cancel_signal_honored: verified
  read_only_mode: unverified
  sandbox_confined_writes: unverified
invocation:
  headless: 'kiro-cli chat --output-format stream-json --trust-tools=<tools> "<prompt>"'
  output_capture: stdout, ACP events as JSON Lines
  result_extraction: finalText of the last runFinished event, then its last line that is a JSON object; no runFinished event or finalTextTruncated true means no result
  resume: 'kiro-cli chat --output-format stream-json --trust-tools=<tools> --resume-id <sessionId> "<prompt>"'
  cancel: { signal: INT, target: pgroup, grace_seconds: 10, then: KILL }
stop:
  containment: [pgroup]
  settle_seconds: 5
permissions:
  mechanism: --trust-tools=<comma list>; fs_read is allowed by default, writes need fs_write, shell needs execute_bash; an untrusted tool is denied, never prompted
  notes: -a/--trust-all-tools was not used or measured
environment_constraints: [logged-in kiro-cli, runs spend Kiro credits]
discovery_hint: pgrep -fl kiro-cli-chat (ignore kiro_cli_desktop, a long-lived desktop helper that is not part of any run)
toolchain_check: null
---
# kiro-cli

Measured by E-KIRO-1 on kiro-cli 2.24.0; the full record, with every run's
transport and receipt, is `docs/evidence/e-kiro-1/` in the passdown
repository.

**Launch.** Run it from the attempt location. `--output-format stream-json`
implies non-interactive mode. Pass the trust list the task needs:

| Task | `--trust-tools=` |
|---|---|
| read or review | leave the flag out; the attempt still takes the writer claim (below) |
| edits files only | `fs_read,fs_write` |
| edits files and runs commands (tests, builds) | `fs_read,fs_write,execute_bash` |

An untrusted tool is denied with `[denied] tool permission approval is not
supported in non-interactive mode` on stderr, and a worker that follows the
environment clause returns `blocked`. That is an environment problem for the
host: fix the trust list and continue, never widen it silently. In E-KIRO-1 a
worker given only `fs_write` wrote the file and then returned `blocked`
because it could not run the verification command.

**No claim-free reads.** Without trust flags, writes and shell were denied
in E-KIRO-1, but an MCP server the user configured with auto-approval is
outside what was measured and could write. So `read_only_mode` stays
`unverified`, and a read attempt on kiro-cli takes the writer claim.

**Session and resume.** The first `metadata` event carries `data.sessionId`;
record it with `observe running --provider-session` if you have no pid. To
continue after `needs_input` or `blocked`, resume that session with
`--resume-id` from the same working directory; the resumed session keeps the
task context. The continuation is still a new attempt.

**Result.** The last `runFinished` event has `status`, `finalText` and
`finalTextTruncated`. The payload is the last line of `finalText` that is a
JSON object. Put the result schema into the prompt: kiro-cli has no flag to
enforce one.

**Exit code.** 0 means the run completed, whatever the disposition; 1 after
`SIGINT`, 137 after `SIGKILL`. Judge the work by the result and the host
checks, never by the exit code alone.

**Stopping.** `SIGINT` to the process group stops the whole tree at once.
Every process kiro-cli started stayed in the launch process group in all
eight runs, but with `execute_bash` trusted the model can start a detached
process, so `descendants_may_outlive` stays `unverified`. On macOS every
attempt therefore ends with owner attestation (check `pgrep -fl
kiro-cli-chat` and the process group), unless it was launched in a
containment scope. The settle window is 5 s.

**Not measured.** `TERM`; `--trust-all-tools`; resume from another
directory; auto-approved MCP tools (they could write despite the read-only
setup); `--cloud`.
