---
tracker:
  kind: linear
  project_slug: "042ccd5f20ae"
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
  interval_ms: 300000
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
    git config user.name "Avi Yashchin"
    git config user.email "3144839+aviyashchin@users.noreply.github.com"
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
repair:
  max_attempts: 2
  retryable_failure_buckets:
    - validation_failed
    - ci_failed
    - ci_timeout
    - git_push_failed
    - missing_pr
    - missing_label
    - missing_workpad
    - missing_pushed_sha
    - pushed_sha_mismatch
    - branch_mismatch
    - missing_validation
    - missing_deploy_evidence
    - merge_conflict
  terminal_failure_buckets:
    - missing_secret
    - auth_blocked
    - unsafe_side_effect
    - ambiguous_scope
agent:
  max_concurrent_agents: 1
  max_turns: 1
  max_uncached_tokens: 250000
  continue_after_normal_exit: false
codex:
  command: env HOME="$HOME/.symphony/worker-home" CODEX_HOME="$HOME/.symphony/codex-home" codex --config shell_environment_policy.inherit=all --config 'model="gpt-5.5"' --config model_reasoning_effort=high --config 'mcp_servers={}' --config features.apps=false --config features.browser_use=false --config features.tool_search=false --config features.image_generation=false --config features.computer_use=false --config features.workspace_dependencies=false --config features.plugins=false --config features.multi_agent=false app-server
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
Recent Symphony harness context:
{{ issue.recent_harness_context }}
{% endif %}

Worker contract:

Profile and validation boundaries:
- Do not invoke Codex skills or read files under `~/.codex` or `~/.agents`; this unattended worker must use the compact workflow context.
- Do not run broad validation inside Codex unless it is necessary to make the commit safely. If a check is necessary, run the narrowest scoped check once.

1. This is an unattended Symphony worker. Never ask a human to perform follow-up actions.
2. Work only in the provided repository copy.
3. Do not call Linear tools, GitHub tools, `gh`, or `git push`.
4. Do not create or update a Linear workpad comment.
5. Do not create or update repo-local progress/status files such as `claude-progress.txt`; keep progress evidence out of the product diff.
6. If this is `Rework`, treat the latest `## Symphony Repair Packet` as the binding scope. Continue the named `codex/{{ issue.identifier }}-...` branch and existing draft PR. Do not create a duplicate PR. If no branch is named, create `codex/{{ issue.identifier }}-<short-slug>`.
7. Sync from `origin/main` before edits.
8. Implement the smallest scoped change that satisfies the ticket or repair packet; avoid unrelated refactors.
9. Commit the local change with a clear message.
10. Leave the workspace on the committed branch and stop.

Symphony will run validation, push the branch, create the draft PR, label it, record Linear evidence, require the repo-owned `symphony-gate` check plus deployment evidence, and move the issue to `Human Review` or `Rework`.
