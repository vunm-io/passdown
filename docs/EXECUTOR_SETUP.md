# Executor setup

Pre-flight checklist for adding an executor to the `executors` list in a
workspace's `## passdown` section. The dispatch skill routes tasks to these
executors at runtime, but it **cannot reconfigure them mid-dispatch** —
permission gates and sandbox policy are user setup work, done here, once,
before the executor earns its place in the list.

An executor that fails these checks doesn't have to be removed — but its
limits must be recorded as `executor notes` in the workspace AGENTS.md so
routing can veto incompatible tasks.

## 1. Non-interactive run completes

Non-interactive modes (`--print`, `exec`, app-server) have nobody to answer
permission prompts. A prompt the CLI cannot answer becomes a silent
hang-to-timeout, not an error.

- [ ] Run a trivial prompt end to end, e.g. "run `echo ok` and report the
      output" — it returns within seconds, no hang
- [ ] If it hangs: configure the executor's own auto-approval mechanism
      (allowlist, hook, or policy file — never a blanket
      skip-all-permissions flag), then re-test

## 2. Sandbox scope matches the work

Sandboxed executors typically restrict writes to the workspace and block
the network. Toolchain wrappers are the classic trap: they write to their
own install dir on every invocation (Flutter's SDK cache is a known
example), so *any* command through them fails — or worse, sends the agent
off improvising workarounds.

- [ ] Run one representative toolchain command through the executor
      (`<tool> --version` is not enough — pick one that builds or tests)
- [ ] If it fails on writes outside the repo: extend the sandbox's writable
      roots (e.g. Codex `~/.codex/config.toml` →
      `[sandbox_workspace_write] writable_roots`)
- [ ] If the work needs package fetches or dependency resolution: enable
      sandbox network access, and note the prompt-injection/exfiltration
      trade-off that comes with it

## 3. Record the outcome

- [ ] Add what passed *and* what failed (with root cause) to
      `executor notes` in the workspace AGENTS.md
- [ ] Tasks that the executor cannot run (network, out-of-repo writes,
      GUI/toolchain builds) are routed elsewhere — the notes are the veto
      list the dispatch skill reads before routing
