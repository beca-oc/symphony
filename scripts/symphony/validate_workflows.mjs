import fs from "node:fs";
import path from "node:path";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const workflows = [
  ["ai-chatbot", "elixir/workflows/ai-chatbot.md", 4001, "Subconscious-ai/ai-chatbot", "vercel"],
  ["spice-harvester", "elixir/workflows/spice-harvester.md", 4002, "Subconscious-ai/spice-harvester", "github_checks"],
  ["causl.io", "elixir/workflows/causl-io.md", 4003, "Subconscious-ai/causl.io", "vercel"],
  ["market-ontology", "elixir/workflows/market-ontology.md", 4004, "Subconscious-ai/market-ontology", "github_checks"],
  ["johnny-5-rebuild", "elixir/workflows/johnny-5-rebuild.md", 4005, "Subconscious-ai/johnny-5-rebuild", "vercel"],
  ["design-system", "elixir/workflows/design-system.md", 4006, "Subconscious-ai/design-system", "github_checks"],
  ["causalactions", "elixir/workflows/causalactions.md", 4007, "Subconscious-ai/causalactions", "vercel"],
  ["causalflow", "elixir/workflows/causalflow.md", 4008, "Subconscious-ai/causalflow", "vercel"],
  ["causalintelligence", "elixir/workflows/causalintelligence.md", 4009, "Subconscious-ai/causalintelligence", "vercel"],
  ["sizzl-trustgraph", "elixir/workflows/sizzl-trustgraph.md", 4010, "Subconscious-ai/sizzl-trustgraph", "github_checks"],
  ["website", "elixir/workflows/website.md", 4011, "Subconscious-ai/website", "vercel"],
];

const failures = [];

for (const [name, relPath, port, githubRepo, deployEvidence] of workflows) {
  const file = path.join(root, relPath);
  const text = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "";
  check(text, relPath, `repo:\n  name: ${name}`, "repo name");
  check(text, relPath, `github_repo: ${githubRepo}`, "GitHub repo");
  if (name === "market-ontology") {
    check(text, relPath, "preflight: PYTHON=.venv/bin/python bash scripts/agent/preflight.sh", "preflight command");
    check(text, relPath, "fast: PYTHON=.venv/bin/python bash scripts/agent/validate-fast.sh", "fast validation command");
    check(text, relPath, "full: PYTHON=.venv/bin/python bash scripts/agent/validate-full.sh", "full validation command");
    check(text, relPath, "before_run: |", "idempotent before_run setup hook");
    check(text, relPath, "test -d .venv || python3 -m venv .venv", "idempotent virtualenv setup");
    check(text, relPath, '.venv/bin/python -m pip install -e ".[dev]"', "market-ontology dev dependency setup");
  } else if (name === "sizzl-trustgraph") {
    check(text, relPath, "preflight: bash scripts/agent/preflight.sh", "preflight command");
    check(
      text,
      relPath,
      "fast: MARKET_ONTOLOGY_DIR=/__symphony_no_local_market_ontology__ bash scripts/agent/validate-fast.sh",
      "hermetic fast validation command",
    );
    check(
      text,
      relPath,
      "full: MARKET_ONTOLOGY_DIR=/__symphony_no_local_market_ontology__ bash scripts/agent/validate-full.sh",
      "hermetic full validation command",
    );
  } else if (name === "website") {
    check(text, relPath, "preflight: npm ci --ignore-scripts", "preflight command");
    check(text, relPath, "fast: npm run build", "fast validation command");
    check(text, relPath, "full: npm run build", "full validation command");
  } else {
    check(text, relPath, "preflight: bash scripts/agent/preflight.sh", "preflight command");
    check(text, relPath, "fast: bash scripts/agent/validate-fast.sh", "fast validation command");
    check(text, relPath, "full: bash scripts/agent/validate-full.sh", "full validation command");
  }
  check(text, relPath, `deploy_evidence: ${deployEvidence}`, "deploy evidence mode");
  check(text, relPath, "evidence_required: true", "evidence gate enabled");
  if (name === "website") {
    check(text, relPath, "github_required_checks: []", "no repo-owned Symphony gate yet");
    check(text, relPath, "require_all_checks: false", "Vercel-only website gate");
  } else {
    check(text, relPath, 'github_required_checks: ["symphony-gate"]', "required symphony-gate check");
    check(text, relPath, "require_all_checks: true", "all non-optional checks gate");
  }
  check(text, relPath, "repair:\n  max_attempts: 2", "bounded repair policy");
  check(text, relPath, "max_concurrent_agents: 1", "single worker per repo");
  check(text, relPath, "max_turns: 1", "single-turn delivery handoff");
  check(text, relPath, "max_uncached_tokens: 250000", "hard uncached token cap");
  check(text, relPath, "continue_after_normal_exit: false", "post-agent evidence handoff");
  check(text, relPath, 'HOME="$HOME/.symphony/worker-home"', "isolated Symphony worker home");
  check(text, relPath, 'CODEX_HOME="$HOME/.symphony/codex-home"', "isolated Symphony Codex home");
  check(text, relPath, 'model="gpt-5.5"', "GPT-5.5 worker model");
  check(text, relPath, "model_reasoning_effort=high", "high reasoning effort");
  check(text, relPath, "features.apps=false", "worker apps disabled");
  check(text, relPath, "features.browser_use=false", "worker browser disabled");
  check(text, relPath, "features.tool_search=false", "worker tool search disabled");
  check(text, relPath, "features.image_generation=false", "worker image generation disabled");
  check(text, relPath, "features.computer_use=false", "worker computer use disabled");
  check(text, relPath, "features.workspace_dependencies=false", "worker workspace dependency helpers disabled");
  check(text, relPath, "features.multi_agent=false", "worker subagents disabled");
  check(text, relPath, "Do not invoke Codex skills or read files under `~/.codex` or `~/.agents`", "no interactive Codex profile reads");
  check(text, relPath, "Do not run broad validation inside Codex", "Symphony-owned validation boundary");
  check(text, relPath, "Do not call Linear tools, GitHub tools, `gh`, or `git push`.", "Symphony-owned publishing rule");
  check(text, relPath, "Symphony will run validation, push the branch, create the draft PR", "Symphony-owned evidence rule");
  console.log(`${name.padEnd(16)} -> port ${port} -> ${relPath}`);
}

if (failures.length > 0) {
  console.error("\nWorkflow validation failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("\nWorkflow validation OK");

function check(text, relPath, needle, label) {
  if (!text.includes(needle)) failures.push(`${relPath}: missing ${label}`);
}
