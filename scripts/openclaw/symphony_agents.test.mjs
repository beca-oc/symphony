import assert from "node:assert/strict";
import test from "node:test";
import {
  classifyRequestedWork,
  mergeDecision,
  upsertOpenClawConfig,
  validateOpenClawConfig,
  validateReviewerEvidence,
  validateSemanticReview,
  validateTicket,
} from "./symphony_agents.mjs";

test("OpenClaw Product Engineer and Reviewer are isolated", () => {
  const config = upsertOpenClawConfig({ agents: { list: [{ id: "main" }] } });
  assert.deepEqual(validateOpenClawConfig(config), { passed: true, errors: [] });
});

test("Product Engineer must not default to Codex runtime", () => {
  const config = upsertOpenClawConfig({ agents: { list: [] } });
  config.agents.list.find((agent) => agent.id === "openclaw-product-engineer").agentRuntime = { id: "codex" };
  const result = validateOpenClawConfig(config);
  assert.equal(result.passed, false);
  assert.ok(result.errors.includes("product_must_not_default_to_codex_runtime"));
});

test("candidate repos are gated to harness bootstrap before product work", () => {
  assert.deepEqual(classifyRequestedWork({ repo: "causalflow", riskTier: "product-code" }), {
    action: "bootstrap_first",
    reason: "candidate_repo_requires_harness_bootstrap",
  });
  assert.deepEqual(classifyRequestedWork({ repo: "ai-chatbot", riskTier: "product-code" }), {
    action: "allow",
    reason: "allowed_system",
  });
});

test("Symphony tickets fail readiness when deploy evidence is missing", () => {
  const result = validateTicket(`## Goal
Do work.

## Repo
ai-chatbot

## Risk Tier
static

## Scope
docs only

## Acceptance
Branch codex/<issue-id>-<short-slug>.

## Validation
bash scripts/agent/validate-fast.sh

## Failure Handling
Move to Rework.
`);
  assert.equal(result.passed, false);
  assert.ok(result.errors.includes("missing_deploy_check_evidence"));
  assert.ok(result.errors.includes("missing_symphony_gate"));
});

test("Reviewer evidence rejects Linear URLs as check evidence", () => {
  const result = validateReviewerEvidence({
    linear_has_workpad: true,
    linear_has_evidence_gate: true,
    checker_passed: true,
    branch: "codex/BEC-1-test",
    pr_label: "symphony",
    pushed_sha_matches: true,
    validation_recorded: true,
    required_ci_green: true,
    check_url: "https://linear.app/subconscious/issue/BEC-1/fake",
    failure_bucket: "none",
    trace_matches: true,
  });
  assert.equal(result.passed, false);
  assert.ok(result.errors.includes("invalid_check_url"));
});

test("Merge policy allows only low-risk green work without human approval", () => {
  assert.deepEqual(mergeDecision({ riskTier: "static", evidencePassed: true, semanticPassed: true }), {
    action: "merge",
    reason: "low_risk_green",
  });
  assert.deepEqual(mergeDecision({ riskTier: "product-code", evidencePassed: true, semanticPassed: true }), {
    action: "human_review",
    reason: "risk_tier_requires_human",
  });
  assert.deepEqual(mergeDecision({ riskTier: "static", evidencePassed: false, semanticPassed: true }), {
    action: "block",
    reason: "mechanical_evidence_failed",
  });
});

test("Semantic review requires mechanical evidence and current PR head SHA", () => {
  const mechanicalEvidence = {
    linear_has_workpad: true,
    linear_has_evidence_gate: true,
    checker_passed: true,
    branch: "codex/BEC-1-test",
    pr_label: "symphony",
    pushed_sha_matches: true,
    validation_recorded: true,
    required_ci_green: true,
    check_url: "https://github.com/Subconscious-ai/example/actions/runs/1/job/2",
    failure_bucket: "none",
    trace_matches: true,
  };

  assert.deepEqual(
    validateSemanticReview({
      mechanicalEvidence,
      currentHeadSha: "abc123",
      review: {
        reviewer_id: "openclaw-reviewer-merge-captain",
        pr_url: "https://github.com/Subconscious-ai/example/pull/1",
        reviewed_sha: "abc123",
        verdict: "pass",
      },
    }),
    { passed: true, errors: [] }
  );

  const stale = validateSemanticReview({
    mechanicalEvidence,
    currentHeadSha: "def456",
    review: {
      reviewer_id: "openclaw-reviewer-merge-captain",
      pr_url: "https://github.com/Subconscious-ai/example/pull/1",
      reviewed_sha: "abc123",
      verdict: "pass",
    },
  });

  assert.equal(stale.passed, false);
  assert.ok(stale.errors.includes("stale_review_sha"));

  const missingEvidence = validateSemanticReview({
    mechanicalEvidence: { ...mechanicalEvidence, required_ci_green: false },
    currentHeadSha: "abc123",
    review: {
      reviewer_id: "openclaw-reviewer-merge-captain",
      pr_url: "https://github.com/Subconscious-ai/example/pull/1",
      reviewed_sha: "abc123",
      verdict: "pass",
    },
  });

  assert.equal(missingEvidence.passed, false);
  assert.ok(missingEvidence.errors.includes("mechanical_evidence_failed"));
});
