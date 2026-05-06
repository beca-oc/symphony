import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const agentSpec = {
  product: {
    id: "openclaw-product-engineer",
    workspace: `${process.env.HOME}/.openclaw/workspace-symphony-product-engineer`,
    agentDir: `${process.env.HOME}/.openclaw/agents/openclaw-product-engineer/agent`,
  },
  reviewer: {
    id: "openclaw-reviewer-merge-captain",
    workspace: `${process.env.HOME}/.openclaw/workspace-symphony-reviewer-merge-captain`,
    agentDir: `${process.env.HOME}/.openclaw/agents/openclaw-reviewer-merge-captain/agent`,
  },
};

export const allowedSystems = {
  "ai-chatbot": "practice",
  "spice-harvester": "practice",
  "causl.io": "practice",
  "market-ontology": "practice",
  causalactions: "candidate",
  causalflow: "candidate",
  causalintelligence: "candidate",
  colossus: "candidate",
};

const requiredTicketSections = [
  "Goal",
  "Repo",
  "Risk Tier",
  "Scope",
  "Acceptance",
  "Validation",
  "Deploy / Check Evidence",
  "Failure Handling",
];

const realCheckUrlHosts = [
  "github.com",
  "vercel.com",
  "checklyhq.com",
  "app.checklyhq.com",
];

export function validateOpenClawConfig(config) {
  const agents = config?.agents?.list ?? [];
  const byId = new Map(agents.map((agent) => [agent.id, agent]));
  const errors = [];

  for (const [role, spec] of Object.entries(agentSpec)) {
    const agent = byId.get(spec.id);
    if (!agent) {
      errors.push(`missing_${role}_agent`);
      continue;
    }

    if (agent.workspace !== spec.workspace) errors.push(`${role}_workspace_mismatch`);
    if (agent.agentDir !== spec.agentDir) errors.push(`${role}_agent_dir_mismatch`);
    if (agent.agentRuntime?.id === "codex") errors.push(`${role}_must_not_default_to_codex_runtime`);
  }

  if (byId.get(agentSpec.product.id)?.workspace === byId.get(agentSpec.reviewer.id)?.workspace) {
    errors.push("shared_workspace");
  }

  if (byId.get(agentSpec.product.id)?.agentDir === byId.get(agentSpec.reviewer.id)?.agentDir) {
    errors.push("shared_agent_dir");
  }

  return { passed: errors.length === 0, errors };
}

export function classifyRequestedWork({ repo, riskTier }) {
  const status = allowedSystems[repo];
  if (!status) return { action: "block", reason: "repo_not_allowed" };
  if (status === "candidate" && riskTier !== "static") {
    return { action: "bootstrap_first", reason: "candidate_repo_requires_harness_bootstrap" };
  }
  return { action: "allow", reason: "allowed_system" };
}

export function validateTicket(ticketMarkdown) {
  const errors = [];
  for (const section of requiredTicketSections) {
    const pattern = new RegExp(`(^|\\n)## ${escapeRegExp(section)}(\\n|$)`);
    if (!pattern.test(ticketMarkdown)) errors.push(`missing_${slug(section)}`);
  }
  if (!/codex\/<issue-id>-<short-slug>|codex\/[A-Z]+-\d+-/.test(ticketMarkdown)) {
    errors.push("missing_codex_branch_rule");
  }
  if (!/symphony-gate/.test(ticketMarkdown)) errors.push("missing_symphony_gate");
  return { passed: errors.length === 0, errors };
}

export function validateReviewerEvidence(evidence) {
  const errors = [];
  const checks = {
    missing_workpad: evidence.linear_has_workpad,
    missing_evidence_gate: evidence.linear_has_evidence_gate,
    checker_failed: evidence.checker_passed,
    branch_mismatch: /^codex\/[A-Z]+-\d+-[a-z0-9-]+$/.test(evidence.branch ?? ""),
    missing_symphony_label: evidence.pr_label === "symphony",
    sha_mismatch: evidence.pushed_sha_matches,
    missing_validation: evidence.validation_recorded,
    ci_not_green: evidence.required_ci_green,
    failure_bucket: evidence.failure_bucket === "none",
    stale_trace: evidence.trace_matches === true,
  };

  for (const [error, passed] of Object.entries(checks)) {
    if (!passed) errors.push(error);
  }

  if (!isRealCheckUrl(evidence.check_url)) errors.push("invalid_check_url");
  return { passed: errors.length === 0, errors };
}

export function validateSemanticReview({ mechanicalEvidence, currentHeadSha, review }) {
  const errors = [];
  const mechanical = validateReviewerEvidence(mechanicalEvidence ?? {});

  if (!mechanical.passed) errors.push("mechanical_evidence_failed");
  if (!review?.reviewer_id) errors.push("missing_reviewer_id");
  if (!review?.pr_url) errors.push("missing_review_pr_url");
  if (!review?.reviewed_sha) errors.push("missing_reviewed_sha");
  if (!["pass", "request_changes", "blocked"].includes(review?.verdict)) errors.push("invalid_review_verdict");
  if (review?.reviewed_sha && currentHeadSha && review.reviewed_sha !== currentHeadSha) errors.push("stale_review_sha");

  return { passed: errors.length === 0, errors };
}

export function mergeDecision({ riskTier, evidencePassed, semanticPassed, humanApproved = false }) {
  if (!evidencePassed) return { action: "block", reason: "mechanical_evidence_failed" };
  if (!semanticPassed) return { action: "block", reason: "semantic_review_failed" };
  if (riskTier === "static" || riskTier === "test-only") return { action: "merge", reason: "low_risk_green" };
  if (humanApproved) return { action: "merge", reason: "human_approved_risky_merge" };
  return { action: "human_review", reason: "risk_tier_requires_human" };
}

export function writeWorkspaceFiles({ baseDir = process.env.HOME } = {}) {
  const root = path.join(baseDir, ".openclaw");
  const productWorkspace = path.join(root, "workspace-symphony-product-engineer");
  const reviewerWorkspace = path.join(root, "workspace-symphony-reviewer-merge-captain");

  fs.mkdirSync(productWorkspace, { recursive: true });
  fs.mkdirSync(reviewerWorkspace, { recursive: true });
  fs.mkdirSync(path.join(root, "agents", agentSpec.product.id, "agent"), { recursive: true });
  fs.mkdirSync(path.join(root, "agents", agentSpec.reviewer.id, "agent"), { recursive: true });

  fs.writeFileSync(path.join(productWorkspace, "AGENTS.md"), productAgentsMd);
  fs.writeFileSync(path.join(productWorkspace, "TOOLS.md"), sharedToolsMd);
  fs.writeFileSync(path.join(reviewerWorkspace, "AGENTS.md"), reviewerAgentsMd);
  fs.writeFileSync(path.join(reviewerWorkspace, "TOOLS.md"), sharedToolsMd);
}

export function upsertOpenClawConfig(config) {
  const next = structuredClone(config);
  next.agents ??= {};
  next.agents.list ??= [];
  upsertAgent(next.agents.list, {
    id: agentSpec.product.id,
    workspace: agentSpec.product.workspace,
    agentDir: agentSpec.product.agentDir,
    model: "openai/gpt-5.5",
    thinkingDefault: "high",
  });
  upsertAgent(next.agents.list, {
    id: agentSpec.reviewer.id,
    workspace: agentSpec.reviewer.workspace,
    agentDir: agentSpec.reviewer.agentDir,
    model: "openai/gpt-5.5",
    thinkingDefault: "high",
  });
  return next;
}

function upsertAgent(list, agent) {
  const index = list.findIndex((item) => item.id === agent.id);
  if (index === -1) list.push(agent);
  else list[index] = { ...list[index], ...agent, agentRuntime: undefined };
}

function isRealCheckUrl(value) {
  try {
    const url = new URL(value);
    if (url.hostname === "linear.app") return false;
    return realCheckUrlHosts.some((host) => url.hostname === host || url.hostname.endsWith(`.${host}`));
  } catch {
    return false;
  }
}

function slug(value) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export const productAgentsMd = `# OpenClaw Product Engineer

Authority: create bounded Linear tickets for Symphony-managed engineering.

Rules:
- Do not write product code.
- Do not merge PRs.
- Every Symphony ticket needs repo, risk tier, scope, validation, evidence, dependencies, and failure handling.
- Candidate repos require harness bootstrap before product work.
- Cross-repo work becomes one parent issue plus ordered child issues.
- Record OpenClaw task id, session id, and trajectory path for detached or disputed runs.
`;

export const reviewerAgentsMd = `# OpenClaw Reviewer And Merge Captain

Authority: verify Symphony output and merge only low-risk work under policy.

Rules:
- Mechanical evidence comes before semantic review.
- Never merge if workpad, evidence gate, PR label, SHA, validation, required CI, or check/deploy URL is missing.
- Static and test-only work may merge when evidence and semantic review pass.
- Product-code, migration, secrets, auth, billing, or live-data work requires explicit human approval.
- Failed evidence goes to Rework with a failure bucket.
- Record OpenClaw task id, session id, reviewed PR SHA, and trajectory path for failed, disputed, or auto-merged reviews.
`;

export const sharedToolsMd = `# Tools

- Linear is the control plane.
- GitHub PR checks are mechanical evidence.
- Symphony traces and evidence gates are required before merge decisions.
- OpenClaw chat history is not sufficient audit evidence.
`;

async function main() {
  const [command, configPath = `${process.env.HOME}/.openclaw/openclaw.json`] = process.argv.slice(2);
  if (!command) return;

  if (command === "install") {
    writeWorkspaceFiles();
    const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
    fs.writeFileSync(configPath, `${JSON.stringify(upsertOpenClawConfig(config), null, 2)}\n`);
    console.log("installed");
    return;
  }

  if (command === "validate-config") {
    const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
    const result = validateOpenClawConfig(config);
    console.log(JSON.stringify(result, null, 2));
    process.exitCode = result.passed ? 0 : 1;
    return;
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main();
}
