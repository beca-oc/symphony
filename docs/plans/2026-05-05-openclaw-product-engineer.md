# OpenClaw Product Engineer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an OpenClaw Product Engineer agent that turns engineering intent into bounded, Symphony-ready Linear tickets.

**Architecture:** The agent should be a planning and ticket-authoring agent, not a coding agent. It reads human intent, repo allowlists, risk policy, and existing Linear dependency state, then creates parent and child issues that Symphony can execute mechanically. Linear remains the source of truth for issue state and dependencies.

**Tech Stack:** OpenClaw agent configuration, Linear API, GitHub repo metadata, Symphony docs, repo-owned `scripts/agent/*` harness contracts.

---

## Guardrails

- Do not edit product code.
- Do not merge PRs.
- Do not mark issues `Done`.
- Do not create a Symphony-ready ticket unless repo, risk tier, validation command, deploy/check evidence, and failure handling are explicit.
- Do not assign candidate repos (`causalactions`, `causalflow`, `causalintelligence`, `colossus`) to Symphony product work until harness bootstrap canaries pass.

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

## Acceptance

- The agent creates bounded Linear tickets with all required sections.
- Candidate repos get harness bootstrap tickets before product work.
- Cross-repo work becomes parent/child Linear issues with dependencies.
- No issue enters a Symphony-active state without passing readiness validation.

