# Agent To Symphony Operating Contract

Engineering agents plan. Symphony executes prepared Linear tickets.

This is the default operating model for Subconscious.ai harness engineering. Codex, Claude, Gemini,
OpenClaw, Hermes, Pi, or any other agent shell can help with planning, implementation, or review
when explicitly asked, but none of those shells is the durable control plane. The durable system of
record is Linear, GitHub, Symphony traces, and repo-owned validation.

This Symphony implementation currently launches workers through Codex app-server. Claude and Gemini
should still read the same repo instructions and can prepare tickets, review output, or perform
normal non-Symphony engineering work, but Symphony-executed runs use the configured Codex worker
runtime unless a future worker adapter is added.

## When To Use Symphony

Use Symphony when the work is queued, bounded, and evidence-heavy:

- One Linear issue maps to one repo workflow.
- The repo, base branch, and risk tier are explicit.
- The scope has clear include and exclude boundaries.
- The issue names repo-owned validation commands, normally `scripts/agent/*`.
- The expected evidence is mechanical: workpad, branch, draft PR, label, pushed SHA, validation
  result, real CI/deploy/check URL, and trace metrics.
- The exit policy is explicit: `Human Review` after evidence passes, `Rework` for repairable
  failures, never worker-authored `Done`.

Do not use Symphony for vague discovery, product judgment, open-ended debugging, or work that
cannot name its validation and evidence path. Keep that work in the planning agent until it becomes
a bounded Linear ticket.

## Division Of Labor

The planning agent owns:

- Inspecting repos and existing behavior.
- Decomposing ambiguous work.
- Writing or updating Linear tickets.
- Defining risk tier, validation, evidence, dependencies, and exit policy.
- Deciding whether the ticket is ready for Symphony.

Symphony owns:

- Claiming the prepared Linear issue.
- Creating the isolated workspace.
- Running the constrained Codex app-server worker.
- Validating after worker exit.
- Pushing the branch and opening a draft PR.
- Adding the `symphony` PR label.
- Recording evidence and trace metrics.
- Moving the issue to `Human Review` or `Rework`.

The worker owns only local implementation: understand the issue, edit files, run useful local
checks, commit, and stop. Symphony owns publication and final state transition.

## Required Ticket Shape

Every Symphony-ready ticket must include these sections:

- `Goal`
- `Repo`
- `Risk Tier`
- `Scope`
- `Acceptance`
- `Validation`
- `Deploy / Check Evidence`
- `Failure Handling`

It must also state the branch rule `codex/<issue-id>-<short-slug>` and require the repo-owned
`symphony-gate` check when that repo has adopted the harness gate.

## Portable Instruction Block

Use this block in global agent instructions, repo `AGENTS.md`, and thin vendor pointers such as
`CLAUDE.md` or `GEMINI.md`:

```md
Engineering agents plan. Symphony executes prepared Linear tickets.

Only hand work to Symphony after it is queued, bounded, and evidence-heavy in Linear. A
Symphony-ready issue must name repo, base branch, risk tier, include/exclude scope, validation,
deploy/check evidence, branch rule, and exit policy.

Keep ambiguous discovery in the planning agent. Symphony should claim prepared issues, create
isolated workspaces, run constrained Codex app-server workers, validate, push, open draft PRs,
record evidence, and move issues only to Human Review or Rework.

Never let a worker mark work Done, merge, promote, delete workspaces, or substitute model review for
mechanical evidence.
```

## Tests

Run these local checks after changing the contract or workflows:

```bash
rtk node scripts/openclaw/symphony_agents.test.mjs
rtk node scripts/symphony/validate_workflows.mjs
cd elixir && rtk mise exec -- mix test
cd elixir && rtk mise exec -- mix build
```

The `scripts/openclaw/*` test file also contains the current tool-neutral readiness and evidence
validators. The filename is historical; the contract it tests is still the Symphony handoff
contract.
