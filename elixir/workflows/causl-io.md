---
tracker:
  kind: linear
  project_slug: "71a996a4475b"
  active_states:
    - Todo
    - In Progress
  terminal_states:
    - Closed
    - Cancelled
    - Canceled
    - Duplicate
    - Done
    - Human Review
polling:
  interval_ms: 60000
workspace:
  root: ~/code/symphony-workspaces/causl-io
hooks:
  timeout_ms: 600000
  after_create: |
    set -eu
    git clone https://github.com/Subconscious-ai/causl.io.git .
    git config core.hooksPath /dev/null || true
    bash scripts/agent/preflight.sh
agent:
  max_concurrent_agents: 1
  max_turns: 1
codex:
  max_total_tokens: 100000
  command: env HOME=/Users/aviyashchin/.symphony/codex-worker-home CODEX_HOME=/Users/aviyashchin/.symphony/codex-home codex --config shell_environment_policy.inherit=all --config 'model="gpt-5.5"' --config model_reasoning_effort=high --config 'mcp_servers={}' --config features.plugins=false --config features.multi_agent=false app-server
  approval_policy: never
  thread_sandbox: danger-full-access
  turn_sandbox_policy:
    type: dangerFullAccess
---

You are working on Linear ticket `{{ issue.identifier }}` for the `causl.io` repository.

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

{% if issue.recent_harness_context %}
Recent Symphony harness context:
{{ issue.recent_harness_context }}
{% endif %}

Worker contract:

1. This is an unattended Symphony worker. Complete the ticket to an evidence-backed handoff; never ask a human to do routine delivery steps.
2. Work only in the provided repository copy and stay inside the ticket scope.
3. If the issue is `Todo`, move it to `In Progress` with the available Linear tool before active work. If tracker write access is unavailable, continue and record that blocker in the workpad.
4. Create or reuse branch `codex/{{ issue.identifier }}-<short-slug>` from `origin/main`. For `Rework`, continue the existing named branch and PR when one exists; do not create duplicates.
5. Maintain exactly one Linear comment headed `## Codex Workpad` with plan, validation, PR URL, pushed SHA, evidence, and blockers.
6. Implement the smallest scoped change that satisfies the issue. Avoid unrelated refactors and product-diff progress files.
7. Validate with the commands in the issue body. If no commands are provided, inspect the repo and run the narrowest existing lint/test/build command that proves the change.
8. Commit, push the branch, open or update a draft PR, link this Linear issue, and add the `symphony` PR label when possible.
9. Record PR URL, final SHA, validation output, and CI/deploy/check evidence in the workpad.
10. Move the issue to `Human Review` only after evidence exists. If blocked, move it to `Rework` with the exact blocker and next action. Never merge, mark ready, delete worktrees, move to `Done`, or close the issue.
