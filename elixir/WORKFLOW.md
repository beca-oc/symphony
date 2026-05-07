---
tracker:
  kind: linear
  project_slug: "symphony-0c79b11b75ea"
  active_states:
    - Todo
    - In Progress
    - Rework
  terminal_states:
    - Closed
    - Cancelled
    - Canceled
    - Duplicate
    - Done
polling:
  interval_ms: 5000
workspace:
  root: ~/code/symphony-workspaces
hooks:
  after_create: |
    git clone --depth 1 https://github.com/openai/symphony .
    if command -v mise >/dev/null 2>&1; then
      cd elixir && mise trust && mise exec -- mix deps.get
    fi
  before_remove: |
    cd elixir && mise exec -- mix workspace.before_remove
agent:
  max_concurrent_agents: 10
  max_turns: 20
codex:
  command: codex --config 'model="gpt-5.5"' --config model_reasoning_effort=xhigh app-server
  environment_allowlist:
    - PATH
    - HOME
    - TMPDIR
    - USER
    - LOGNAME
    - SHELL
    - LANG
    - LC_ALL
    - TERM
  required_environment: []
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
---

You are working on a Linear ticket `{{ issue.identifier }}` in the isolated workspace Symphony created.

Symphony checked ticket readiness before launching this run. Keep the work scoped to the ticket and this repository copy.

This is an unattended orchestration session.

{% if attempt %}
Continuation context:

- This is retry attempt #{{ attempt }} because the ticket is still active.
- Resume from the current workspace state instead of restarting from scratch.
- Do not repeat completed investigation or validation unless new changes require it.
{% endif %}

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

Execution rules:

1. Work only in the provided repository copy.
2. Only stop early for a true blocker: missing required auth, permissions, secrets, or tools.
3. Do not call Linear tools, GitHub tools, `gh`, or `git push`; Symphony owns validation, push, PR publication, evidence, and Linear state transitions.
4. Treat the ticket's scope, acceptance criteria, validation, and evidence requirements as the contract.
5. If blocked, stop and report the blocker clearly.
6. Prefer targeted tests or proofs for changed behavior. Revert temporary proof edits before finishing.
7. Final response should include only what changed, what validation ran, and any blockers. Do not include "next steps for user".
