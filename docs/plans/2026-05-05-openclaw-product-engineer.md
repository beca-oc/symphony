# OpenClaw Product Engineer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an OpenClaw Product Engineer agent that turns engineering intent into bounded, Symphony-ready Linear tickets.

**Architecture:** The agent should be a planning and ticket-authoring agent, not a coding agent. It reads human intent, repo allowlists, risk policy, and existing Linear dependency state, then creates parent and child issues that Symphony can execute mechanically. Linear remains the source of truth for issue state and dependencies.

**Tech Stack:** OpenClaw isolated agent workspace, OpenClaw `AGENTS.md` standing orders, Linear API, GitHub repo metadata, Symphony docs, repo-owned `scripts/agent/*` harness contracts, OpenClaw background task ledger, OpenClaw trajectory bundles.

**Documentation basis:** Re-read and apply these OpenClaw docs before implementation: Agent Runtime, Agent Workspace, Multi-Agent Routing, Standing Orders, Background Tasks, Trajectory Bundles, Context, Exec Approvals, Tool-loop Detection, and Codex Harness.

**Key interpretation:** OpenClaw Product Engineer is not a coding worker. It is a bounded planning and ticket-readiness agent. Symphony remains the Codex foreman for repo work.

---

## Guardrails

- Do not edit product code.
- Do not merge PRs.
- Do not mark issues `Done`.
- Do not create a Symphony-ready ticket unless repo, risk tier, validation command, deploy/check evidence, and failure handling are explicit.
- Do not assign candidate repos (`causalactions`, `causalflow`, `causalintelligence`, `colossus`) to Symphony product work until harness bootstrap canaries pass.
- Do not use a shared OpenClaw agent workspace or shared `agentDir` with the Reviewer/Merge Captain.
- Do not launch Codex directly for repo delivery unless the human explicitly opts out of Symphony.
- Do not leave long-running Product Engineer work only in chat history; record the OpenClaw task id/session id and trajectory export path when detached or disputed.

## Task 0: Provision Isolated OpenClaw Agent Workspace

**Files:**
- Create: OpenClaw workspace for `openclaw-product-engineer`
- Create: Product Engineer `AGENTS.md`
- Create: Product Engineer `TOOLS.md`
- Create or configure: OpenClaw agent entry with dedicated workspace, `agentDir`, auth profiles, and session store.

**Step 1: Write the failing isolation test**

Inspect the OpenClaw config/workspace and assert:

- Product Engineer has a dedicated workspace.
- Product Engineer has a dedicated `agentDir`.
- Product Engineer workspace has `AGENTS.md`.
- Product Engineer does not share Reviewer/Merge Captain sessions or auth profiles.
- Product Engineer does not default to Codex runtime for ticket authoring.

Expected failure before implementation:

- Agent config is missing, shared, or ambiguous.

**Step 2: Implement the isolated workspace**

Add standing orders directly to Product Engineer `AGENTS.md`:

- Authority: create bounded Symphony-ready Linear issues.
- Trigger: human engineering intent or scheduled backlog grooming.
- Approval gates: candidate repos, risky work, missing validation, missing deploy/check evidence.
- Escalation: ambiguity, missing repo mapping, missing dependencies, missing secrets boundary.

Keep `AGENTS.md`, `SOUL.md`, and `TOOLS.md` concise. Use `TOOLS.md` for local command conventions only; it must not be treated as tool policy.

**Step 3: Run the test**

Expected: the agent workspace is isolated, concise, and has its standing order loaded from `AGENTS.md`.

## Task 1: Add Agent System Prompt

**Files:**
- Create: OpenClaw agent config for `openclaw-product-engineer`
- Reference: `/Users/aviyashchin/symphony/docs/openclaw-symphony-agents.md`

**Step 1: Write the failing behavior test**

Create an OpenClaw test that gives this input:

```text
Make ai-chatbot remember the selected validation ladder in the UI.
```

Expected failure before implementation:

- No Linear issue is created, or the created issue lacks risk tier, repo, validation, and evidence sections.

**Step 2: Implement the prompt**

Use this instruction core:

```text
You are OpenClaw Product Engineer for Symphony-managed engineering.

Your job is to transform human intent into bounded Linear tickets. You do not write code and you do not merge PRs.

For every ticket, include:
- Goal
- Repo
- Risk Tier
- Scope / Exclusions
- Acceptance
- Validation
- Deploy / Check Evidence
- Dependencies
- Failure Handling

Only use allowed systems from docs/openclaw-symphony-agents.md. Candidate repos require harness bootstrap tickets before product work.

For cross-repo work, create one parent issue and one child per repo. Use Linear dependencies to enforce order.

For every detached or scheduled planning run, record:
- OpenClaw task id
- OpenClaw session id
- trajectory export path when available
- Linear issue ids created or modified
```

**Step 3: Run the test**

Run the OpenClaw agent test harness.

Expected: the generated ticket includes all required sections and does not assign code work directly to OpenClaw.

## Task 2: Add Repo Allowlist And Risk Policy Tooling

**Files:**
- Create or modify: OpenClaw config/data file containing allowed systems.
- Reference: `/Users/aviyashchin/symphony/docs/openclaw-symphony-agents.md`

**Step 1: Write the failing allowlist test**

Input:

```text
Make causalactions do a product feature.
```

Expected failure before implementation:

- The agent creates a product-code issue directly.

**Step 2: Implement allowlist and candidate gating**

The agent must classify:

```json
{
  "ai-chatbot": "practice",
  "spice-harvester": "practice",
  "causl.io": "practice",
  "market-ontology": "practice",
  "causalactions": "candidate",
  "causalflow": "candidate",
  "causalintelligence": "candidate",
  "colossus": "candidate"
}
```

Candidate repo response must create a harness bootstrap ticket first.

**Step 3: Run the test**

Expected: product-code request for a candidate repo becomes a harness bootstrap ticket, not a product work ticket.

## Task 3: Add Cross-Repo Dependency Decomposition

**Files:**
- Modify: OpenClaw Product Engineer prompt/config.
- Test: OpenClaw scenario test for cross-repo issue creation.

**Step 1: Write the failing dependency test**

Input:

```text
Change the ontology contract and update spice-harvester and ai-chatbot consumers.
```

Expected failure before implementation:

- The agent creates one large issue or misses dependency ordering.

**Step 2: Implement dependency rules**

Create:

- One parent coordination issue.
- One `market-ontology` child issue.
- One `spice-harvester` child issue blocked by `market-ontology`.
- One `ai-chatbot` child issue blocked by `spice-harvester`.

**Step 3: Run the test**

Expected: Linear dependency graph enforces ontology first, emitter second, consumer third.

## Task 4: Add Ticket Readiness Validator

**Files:**
- Create: OpenClaw validator for Symphony ticket readiness.

**Step 1: Write the failing validator test**

Give the validator a ticket missing `Deploy / Check Evidence`.

Expected: FAIL with `missing_deploy_check_evidence`.

**Step 2: Implement validator**

Required sections:

- Goal
- Repo
- Risk Tier
- Scope
- Acceptance
- Validation
- Deploy / Check Evidence
- Failure Handling

**Step 3: Run the test**

Expected: incomplete tickets are blocked before entering a Symphony-active state.

## Task 5: Add OpenClaw Observability And Context Budget Checks

**Files:**
- Modify: Product Engineer prompt/config.
- Create: OpenClaw observability test or checklist fixture.

**Step 1: Write the failing observability test**

Run a Product Engineer fixture that creates a cross-repo ticket plan.

Expected failure before implementation:

- The output lacks task id/session id.
- No trajectory export is requested for a failed or disputed run.
- No context budget report is captured.

**Step 2: Implement observability**

Require the Product Engineer to record:

- OpenClaw task id for detached/background runs.
- OpenClaw session id.
- `/context list` or `/context detail` summary during proof runs.
- `/usage tokens` summary during proof runs.
- `/export-trajectory <linear-issue-id>` for failed, disputed, or high-impact planning decisions.

Do not poll task status in a loop. Use push completion or inspect task status only when debugging.

**Step 3: Run the test**

Expected: Product Engineer output is auditable from Linear plus OpenClaw task/trajectory artifacts.

## Task 6: Add Candidate Repo Bootstrap Template

**Files:**
- Modify: Product Engineer prompt/config.
- Test: candidate repo bootstrap scenario.

**Step 1: Write the failing candidate bootstrap test**

Input:

```text
Move causalflow onto Symphony and start giving it product work.
```

Expected failure before implementation:

- The agent creates product tickets before proving harness readiness.

**Step 2: Implement candidate bootstrap output**

For `causalactions`, `causalflow`, `causalintelligence`, and `colossus`, create only harness bootstrap tickets until each repo has:

- `AGENTS.md`
- `docs/agent-harness.md`
- `docs/agent-observability.md`
- `scripts/agent/preflight.sh`
- `scripts/agent/validate-fast.sh`
- `scripts/agent/validate-full.sh`
- `scripts/agent/smoke.sh`
- `symphony-gate`
- Level 0 and Level 1 canary evidence

**Step 3: Run the test**

Expected: candidate repos receive bootstrap and proof tickets, not autonomous product-code tickets.

## Acceptance

- The agent creates bounded Linear tickets with all required sections.
- Candidate repos get harness bootstrap tickets before product work.
- Cross-repo work becomes parent/child Linear issues with dependencies.
- No issue enters a Symphony-active state without passing readiness validation.
- Product Engineer runs are attributable to OpenClaw task/session ids.
- Failed, disputed, or high-impact planning runs have trajectory exports.
- Product Engineer workspace and sessions are isolated from Reviewer/Merge Captain.
