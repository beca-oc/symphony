# Symphony Agent Instructions

Use `rtk` before local shell commands in this repository.

Codex, Claude, and Gemini may all be used as engineering agents in Subconscious.ai repos. This file
is the canonical repo instruction entrypoint; vendor-specific files such as `CLAUDE.md` or
`GEMINI.md` should point here instead of duplicating the contract.

Engineering agents plan. Symphony executes prepared Linear tickets.

Keep ambiguous discovery, product judgment, and open-ended debugging in the planning agent. Hand work to
Symphony only after the Linear issue is queued, bounded, and evidence-heavy.

A Symphony-ready issue must name:

- repo and base branch;
- risk tier;
- include and exclude scope;
- validation commands;
- deploy/check evidence;
- branch rule `codex/<issue-id>-<short-slug>`;
- exit policy.

Symphony currently owns isolated workspaces, constrained Codex app-server worker execution, validation, draft PR
publication, `symphony` labeling, evidence recording, trace metrics, and moving Linear issues only
to `Human Review` or `Rework`.

Never let a worker mark work `Done`, merge, promote, delete workspaces, or substitute model review
for mechanical evidence.

See `docs/codex-symphony-operating-contract.md` for the full contract.
