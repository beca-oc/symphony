# Symphony Task Intake Contract

Hermes routes repo-changing work to Linear. Symphony executes the issue. Codex workers edit local
files only. Keep this contract compact; repo-owned `AGENTS.md` files carry the detailed allowed
surfaces and validation rules.

## When To Use Symphony

Use Symphony for bounded repo work: code, tests, docs, UI, config, CI, data contracts, or deployment
behavior. Use direct Codex for exploratory debugging, design iteration, or unclear product shaping.

## Compact Ticket Shape

Hermes should create short issues with:

- `Goal`: one sentence outcome.
- `Repo`: Linear project, GitHub repo, task type, and risk tier.
- `Acceptance`: observable behavior plus PR/evidence expectation.
- `Validation`: `preflight`, `validate-fast`, and task-specific checks only when needed.
- `Notes`: user URL, screenshot, constraints, or source evidence.

Do not duplicate long implementation plans in Linear by default. If a task needs a plan, create a
planning/discovery issue first.

## Repo Contract

Every Symphony repo must expose:

- `scripts/agent/preflight.sh`
- `scripts/agent/validate-fast.sh`
- `scripts/agent/validate-full.sh`
- `AGENTS.md`
- `.github/workflows/symphony-gate.yml`

`validate-fast.sh` should target 2-5 minutes and avoid live services, broad browser suites, and full
production builds unless the repo has measured that path as fast.

## Policy

- Workers do not call Linear tools, GitHub tools, `gh`, or `git push`.
- Symphony owns validation, push, draft PR creation, PR labeling, evidence comments, traces, and
  state transitions.
- Symphony stops at `Human Review` or `Rework`; merge/close is deterministic GitHub/Linear plumbing.
- Repair loops are bounded by workflow config; more retries usually hide bad repo contracts.

## Operations

- Audit repo contracts: `node scripts/symphony/audit_agent_contracts.mjs`
- Validate lane config: `node scripts/symphony/validate_workflows.mjs`
- Dry-run cleanup: `node scripts/symphony/janitor.mjs --age-days 7`
- Include Linear canary cleanup: `node scripts/symphony/janitor.mjs --linear --age-days 7`
