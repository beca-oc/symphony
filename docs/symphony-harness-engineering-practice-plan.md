# Symphony Harness Engineering Practice Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `ai-chatbot`, `spice-harvester`, `causl.io`, and `market-ontology` into Subconscious.ai practice repos for proving long-running autonomous engineering under Symphony.

**Architecture:** Symphony remains the foreman: it selects Linear work, creates isolated workspaces, launches a constrained Codex worker, owns validation/push/PR/evidence/state transition, and records traces. Each repo owns deterministic harness entrypoints, behavior tests, failure fixtures, and docs that make long-running agent work legible, testable, observable, and mechanically constrained.

**Tech Stack:** Symphony Elixir app-server orchestration, Linear, GitHub Actions, GitHub PR checks, Vercel/Checkly where applicable, repo-owned `scripts/agent/*`, Python unittest/pytest, pnpm/Vitest/Playwright/TypeScript.

---

## Current Baseline

On May 5, 2026, all four repos passed Level 0 Symphony proof canaries from fresh `origin/main`.

| Repo | Linear | PR | Uncached Tokens | Runtime | Result |
| --- | --- | --- | ---: | ---: | --- |
| `ai-chatbot` | `BEC-1791` | `Subconscious-ai/ai-chatbot#323` | 65,722 | 268s | Human Review |
| `spice-harvester` | `BEC-1792` | `Subconscious-ai/spice-harvester#200` | 80,211 | 126s | Human Review |
| `market-ontology` | `BEC-1794` | `Subconscious-ai/market-ontology#34` | 52,354 | 115s | Human Review |
| `causl.io` | `BEC-1793` | `Subconscious-ai/causl.io#242` | 57,523 | 350s | Human Review |

`BEC-1800` then proved the corrected evidence URL gate on `spice-harvester`: Symphony recorded `check_url` as the real GitHub Actions `symphony-gate` job, moved the issue to `Human Review`, and completed with 75,418 uncached tokens, 138 seconds runtime, `checker.passed == true`, and `manual_rescue_count == 0`.

This proves small static delivery. It does not prove multi-day autonomous engineering.

OpenClaw should use `docs/openclaw-symphony-agents.md` for the Product Engineer and Reviewer/Merge Captain agent contracts. The Product Engineer creates bounded, dependency-aware Linear issues. The Reviewer/Merge Captain checks deterministic Symphony evidence first, then semantic risk, then applies the merge policy.

## Subconscious.ai Harness Best Practice

Every repo admitted into Symphony engineering work must expose these surfaces:

- `AGENTS.md`: concise repo orientation, working rules, and link to harness docs.
- `docs/agent-harness.md`: validation ladder, known secrets, deploy evidence, failure buckets.
- `docs/agent-observability.md`: trace fields, workpad evidence, PR evidence, manual rescue accounting.
- `scripts/agent/readiness.sh`: fast deterministic repo readiness check.
- `scripts/agent/preflight.sh`: dependency/environment readiness.
- `scripts/agent/validate-fast.sh`: default PR validation, no live destructive side effects.
- `scripts/agent/validate-full.sh`: expanded validation for higher-risk work.
- `scripts/agent/smoke.sh`: tiny local sanity path.
- `.github/workflows/symphony-gate.yml`: required repo-owned check that runs readiness, preflight, and fast validation.

Symphony must own these actions:

- Claim the Linear issue.
- Create and retain an isolated workspace.
- Run the worker with disabled GitHub/Linear/tool/plugin access unless a task explicitly needs it.
- Validate after worker exit.
- Push branch.
- Create draft PR.
- Add `symphony` label.
- Record workpad and evidence gate comments.
- Wait for required repo CI/deploy evidence.
- Move to `Human Review` or `Rework`.

The worker should own only:

- Understand the issue.
- Edit local files.
- Run local checks when useful.
- Commit.
- Stop.

## Proof Ladder

Each repo must pass the following ladder before we use it for real multi-day work:

1. **Level 0: Static canary**
   - Already passed across all four repos.
   - Target: under 100k uncached tokens, no manual rescue.

2. **Level 1: Repo-native validation canary**
   - A small test-only or docs+test change that must exercise the repo harness.
   - Target: under 150k uncached tokens, no manual rescue.

3. **Level 2: Small behavior change**
   - One real user-facing or domain-facing behavior change with a meaningful failing test first.
   - Target: under 250k uncached tokens, no manual rescue.

4. **Level 3: Failure recovery exercise**
   - Intentionally introduce one recoverable failure mode: CI failure, merge conflict, or validation failure.
   - Target: Symphony detects and routes to repair or `Rework` with clear evidence.

5. **Level 4: Multi-PR dependency chain**
   - One parent Linear issue with repo-specific child issues and one PR per repo.
   - Target: no child moves to `Human Review` before its own evidence passes; dependencies are visible in Linear.

6. **Level 5: Restart/resume durability**
   - Kill/restart a Symphony runner during a run.
   - Target: no duplicate PRs, no duplicate comments, no lost workspace state, no premature `Done`.

## Shared Symphony Plan

### Task S1: Add Practice-Run Dossier Generation

**Files:**
- Modify: `elixir/lib/symphony_elixir/run_trace.ex`
- Modify: `elixir/lib/symphony_elixir/delivery_publisher.ex`
- Test: `elixir/test/symphony_elixir/run_trace_test.exs`
- Test: `elixir/test/symphony_elixir/delivery_publisher_test.exs`

- [ ] **Step 1: Write failing trace test**
  - Assert a completed run records `repo.name`, `issue_identifier`, `pr_url`, `check_url`, `runtime_seconds`, `tokens.uncached_total_tokens`, `failure_bucket`, `manual_rescue_count`, and `outcome`.
  - Run: `cd elixir && mix test test/symphony_elixir/run_trace_test.exs`
  - Expected: FAIL because some fields are absent.

- [ ] **Step 2: Implement minimal trace fields**
  - Extend trace serialization without changing existing field names.
  - Preserve backward compatibility with existing ndjson readers.

- [ ] **Step 3: Write failing publisher test**
  - Assert the Linear evidence gate comment includes a compact measurement block.
  - Run: `cd elixir && mix test test/symphony_elixir/delivery_publisher_test.exs`
  - Expected: FAIL until publisher emits the block.

- [ ] **Step 4: Implement evidence measurement block**
  - Include runtime, uncached tokens, total tokens, validation command, PR URL, check/deploy URL, and failure bucket.

- [ ] **Step 5: Validate**
  - Run: `cd elixir && mix test`
  - Run: `cd elixir && mix build`

### Task S1.5: Add Trace-Backed Completed Run History

**Files:**
- Modify: `elixir/lib/symphony_elixir/run_trace.ex`
- Modify: `elixir/lib/symphony_elixir_web/presenter.ex`
- Modify: `elixir/lib/symphony_elixir_web/live/dashboard_live.ex`
- Test: `elixir/test/symphony_elixir/run_trace_test.exs`
- Test: `elixir/test/symphony_elixir/extensions_test.exs`

- [x] **Step 1: Write failing trace reader test**
  - Assert `RunTrace.recent/1` returns latest valid NDJSON records first and ignores malformed lines.

- [x] **Step 2: Implement trace reader**
  - Add a bounded trace reader that returns completed run records from `symphony-runs.ndjson`.

- [x] **Step 3: Write failing API/dashboard tests**
  - Assert `/api/v1/state` includes `completed_runs`.
  - Assert the dashboard renders a `Completed runs` section.

- [x] **Step 4: Implement API and dashboard projection**
  - Add recent completed run history to the state payload and dashboard.

- [ ] **Step 5: Validate**
  - Run: `cd elixir && mix test`
  - Run: `cd elixir && mix build`

### Task S2: Add Restart/Resume Contract Tests

**Files:**
- Modify: `elixir/lib/symphony_elixir/orchestrator.ex`
- Modify: `elixir/lib/symphony_elixir/delivery_publisher.ex`
- Test: `elixir/test/symphony_elixir/orchestrator_resume_test.exs`

- [ ] **Step 1: Write failing resume test**
  - Given an issue with existing workpad, branch, draft PR, and validation evidence, restart orchestration.
  - Assert Symphony updates existing evidence instead of creating duplicate PR/comment.

- [ ] **Step 2: Implement idempotent lookup**
  - Reuse PRs by branch and Linear attachment.
  - Reuse `## Codex Workpad` and `## Symphony Evidence Gate` comments by heading.

- [ ] **Step 3: Validate**
  - Run: `cd elixir && mix test test/symphony_elixir/orchestrator_resume_test.exs`
  - Run: `cd elixir && mix test`

### Task S3: Add Failure-Bucket Routing

**Files:**
- Modify: `elixir/lib/symphony_elixir/delivery_evidence.ex`
- Modify: `elixir/lib/symphony_elixir/orchestrator.ex`
- Test: `elixir/test/symphony_elixir/delivery_evidence_test.exs`

- [ ] **Step 1: Write failing evidence failures**
  - Cases: missing workpad, missing pushed SHA, failing `symphony-gate`, missing deploy evidence, merge conflict, validation failure.
  - Assert each maps to a stable failure bucket.

- [ ] **Step 2: Implement stable buckets**
  - Use names: `missing_workpad`, `branch_mismatch`, `missing_pr`, `missing_label`, `missing_validation`, `missing_deploy_evidence`, `ci_failed`, `merge_conflict`, `token_budget`, `agent_no_commit`.

- [ ] **Step 3: Route Rework comments**
  - Ensure `Rework` comments always include bucket, blocking evidence, and exact retry command or operator action.

- [ ] **Step 4: Validate**
  - Run: `cd elixir && mix test test/symphony_elixir/delivery_evidence_test.exs`
  - Run: `cd elixir && mix test`

## ai-chatbot Practice Plan

### Objective

Prove Symphony can handle frontend-heavy TypeScript engineering with fast checks, browser-facing behavior, CI repair, and Vercel evidence.

### Level 1: Repo-Native Validation Canary

**Files:**
- Modify: `tests/unit/agent-harness-scripts.test.ts`
- Modify: `docs/agent-observability.md`

- [ ] Add a failing test that asserts `docs/agent-observability.md` documents `manual_rescue_count`.
- [ ] Run: `pnpm exec tsx --test tests/unit/agent-harness-scripts.test.ts`
- [ ] Add the minimal doc line.
- [ ] Run: `bash scripts/agent/validate-fast.sh`.
- [ ] Run via Symphony as a Linear issue.

### Level 2: Small Behavior Change

**Proposed issue:** `ai-chatbot: make harness smoke output include active validation ladder`

**Files:**
- Modify: `tests/smoke/harness-smoke.test.ts`
- Modify: `scripts/agent/smoke.sh`

- [ ] Write a failing smoke test that expects `scripts/agent/smoke.sh` output to include `readiness`, `preflight`, and `validate-fast`.
- [ ] Implement only enough shell output to pass.
- [ ] Run: `pnpm exec tsx --test tests/smoke/harness-smoke.test.ts`
- [ ] Run: `bash scripts/agent/validate-fast.sh`.
- [ ] Run via Symphony.

### Level 3: CI Failure Repair Exercise

**Proposed issue:** `ai-chatbot: repair intentional harness smoke regression`

- [ ] Create a branch that intentionally breaks the smoke output assertion.
- [ ] Confirm `symphony-gate` fails.
- [ ] Create a Linear repair issue that asks Symphony to diagnose and fix the failing check.
- [ ] Pass condition: Symphony creates a second draft PR that fixes the test and records the failing check URL plus repair evidence.

### Level 4: Merge Conflict Exercise

- [ ] Create two canary issues that both edit the same small section of `docs/agent-observability.md`.
- [ ] Merge the first PR.
- [ ] Let Symphony handle the second branch update.
- [ ] Pass condition: no force overwrite, conflict is resolved with both markers preserved, PR remains draft.

### Level 5: Restart/Resume Exercise

- [ ] Start a Symphony ai-chatbot run.
- [ ] Kill the runner after the draft PR exists but before Vercel evidence completes.
- [ ] Restart the runner.
- [ ] Pass condition: one PR, one workpad, one evidence gate comment, final state `Human Review`.

## spice-harvester Practice Plan

### Objective

Prove Symphony can handle Python/shell data-pipeline work without live ingest side effects unless explicitly requested.

### Level 1: Repo-Native Validation Canary

**Files:**
- Modify: `tests/test_agent_harness_contract.py`
- Modify: `docs/agent-observability.md`

- [ ] Add a failing test that requires the docs to state fast validation must not run live ingest.
- [ ] Run: `python3 -m unittest tests/test_agent_harness_contract.py -v`
- [ ] Add the minimal docs line.
- [ ] Run: `bash scripts/agent/validate-fast.sh`.
- [ ] Run via Symphony.

### Level 2: Small Behavior Change

**Proposed issue:** `spice-harvester: make doc-rot failure bucket explicit`

**Files:**
- Modify: `tests/test_agent_harness_contract.py`
- Modify: `scripts/check-doc-rot.sh`
- Modify: `docs/agent-harness.md`

- [ ] Write a failing test that creates a temporary stale doc fixture and asserts doc-rot returns a recognizable failure message.
- [ ] Implement the smallest stable error message in `scripts/check-doc-rot.sh`.
- [ ] Document the `doc_rot` failure bucket.
- [ ] Run: `python3 -m unittest tests/test_agent_harness_contract.py -v`
- [ ] Run: `bash scripts/agent/validate-fast.sh`.
- [ ] Run via Symphony.

### Level 3: CI Failure Repair Exercise

- [ ] Intentionally break the doc-rot fixture in a PR.
- [ ] Let GitHub `symphony-gate` fail.
- [ ] File a repair issue.
- [ ] Pass condition: Symphony diagnoses static validation failure, fixes only docs/check fixture, and records failed then passing check evidence.

### Level 4: Live-Boundary Exercise

- [ ] File an issue that asks for ingest-related work without credentials.
- [ ] Expected behavior: Symphony moves to `Rework` with `missing_secret_or_live_boundary`, not `Human Review`.
- [ ] Then file a second issue with explicit credential/side-effect boundary.
- [ ] Expected behavior: full validation is allowed only when the issue declares live side effects.

### Level 5: Restart/Resume Exercise

- [ ] Kill Symphony after local validation but before evidence gate.
- [ ] Restart.
- [ ] Pass condition: existing branch and PR are reused; workpad is updated, not duplicated.

## causl.io Practice Plan

### Objective

Prove Symphony can handle a large pnpm/Next-style repo with Vercel, Checkly, skipped optional checks, and longer CI latency.

### Level 1: Repo-Native Validation Canary

**Files:**
- Modify: `scripts/agent/harness-contract.test.ts`
- Modify: `docs/agent-observability.md`

- [ ] Add a failing test that requires observability docs to name Vercel and Checkly as evidence surfaces.
- [ ] Run: `pnpm exec vitest run --config vitest.harness.config.ts`
- [ ] Add minimal docs text.
- [ ] Run: `bash scripts/agent/validate-fast.sh`.
- [ ] Run via Symphony.

### Level 2: Small Behavior Change

**Proposed issue:** `causl.io: expose harness smoke metadata in deterministic output`

**Files:**
- Modify: `scripts/agent/harness-contract.test.ts`
- Modify: `scripts/agent/smoke.sh`

- [ ] Write a failing test that runs `scripts/agent/smoke.sh` and expects repo name, validation ladder, and deploy evidence type.
- [ ] Implement minimal shell output.
- [ ] Run: `pnpm exec vitest run --config vitest.harness.config.ts`
- [ ] Run: `bash scripts/agent/validate-fast.sh`.
- [ ] Run via Symphony.

### Level 3: CI Failure Repair Exercise

- [ ] Introduce a harmless TypeScript type failure in a canary branch.
- [ ] Confirm `symphony-gate` and `Run static checks` fail.
- [ ] File a repair issue.
- [ ] Pass condition: Symphony identifies typecheck failure, fixes it, preserves app behavior, and records failing/passing check URLs.

### Level 4: Optional Check Semantics Exercise

- [ ] Ensure `Run Storybook` remains allowed as skipped in workflow config.
- [ ] Add a test in Symphony proving skipped allowed checks do not block `Human Review`, but failed required checks do.
- [ ] Run one causl canary where Storybook is skipped and required checks pass.

### Level 5: Restart/Resume Exercise

- [ ] Kill Symphony while Vercel is pending.
- [ ] Restart.
- [ ] Pass condition: one PR, evidence waits for Vercel/check URL, no duplicate comment spam.

## market-ontology Practice Plan

### Objective

Prove Symphony can handle deterministic contract/schema work and orchestrate it as the upstream source of truth for cross-repo changes.

### Level 1: Repo-Native Validation Canary

**Files:**
- Modify: `tests/test_agent_harness_contract.py`
- Modify: `docs/agent-observability.md`

- [ ] Add a failing test that requires observability docs to name generated contract drift as a failure bucket.
- [ ] Run: `python3 -m unittest tests/test_agent_harness_contract.py -v`
- [ ] Add minimal docs text.
- [ ] Run: `bash scripts/agent/validate-fast.sh`.
- [ ] Run via Symphony.

### Level 2: Small Behavior Change

**Proposed issue:** `market-ontology: add deterministic contract drift smoke fixture`

**Files:**
- Modify: `tests/test_agent_harness_contract.py`
- Modify: `scripts/agent/smoke.sh`

- [ ] Write a failing test that runs `scripts/agent/smoke.sh` and expects contract validation commands to be listed.
- [ ] Implement minimal smoke output.
- [ ] Run: `python3 -m unittest tests/test_agent_harness_contract.py -v`
- [ ] Run: `bash scripts/agent/validate-fast.sh`.
- [ ] Run via Symphony.

### Level 3: CI Failure Repair Exercise

- [ ] Intentionally create generated contract drift in a canary branch.
- [ ] Confirm `validate-fast` fails with generated contract check failure.
- [ ] File a Symphony repair issue.
- [ ] Pass condition: Symphony regenerates or reverts correctly, explains contract drift, and records evidence.

### Level 4: Cross-Repo Dependency Chain

**Parent issue:** `Cross-repo ontology contract propagation practice`

Child sequence:

1. `market-ontology`: add tiny schema/contract fixture field behind tests.
2. `spice-harvester`: emit or preserve the new contract field.
3. `ai-chatbot`: consume/read the new field in a test-only or non-user-visible path.
4. `causl.io`: document or validate compatibility if relevant.

- [ ] Add Linear relations so downstream issues are blocked by upstream PRs.
- [ ] Ensure Symphony runs one repo issue at a time.
- [ ] Pass condition: one draft PR per repo, each with evidence, no downstream `Human Review` before upstream dependency is satisfied.

### Level 5: Restart/Resume Exercise

- [ ] Kill Symphony between contract validation and evidence publishing.
- [ ] Restart.
- [ ] Pass condition: generated contracts are not rewritten unexpectedly; existing PR/evidence are reused.

## Measurement Standard

Every practice run must record:

- Linear issue ID and URL.
- Repo and project.
- Branch.
- Workspace path.
- Draft PR URL.
- Changed files.
- Commit SHA.
- Validation command/result.
- Required check/deploy URL.
- Runtime seconds.
- Uncached input tokens.
- Output tokens.
- Uncached total tokens.
- Total tokens.
- Turn count.
- Retry count.
- Failure bucket.
- Manual rescue count.
- Final Linear state.

Pass criteria for the next round:

- Level 1: all four repos pass under 150k uncached tokens.
- Level 2: all four repos pass under 250k uncached tokens.
- Failure recovery: at least one repo per failure class reaches `Rework` or repaired `Human Review` with accurate evidence.
- Restart/resume: no duplicate PRs or duplicate workpads.
- Cross-repo chain: dependency state is visible in Linear and PR evidence is per repo.

## Recommended Sequence

1. Implement shared Symphony trace/evidence improvements.
2. Run Level 1 validation canaries across all four repos.
3. Run Level 2 small behavior changes across all four repos.
4. Run one CI repair exercise in `causl.io` and one contract-drift repair in `market-ontology`.
5. Run restart/resume in `ai-chatbot` and `spice-harvester`.
6. Run the cross-repo ontology dependency chain.
7. Publish `docs/symphony-harness-engineering-best-practice.md` from observed results, not aspirational process.
