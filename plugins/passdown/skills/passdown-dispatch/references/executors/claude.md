---
card: claude
card_version: 1
measured:
  date: 2026-09-25
  host_os: macOS 26.6.2
  cli_version: 2.1.193
  engine: claude-sonnet-4-6 (CLI default on the measuring machine)
  by: E-CLAUDE-1 (passdown maintainer session, Claude)
  evidence: docs/evidence/e-claude-1/README.md
capabilities:
  headless: verified
  structured_output: verified
  native_schema_enforcement: unsupported
  resume_session: verified
  session_id_observable: verified
  exit_code_meaningful: unsupported
  descendants_may_outlive: verified
  cancel_signal_honored: verified
  read_only_mode: verified
  sandbox_confined_writes: unverified
invocation:
  headless: 'claude -p --output-format stream-json --verbose --permission-mode <mode> [--allowedTools=<tools>] "<prompt>"'
  output_capture: stdout, stream-json events as JSON Lines
  result_extraction: .result of the last event with type result, then its last line that is a JSON object; is_error true or no result event means no result
  resume: 'claude -p --output-format stream-json --verbose --permission-mode <mode> --resume <session_id> "<prompt>"'
  cancel: { signal: INT, target: pgroup, grace_seconds: 10, then: KILL }
stop:
  containment: [pgroup]
  settle_seconds: 5
permissions:
  mechanism: --permission-mode (default denies edits and writing shell commands; acceptEdits allows edits, including through the shell) and --allowedTools=<tools>
  notes: --allowedTools is variadic, so use the = form or it swallows the prompt; the user's settings, hooks, plugins and MCP servers load into -p runs
environment_constraints: [logged-in claude CLI (claude auth login), usage limits end a run with is_error and api_error_status 429]
discovery_hint: pgrep -fl 'claude -p' for the worker and pgrep -fl 'shell-snapshots/snapshot-' for its Bash tool shells, which run in their own process groups
toolchain_check: null
---
# claude (Claude Code CLI)

Measured by E-CLAUDE-1 on Claude Code 2.1.193; the record is
`docs/evidence/e-claude-1/` in the passdown repository. This card also
describes a Claude Code **host's** native subagents only as far as they run
the same tools; they were not measured separately.

**Launch.** Run from the attempt location with a permission mode that fits
the task:

| Task | Flags |
|---|---|
| read or review (read-only mode) | no `--permission-mode` (default) and no `--allowedTools` |
| edits files | `--permission-mode acceptEdits` |
| edits files and runs commands | `--permission-mode acceptEdits --allowedTools=Bash` |

Use `--allowedTools=<tools>` with `=`: the option is variadic and otherwise
takes the prompt as one more tool name (the CLI then exits 1, "Input must be
provided"). The user's own settings, hooks, plugins and MCP servers load into
every `-p` run; a settings file that allows more than the default widens
what the worker can do, including in read-only mode.

**Workarounds.** When `Write` was denied, the measured worker tried to write
through a shell redirect instead, against the environment clause. Only the
permission layer stopped it. Rely on the permission mode, never on the
prompt, to keep a worker from writing.

**Result.** The last `result` event has `subtype`, `is_error`, `result` and
`permission_denials`. The payload is the last line of `result` that is a JSON
object. `is_error: true` (for example a usage limit, `api_error_status: 429`)
means no result: treat it as an environment problem, not a worker failure.
`--json-schema` did not produce `structured_output` for passdown's result
schema, so paste the schema into the prompt.

**Exit code.** Not a completion signal: 0 for any completed run, **and 0
after `SIGINT`** (`result` subtype `error_during_execution`); 1 for a usage
limit or an argument error; 137 after `SIGKILL`. Judge the run by the result
event and the host checks.

**Session and resume.** Every event carries `session_id`. Resume with
`--resume <session_id>` from the same directory; the resumed session keeps
the task context. The continuation is a new attempt.

**Stopping.** The Bash tool runs each command in **its own process group**.
`SIGINT` to the launch group makes Claude end those groups too. After
`SIGKILL` they survive and keep writing: in E-CLAUDE-1 a loop went on from 14
to 38 lines with the launch group already empty. So an empty launch process
group is never stop evidence for Claude (`descendants_may_outlive:
verified`): cancel with `SIGINT` first, and end every attempt with owner
attestation after checking the Bash tool shells (`pgrep -fl
'shell-snapshots/snapshot-'`), unless it ran in a containment scope.

**Not measured.** `TERM`; `bypassPermissions` and `auto` modes; resume from
another directory; `--setting-sources`; a containment scope.
