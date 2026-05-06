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
    bash scripts/agent/preflight.sh
validation:
  preflight: bash scripts/agent/preflight.sh
  fast: bash scripts/agent/validate-fast.sh
  full: bash scripts/agent/validate-full.sh
  deploy_evidence: vercel
  evidence_required: true
evidence_gate:
  github_required_checks: ["symphony-gate"]
  require_all_checks: true
  allow_skipped_checks: ["Run Storybook"]
  timeout_seconds: 1800
agent:
  max_concurrent_agents: 1
  max_turns: 1
  max_uncached_tokens: 500000
  continue_after_normal_exit: false
codex:
  command: codex --config shell_environment_policy.inherit=all --config 'model="gpt-5.5"' --config model_reasoning_effort=high --config 'mcp_servers={}' --config features.plugins=false --config features.multi_agent=false app-server
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
Recent Symphony harness blocker context:
{{ issue.recent_harness_context }}
{% endif %}

Worker contract:

1. Unattended Symphony worker: do not ask a human for follow-up.
2. Work only in the provided repository copy.
3. Do not call Linear tools, GitHub tools, `gh`, or `git push`.
4. Do not create or update a Linear workpad comment.
5. Create a local branch named `codex/{{ issue.identifier }}-<short-slug>`.
6. Sync from `origin/main` before edits.
7. Make the smallest scoped change; avoid unrelated refactors.
8. Commit the local change with a clear message.
9. Leave the workspace on the committed branch and stop.

Symphony will run validation, push the branch, create the draft PR, label it, record Linear evidence, require the repo-owned `symphony-gate` check plus deployment evidence, and move the issue to `Human Review` or `Rework`.
