---
tracker:
  kind: linear
  project_slug: "causlio-71a996a4475b"
  active_states:
    - Todo
    - In Progress
    - Merging
    - Rework
  terminal_states:
    - Closed
    - Cancelled
    - Canceled
    - Duplicate
    - Done
polling:
  interval_ms: 60000
workspace:
  root: ~/code/symphony-workspaces/causl.io
repo:
  name: causl.io
  github_repo: Subconscious-ai/causl.io
  default_branch: main
hooks:
  timeout_ms: 600000
  after_create: |
    set -eu
    git clone https://github.com/Subconscious-ai/causl.io.git .
    git config core.hooksPath /dev/null || true
    pnpm install --frozen-lockfile
validation:
  preflight: |
    set -eu
    pnpm -v
    test -d node_modules
  fast: pnpm run verify:fast
  full: pnpm run verify:full
  deploy_evidence: vercel
  evidence_required: true
agent:
  max_concurrent_agents: 1
  max_turns: 1
  max_uncached_tokens: 500000
  continue_after_normal_exit: false
codex:
  command: codex --config shell_environment_policy.inherit=all --config 'model="gpt-5.2"' --config model_reasoning_effort=medium app-server
  approval_policy: never
  thread_sandbox: danger-full-access
  turn_sandbox_policy:
    type: dangerFullAccess
---

You are working on a Linear ticket `{{ issue.identifier }}` for the `causl.io` repository.

Issue context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Instructions:

1. This is an unattended Symphony worker. Never ask a human to perform follow-up actions.
2. Work only in the provided repository copy.
3. For `Todo`, immediately move the Linear issue to `In Progress`, then create or update one persistent `## Codex Workpad` comment.
4. Use a branch named `codex/{{ issue.identifier }}-<short-slug>`.
5. Sync from `origin/main` before edits, record the pull result and HEAD SHA in the workpad, then implement the ticket.
6. Run the smallest validation command that proves the change, plus any validation explicitly required by the ticket.
7. Every code-changing task must produce a GitHub draft PR, not a ready PR.
8. Attach or link the PR to the Linear issue and add the GitHub PR label `symphony`.
9. Keep all verification evidence in the single `## Codex Workpad` comment: Linear issue URL, absolute workspace path, branch, draft PR URL, PR attachment/link, `symphony` label status, final commit SHA, validation command/result, and Vercel/Fly/deployment preview or check URL when available.
10. Do not wait for asynchronous GitHub/Vercel/Fly checks to become green. Poll PR checks and deployment status once after creating the PR, record current status plus check/deployment URLs, then stop polling.
11. Do not move the issue to `Human Review`. Leave it active after the workpad has local validation evidence, the draft PR link, the final commit SHA, the `symphony` label status, and a deployment/check URL or pending-check URL; Symphony verifies the evidence and moves the issue.
12. Never move a failed ticket to `Done`.
13. Never merge, mark ready for merge, promote to production, or delete the worktree without an explicit human decision.

If blocked by missing auth, secrets, permissions, or external access, update the workpad with a concise blocker note and move the issue to `Rework`.
