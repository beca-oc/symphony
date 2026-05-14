#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const requiredFiles = [
  "scripts/agent/preflight.sh",
  "scripts/agent/validate-fast.sh",
  "scripts/agent/validate-full.sh",
  "AGENTS.md",
  ".github/workflows/symphony-gate.yml",
];

let failed = false;

for (const workflow of workflowRepos()) {
  console.log(`\n== ${workflow.name} (${workflow.githubRepo}) ==`);
  for (const file of requiredFiles) {
    const ok = existsOnGitHub(workflow.githubRepo, file);
    console.log(`${ok ? "OK     " : "MISSING"} ${file}`);
    if (!ok) failed = true;
  }
}

if (failed) {
  console.error("\nAgent contract audit failed.");
  process.exit(1);
}

console.log("\nAgent contract audit OK");

function workflowRepos() {
  const workflowsDir = path.join(root, "elixir/workflows");
  return fs
    .readdirSync(workflowsDir)
    .filter((name) => name.endsWith(".md"))
    .map((name) => {
      const text = fs.readFileSync(path.join(workflowsDir, name), "utf8");
      return {
        name: text.match(/repo:\n\s+name:\s*([^\n]+)/)?.[1]?.trim(),
        githubRepo: text.match(/github_repo:\s*([^\n]+)/)?.[1]?.trim(),
      };
    })
    .filter((repo) => repo.name && repo.githubRepo)
    .sort((a, b) => a.name.localeCompare(b.name));
}

function existsOnGitHub(repo, file) {
  try {
    execFileSync("gh", ["api", `repos/${repo}/contents/${file}?ref=main`, "--jq", ".path"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    return true;
  } catch {
    return false;
  }
}
