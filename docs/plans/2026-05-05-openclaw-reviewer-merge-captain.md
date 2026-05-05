# OpenClaw Reviewer And Merge Captain Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an OpenClaw Reviewer And Merge Captain agent that checks Symphony output mechanically, reviews semantic risk, and merges only low-risk work under policy.

**Architecture:** The agent should be a verification and landing agent. It reads Linear, GitHub PR state, Symphony traces, and required checks. It blocks on deterministic evidence first, then performs semantic review, then applies risk-tier merge policy.

**Tech Stack:** OpenClaw isolated agent workspace, OpenClaw `AGENTS.md` standing orders, Linear API, GitHub API/CLI, Symphony `/api/v1/state`, `symphony-runs.ndjson`, repo CI checks, OpenClaw background task ledger, OpenClaw trajectory bundles.

**Documentation basis:** Re-read and apply these OpenClaw docs before implementation: Agent Runtime, Agent Workspace, Multi-Agent Routing, Standing Orders, Background Tasks, Trajectory Bundles, Context, Exec Approvals, Tool-loop Detection, and Codex Harness.

**Key interpretation:** Reviewer/Merge Captain is a gatekeeper, not a believer. It may use model review as one input, but deterministic Symphony, GitHub, Linear, and OpenClaw evidence decides whether merge is allowed.

---

## Guardrails

- Do not merge product-code, migration, secrets, auth, billing, or live-data work without explicit human approval.
- Do not treat an LLM review as a substitute for required checks.
- Do not merge if `check_url` points to Linear.
- Do not merge if `manual_rescue_count > 0` on proof runs.
- Do not mark Linear issues `Done`.
- Do not share workspace, `agentDir`, auth profiles, or sessions with Product Engineer.
- Do not use native Codex/OpenClaw review as a substitute for mechanical evidence.
- Do not poll OpenClaw tasks or subagents in loops; use task records and on-demand inspection.

## Task 0: Provision Isolated Reviewer Workspace And Standing Order

**Files:**
- Create: OpenClaw workspace for `openclaw-reviewer-merge-captain`
- Create: Reviewer/Merge Captain `AGENTS.md`
- Create: Reviewer/Merge Captain `TOOLS.md`
- Create or configure: OpenClaw agent entry with dedicated workspace, `agentDir`, auth profiles, and session store.

**Step 1: Write the failing isolation test**

Inspect the OpenClaw config/workspace and assert:

- Reviewer/Merge Captain has a dedicated workspace.
- Reviewer/Merge Captain has a dedicated `agentDir`.
- Reviewer/Merge Captain workspace has `AGENTS.md`.
- Reviewer/Merge Captain does not share Product Engineer sessions or auth profiles.
- Reviewer/Merge Captain has merge authority only through the documented risk-tier policy.

Expected failure before implementation:

- Reviewer config is missing, shared, or can merge without policy.

**Step 2: Implement standing order**

Add standing orders directly to Reviewer `AGENTS.md`:

- Authority: mechanically verify Symphony evidence, perform semantic review, merge only low-risk work under policy.
- Trigger: PR ready for review, Linear issue in `Human Review`, scheduled review queue sweep.
- Approval gates: product-code, migration, secrets/live, auth, billing, destructive operations, failed or missing evidence.
- Escalation: stale traces, duplicate PRs, missing checks, ambiguous risk, manual rescue.

Keep injected workspace files concise and avoid storing secrets. Use OpenClaw tool policy/exec approvals for hard controls.

**Step 3: Run the test**

Expected: reviewer workspace is isolated, concise, and has explicit merge authority limits.

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
- Symphony trace and OpenClaw task/session records agree on issue id, PR URL, head SHA, final state, and failure bucket.

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
- PR head SHA differs from the SHA in the latest Symphony evidence gate.
- The review was performed against stale OpenClaw or GitHub state.

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
5. Record the OpenClaw task id/session id and trajectory export path for the repair decision.

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

## Task 6: Add OpenClaw Trajectory And Context Audit

**Files:**
- Modify: Reviewer/Merge Captain prompt/config.
- Create: review observability scenario test.

**Step 1: Write the failing observability test**

Fixture:

- Low-risk PR passes deterministic checks.
- Reviewer auto-merges.
- No OpenClaw task id/session id/trajectory export is recorded.

Expected: FAIL with `missing_review_trace`.

**Step 2: Implement audit capture**

For every review run, record:

- OpenClaw task id when detached/background.
- OpenClaw session id.
- PR URL and head SHA reviewed.
- Symphony run trace id/path.
- GitHub check URL.
- Merge decision and risk tier.
- `/context list` or `/context detail` summary during proof runs.
- `/usage tokens` summary during proof runs.
- `/export-trajectory <linear-issue-id>` for failed, disputed, auto-merged, or high-impact reviews.

Do not store secrets in the OpenClaw workspace. Review trajectory bundles before sharing outside the team.

**Step 3: Run tests**

Expected: every merge/block decision is reconstructable from Linear, GitHub, Symphony trace, and OpenClaw task/trajectory artifacts.

## Task 7: Add Native Codex Review Boundary

**Files:**
- Modify: Reviewer/Merge Captain prompt/config.
- Test: Codex review boundary scenario.

**Step 1: Write the failing boundary test**

Fixture:

- Native Codex/OpenClaw review says the PR looks correct.
- `symphony-gate` is missing or failed.

Expected: FAIL with `missing_mechanical_evidence`.

**Step 2: Implement boundary**

Allow optional native Codex/OpenClaw review only after mechanical evidence exists. Treat model review as semantic input, not merge authority.

If a dedicated Codex review agent is needed, configure it separately with:

```json
{
  "agents": {
    "defaults": {
      "model": "openai/gpt-5.5",
      "agentRuntime": {
        "id": "codex"
      }
    }
  },
  "plugins": {
    "entries": {
      "codex": {
        "enabled": true
      }
    }
  }
}
```

Do not enable Codex harness globally for Product Engineer or merge policy decisions.

**Step 3: Run tests**

Expected: model review cannot bypass failed or missing Symphony evidence.

## Acceptance

- Mechanical evidence fails closed before semantic review.
- Static/test-only work can auto-merge only when all checks pass.
- Product/risky work remains in Human Review unless a human explicitly approves merge.
- Failed CI creates Rework/repair flow.
- Restart/resume duplicates are detected before merge.
- Reviewer runs are attributable to OpenClaw task/session ids.
- Failed, disputed, or auto-merged reviews have trajectory exports.
- Reviewer workspace and sessions are isolated from Product Engineer.
- Native Codex/OpenClaw review cannot override missing mechanical evidence.
