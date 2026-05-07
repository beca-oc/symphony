# Symphony Agent Instructions

Use `rtk` before local shell commands in this repository.

Codex plans. Symphony executes.

Keep ambiguous discovery, product judgment, and open-ended debugging in Codex. Hand work to
Symphony only after the Linear issue is queued, bounded, and evidence-heavy.

A Symphony-ready issue must name:

- repo and base branch;
- risk tier;
- include and exclude scope;
- validation commands;
- deploy/check evidence;
- branch rule `codex/<issue-id>-<short-slug>`;
- exit policy.

Symphony owns isolated workspaces, constrained Codex worker execution, validation, draft PR
publication, `symphony` labeling, evidence recording, trace metrics, and moving Linear issues only
to `Human Review` or `Rework`.

Never let a worker mark work `Done`, merge, promote, delete workspaces, or substitute model review
for mechanical evidence.

See `docs/codex-symphony-operating-contract.md` for the full contract.
