# Symphony Task Intake Contract

Symphony work should be queued, bounded, and evidence-heavy by default.

This does not mean every thought, spike, or design conversation needs Symphony. It means every
task delegated to autonomous execution must be shaped so the harness can select it, constrain it,
verify it, and leave an audit trail without relying on chat memory.

## When To Use Symphony

Use Symphony when the work has these traits:

- It belongs to a Linear queue and a repo-mapped Linear project.
- It can be expressed as one bounded issue or a parent issue plus repo-specific child issues.
- The repo exposes deterministic `scripts/agent/*` validation.
- The expected evidence is mechanical: branch, draft PR, label, SHA, validation, CI/deploy URL,
  workpad, evidence gate, trace, and final Linear state.
- The right completion state is `Human Review`, `Rework`, or a policy-approved merge.

Use direct Codex when the work is exploratory, ambiguous, or tightly interactive. Direct Codex is
still the right tool for design exploration, unclear debugging, and rapid human-agent iteration.

## Required Ticket Shape

Every Symphony ticket must include:

- `Goal`: one sentence outcome.
- `Queue`: Linear project and starting state.
- `Repo`: repo mapping and base branch.
- `Risk Tier`: `static`, `test-only`, `product-code`, `migration`, or `secrets/live`.
- `Scope`: concise work summary.
- `Boundaries`: explicit include and exclude lists.
- `Acceptance`: behavioral and evidence acceptance.
- `Validation`: preflight, fast, and full validation commands as applicable.
- `Evidence`: workpad, evidence gate, draft PR, label, pushed SHA, validation result, trace, and
  check/deploy URL.
- `Deploy / Check Evidence`: required `symphony-gate` and deploy/check source.
- `Exit Policy`: when Symphony may move to `Human Review`, `Rework`, or merge.
- `Failure Handling`: failure bucket and repair/retry behavior.

## Policy

- Workers do not push, open PRs, update Linear workpads, or move issues to review.
- Symphony owns validation, push, draft PR creation, PR labeling, evidence comments, traces, and
  state transitions.
- OpenClaw Product Engineer owns ticket quality.
- OpenClaw Reviewer/Merge Captain owns mechanical evidence review first, then semantic review.
- A task that cannot name its queue, boundaries, and evidence is not ready for autonomous
  execution.

## Decision Rule

If the work is ambiguous but important, start with a direct Codex planning/debugging session. Once
the next step is clear, convert it into a Symphony-ready ticket using the intake contract.
