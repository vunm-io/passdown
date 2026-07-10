# Optional integrations

Passdown is a routing and handoff layer. It does not require Superpowers or OpenSpec.

## Standalone Passdown

Use `planning: markdown` and copy `templates/plan.md` into the workspace's configured `plan_dir`.

Flow:

1. Capture or receive a request.
2. Create a self-contained markdown plan with dispatch tags.
3. Run `passdown-dispatch` before implementation.
4. Execute tasks routed to `main`; delegate only to configured and authorized executors.
5. Verify results and finish with `passdown-handoff` when pausing or ending the session.

For a direct install without OpenSpec schema files:

```bash
./install.sh --host claude --skills-only
```

## Passdown with OpenSpec

OpenSpec is an optional planning-artifact provider. The Passdown schema generates self-contained tasks with `[dispatch: external-ok]` and `[dispatch: main]` tags.

Flow:

```text
OpenSpec proposal/spec/tasks
→ Passdown dispatch gate
→ main/external execution
→ verification
→ Passdown handoff
```

The skills remain usable when the OpenSpec CLI and schema are not installed.

## Passdown with Superpowers

Superpowers may provide brainstorming, plan writing, debugging, and execution discipline. It must not bypass Passdown's routing gate.

Required flow:

```text
Superpowers brainstorming
→ Superpowers writing-plans
→ normalize or add Passdown dispatch tags
→ passdown-dispatch
→ execute tasks according to routing decisions
→ verify
→ passdown-handoff
```

Before entering Superpowers `executing-plans`, run `passdown-dispatch` whenever the plan has three or more pending tasks, any dispatch tags, or independently delegable work. The gate may route every task to `main`; routing still happens before implementation.

## Passdown with both OpenSpec and Superpowers

OpenSpec owns durable specification and task artifacts. Superpowers may improve the planning process. Passdown owns pre-execution routing, delegated-work verification, and session handoff.

None of these integrations changes executor authorization: native subagents still require explicit user authorization, and external executors must be configured in the effective `AGENTS.md`.
