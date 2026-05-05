# OpenClaw Reviewer And Merge Captain Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an OpenClaw Reviewer And Merge Captain agent that checks Symphony output mechanically, reviews semantic risk, and merges only low-risk work under policy.

**Architecture:** The agent should be a verification and landing agent. It reads Linear, GitHub PR state, Symphony traces, and required checks. It blocks on deterministic evidence first, then performs semantic review, then applies risk-tier merge policy.

**Tech Stack:** OpenClaw agent configuration, Linear API, GitHub API/CLI, Symphony `/api/v1/state`, `symphony-runs.ndjson`, repo CI checks.

---

## Guardrails

- Do not merge product-code, migration, secrets, auth, billing, or live-data work without explicit human approval.
- Do not treat an LLM review as a substitute for required checks.
- Do not merge if `check_url` points to Linear.
- Do not merge if `manual_rescue_count > 0` on proof runs.
- Do not mark Linear issues `Done`.

## Task 1: Add Mechanical Evidence Checker

**Files:**
- Create: OpenClaw agent config for `openclaw-reviewer-merge-captain`
- Reference: `/Users/aviyashchin/symphony/docs/openclaw-symphony-agents.md`

**Step 1: Write the failing evidence test**

Input fixture:

```json
{
  "linear_has_workpad": true,
  "linear_has_evidence_gate": true,
  "checker_passed": true,
  "branch": "codex/BEC-1-test",
  "pr_label": "symphony",
  "pushed_sha_matches": true,
  "validation_recorded": true,
  "check_url": "https://linear.app/subconscious/issue/BEC-1/fake",
  "failure_bucket": "none"
}
```

Expected: FAIL with `invalid_check_url`.

**Step 2: Implement mechanical checklist**

Block unless all are true:

- Linear has `## Codex Workpad`.
- Linear has `## Symphony Evidence Gate`.
- Evidence gate result is `passed`.
- `checker.passed == true`.
- Branch matches `codex/<issue-id>-<short-slug>`.
- PR has `symphony` label.
- PR head SHA matches Linear pushed SHA.
- Validation command/result is recorded.
- Required CI is green.
- `check_url` is GitHub Actions, Vercel, Checkly, or another real check/deploy URL.
- `failure_bucket == none`.

**Step 3: Run the test**

Expected: Linear URLs are rejected as check evidence.

## Task 2: Add Risk-Tier Merge Policy

**Files:**
- Modify: OpenClaw Reviewer And Merge Captain prompt/config.
- Test: OpenClaw merge policy scenarios.

**Step 1: Write failing merge policy tests**

Cases:

- `static` + all checks green -> merge allowed.
- `test-only` + all checks green -> merge allowed.
- `product-code` + no human approval -> merge blocked.
- `migration` -> merge blocked.
- `secrets/live` -> merge blocked.

Expected before implementation: policy is missing or over-permissive.

**Step 2: Implement policy**

Use the table in `/Users/aviyashchin/symphony/docs/openclaw-symphony-agents.md`.

**Step 3: Run tests**

Expected: only static/test-only low-risk PRs can auto-merge.

## Task 3: Add Semantic Diff Review

**Files:**
- Modify: OpenClaw Reviewer And Merge Captain prompt/config.
- Test: semantic review fixtures.

**Step 1: Write failing semantic test**

Fixture:

- Ticket says docs-only.
- PR changes application source code.

Expected: FAIL with `scope_expansion`.

**Step 2: Implement semantic checks**

Block if:

- Diff changes files outside scope.
- Tests are missing or meaningless.
- Generated files changed without regeneration instructions.
- Error/empty/loading/edge states are ignored for user-facing work.
- Secrets or destructive operations are introduced.

**Step 3: Run tests**

Expected: docs-only ticket with source-code diff is blocked.

## Task 4: Add Failure Repair Loop

**Files:**
- Modify: OpenClaw Reviewer And Merge Captain prompt/config.
- Test: failed CI scenario.

**Step 1: Write failing repair test**

Fixture:

- `symphony-gate` failed.
- PR is draft.
- Linear issue is still `Human Review`.

Expected: FAIL because the reviewer does not route to repair.

**Step 2: Implement repair routing**

On failed CI/evidence:

1. Comment on Linear with failure bucket and failing URL.
2. Move issue to `Rework`.
3. Create a bounded repair ticket or reassign the same ticket to Symphony.
4. Require the repair PR to include failing and passing check URLs.

**Step 3: Run tests**

Expected: failed CI becomes Rework/repair, never merge.

## Task 5: Add Restart/Resume Verification

**Files:**
- Modify: OpenClaw Reviewer And Merge Captain prompt/config.
- Test: duplicate PR/comment scenario.

**Step 1: Write failing restart test**

Fixture:

- Same Linear issue has two draft PRs or duplicate `## Symphony Evidence Gate` comments.

Expected: FAIL with `duplicate_resume_artifacts`.

**Step 2: Implement restart checklist**

Require:

- One issue branch.
- One draft PR.
- One current workpad comment.
- One current evidence gate comment.
- Continuous trace history for the issue identifier.

**Step 3: Run tests**

Expected: duplicate resume artifacts block merge and route to human review.

## Acceptance

- Mechanical evidence fails closed before semantic review.
- Static/test-only work can auto-merge only when all checks pass.
- Product/risky work remains in Human Review unless a human explicitly approves merge.
- Failed CI creates Rework/repair flow.
- Restart/resume duplicates are detected before merge.

