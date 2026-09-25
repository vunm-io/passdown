---
card: codex
card_version: 1
measured:
  date: 2026-09-25
  host_os: macOS 26.6.2
  cli_version: 0.157.0
  engine: not reported in --json output
  by: E-CODEX-1 (passdown maintainer session, Claude)
  evidence: docs/evidence/e-codex-1/README.md
capabilities:
  headless: verified
  structured_output: verified
  native_schema_enforcement: unsupported
  resume_session: verified
  session_id_observable: verified
  exit_code_meaningful: verified
  descendants_may_outlive: verified
  cancel_signal_honored: verified
  read_only_mode: verified
  sandbox_confined_writes: unverified
invocation:
  headless: 'codex exec --json --skip-git-repo-check --sandbox <read-only|workspace-write> [--ignore-user-config] "<prompt>" </dev/null'
  output_capture: stdout, JSON Lines events
  result_extraction: text of the last item.completed event whose item.type is agent_message, then its last line that is a JSON object; turn.failed or no turn.completed means no result
  resume: 'codex exec resume --json --skip-git-repo-check -c sandbox_mode=<mode> <thread_id> "<prompt>" </dev/null'
  cancel: { signal: INT, target: pgroup, grace_seconds: 10, then: KILL }
stop:
  containment: [pgroup]
  settle_seconds: 5
permissions:
  mechanism: --sandbox read-only (the default, OS-enforced) or workspace-write (writes inside the workspace only); resume takes -c sandbox_mode=<mode>; the read-only mode is --sandbox read-only --ignore-user-config
  notes: danger-full-access and --dangerously-bypass-approvals-and-sandbox were not used or measured
environment_constraints: [logged-in codex CLI, stdin must be closed or it waits for input, the user's skills and plugins load and marketplaces refresh over the network, about 25 s start-up measured]
discovery_hint: pgrep -fl 'codex exec' for the worker; its tool shells (/bin/zsh -c or -lc) run in their own process groups under the attempt location
toolchain_check: null
---
# codex (Codex CLI)

Measured by E-CODEX-1 on codex-cli 0.157.0; the record is
`docs/evidence/e-codex-1/` in the passdown repository. Skip this card when
Codex is the host: `codex` is then a self-target.

**Launch.** Run from the attempt location, always with stdin closed
(`</dev/null`): `codex exec` otherwise reads more input from stdin and a
backgrounded worker waits. Choose the sandbox by task:

| Task | Flags |
|---|---|
| read or review, claim-free (`--mutation-guard readonly:sandbox-read-only+ignore-user-config`) | `--sandbox read-only --ignore-user-config` |
| edits files and runs commands in the repository | `--sandbox workspace-write` |

The read-only sandbox is enforced by the OS: a shell write fails with
`operation not permitted`, and `apply_patch` is refused with "writing is
blocked by read-only sandbox" (E-CODEX-1 runs R and R2). The read-only mode
needs `--ignore-user-config` as well: without it the user's MCP servers and
plugins load, and they are outside the sandbox and were not measured. With
it, no plugin or MCP activity appeared.

`workspace-write` refused a shell write in the home directory (W). That run
still loaded the user's MCP servers and plugins, which act outside the
sandbox; `apply_patch` outside the workspace and writes to `/tmp` or
`$TMPDIR` were not measured. So `sandbox_confined_writes` stays
`unverified`: a `snapshot+sandbox` read on Codex is not claim-free. Use the
read-only mode above for claim-free reads.

**Result.** Events are `thread.started` (`thread_id`), `item.completed`
(`command_execution`, `file_change`, `agent_message`), then
`turn.completed` or `turn.failed`. The payload is the last line that is a
JSON object in the text of the last `agent_message`. `--output-schema`
cannot carry passdown's result schema (the API rejects its `not` and
conditional parts), so paste the schema into the prompt.

**Exit code.** 0 for a completed turn, whatever the disposition; 1 after
`SIGINT` or a failed turn; 137 after `SIGKILL`.

**Session and resume.** Resume with `codex exec resume <thread_id>`. That
subcommand has no `--sandbox`; pass `-c sandbox_mode=workspace-write`. The
resumed thread keeps the task context; the continuation is a new attempt.

**Stopping.** Tool shells run in **their own process groups**. `SIGINT` to
the launch group ends them too. After `SIGKILL` they survive and keep
writing: in E-CODEX-1 a loop went on from 11 to 28 lines with the launch
group already empty. An empty launch process group is never stop evidence
for Codex (`descendants_may_outlive: verified`): cancel with `SIGINT` first,
and end every attempt with owner attestation after checking for tool shells
in the attempt location, unless it ran in a containment scope.

**Environment.** The user's installed skills and plugins load into `codex
exec`, and it refreshes plugin marketplaces over the network. The measured
start-up before the first write was about 25 s; give short tasks a budget
that allows for it.

**Not measured.** `TERM`; `danger-full-access`; writes to `/tmp`; resume from
another directory; a containment scope.
