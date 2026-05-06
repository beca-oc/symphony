---
tracker:
  kind: linear
  project_slug: "ai-chatbot-042ccd5f20ae"
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
    - Human Review
polling:
  interval_ms: 60000
workspace:
  root: ~/code/symphony-workspaces/ai-chatbot
repo:
  name: ai-chatbot
  github_repo: Subconscious-ai/ai-chatbot
  default_branch: main
hooks:
  timeout_ms: 600000
  after_create: |
    set -eu
    git clone https://github.com/Subconscious-ai/ai-chatbot.git .
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

You are working on Linear ticket `{{ issue.identifier }}` for the `ai-chatbot` repository.

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

1. This is an unattended Symphony worker. Never ask a human to perform follow-up actions.
2. Work only in the provided repository copy.
3. Do not call Linear tools, GitHub tools, `gh`, or `git push`.
4. Do not create or update a Linear workpad comment.
5. If this is `Rework` and the harness context names an existing `codex/{{ issue.identifier }}-...` branch, continue that branch; otherwise create a local branch named `codex/{{ issue.identifier }}-<short-slug>`.
6. Sync from `origin/main` before edits.
7. Implement the smallest scoped change that satisfies the ticket; avoid unrelated refactors.
8. Commit the local change with a clear message.
9. Leave the workspace on the committed branch and stop.

Symphony will run validation, push the branch, create the draft PR, label it, record Linear evidence, require the repo-owned `symphony-gate` check plus deployment evidence, and move the issue to `Human Review` or `Rework`.
