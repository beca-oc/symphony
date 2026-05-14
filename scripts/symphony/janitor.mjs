#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const workflowsDir = path.join(root, "elixir/workflows");
const args = new Set(process.argv.slice(2));
const apply = args.has("--apply");
const includeLinear = args.has("--linear");
const ageDays = numberArg("--age-days", 7);
const repoFilter = valueArg("--repo");
const cutoff = new Date(Date.now() - ageDays * 24 * 60 * 60 * 1000);

const repos = readRepos().filter((repo) => !repoFilter || repo === repoFilter);
if (repos.length === 0) fail(`No workflow repos matched${repoFilter ? ` ${repoFilter}` : ""}.`);

console.log(`Symphony janitor ${apply ? "APPLY" : "DRY-RUN"}; cutoff=${cutoff.toISOString()}`);
console.log(`Repos: ${repos.join(", ")}`);

for (const repo of repos) {
  inspectRepo(repo);
}

if (includeLinear) {
  await inspectLinear();
}

inspectLanes();

function readRepos() {
  return fs
    .readdirSync(workflowsDir)
    .filter((name) => name.endsWith(".md"))
    .map((name) => {
      const text = fs.readFileSync(path.join(workflowsDir, name), "utf8");
      return text.match(/github_repo:\s*([^\n]+)/)?.[1]?.trim();
    })
    .filter(Boolean)
    .sort();
}

function inspectRepo(repo) {
  console.log(`\n== ${repo} ==`);
  const openBranches = new Set(
    gh(["pr", "list", "--repo", repo, "--state", "open", "--json", "headRefName", "--jq", ".[].headRefName"])
      .trim()
      .split("\n")
      .filter(Boolean),
  );

  const staleCanaries = jsonGh([
    "pr",
    "list",
    "--repo",
    repo,
    "--state",
    "open",
    "--label",
    "symphony",
    "--json",
    "number,title,headRefName,createdAt,labels,url",
  ]).filter((pr) => {
    const haystack = `${pr.title ?? ""} ${pr.headRefName ?? ""} ${(pr.labels ?? [])
      .map((label) => label.name)
      .join(" ")}`.toLowerCase();
    return haystack.includes("canary") && new Date(pr.createdAt) < cutoff;
  });

  if (staleCanaries.length === 0) {
    console.log("stale canary PRs: none");
  } else {
    for (const pr of staleCanaries) {
      action(`close stale canary PR ${pr.url}`, () =>
        gh(["pr", "close", String(pr.number), "--repo", repo, "--comment", "Closing stale Symphony canary via janitor."]),
      );
    }
  }

  const closedBranches = jsonGh([
    "pr",
    "list",
    "--repo",
    repo,
    "--state",
    "closed",
    "--limit",
    "100",
    "--json",
    "headRefName,headRepositoryOwner,updatedAt,url",
  ])
    .filter((pr) => pr.headRefName?.startsWith("codex/"))
    .filter((pr) => pr.headRepositoryOwner?.login === repo.split("/")[0])
    .filter((pr) => new Date(pr.updatedAt) < cutoff)
    .map((pr) => pr.headRefName);

  const existingBranches = new Set(
    gh(["api", `repos/${repo}/branches`, "--paginate", "--jq", ".[].name"])
      .trim()
      .split("\n")
      .filter((branch) => branch.startsWith("codex/")),
  );

  const deleteCandidates = [...new Set(closedBranches)]
    .filter((branch) => existingBranches.has(branch))
    .filter((branch) => !openBranches.has(branch));

  if (deleteCandidates.length === 0) {
    console.log("merged/closed codex branches: none");
  } else {
    for (const branch of deleteCandidates) {
      action(`delete branch ${repo}:${branch}`, () =>
        gh(["api", "-X", "DELETE", `repos/${repo}/git/refs/heads/${branch}`]),
      );
    }
  }
}

async function inspectLinear() {
  console.log("\n== Linear stale canaries ==");
  const key = process.env.LINEAR_API_KEY;
  if (!key) {
    console.log("skipped: LINEAR_API_KEY is not set");
    return;
  }

  const canceledState = await linear(
    `query {
      workflowStates(filter: { team: { key: { eq: "BEC" } }, name: { in: ["Canceled", "Cancelled"] } }, first: 5) {
        nodes { id name }
      }
    }`,
  );
  const stateId = canceledState.data?.workflowStates?.nodes?.[0]?.id;
  if (!stateId) {
    console.log("skipped: no Canceled/Cancelled BEC workflow state found");
    return;
  }

  const response = await linear(
    `query($before: DateTimeOrDuration!) {
      issues(
        filter: {
          team: { key: { eq: "BEC" } }
          labels: { name: { eq: "symphony" } }
          updatedAt: { lt: $before }
          state: { name: { nin: ["Done", "Closed", "Canceled", "Cancelled", "Duplicate"] } }
        }
        first: 50
      ) {
        nodes {
          id
          identifier
          title
          url
          updatedAt
          state { name }
          labels { nodes { name } }
        }
      }
    }`,
    { before: cutoff.toISOString() },
  );

  const issues = response.data?.issues?.nodes ?? [];
  const canaries = issues.filter((issue) => {
    const labels = issue.labels?.nodes?.map((label) => label.name).join(" ") ?? "";
    return `${issue.title} ${labels}`.toLowerCase().includes("canary");
  });

  if (canaries.length === 0) {
    console.log("stale Linear canaries: none");
    return;
  }

  for (const issue of canaries) {
    await action(`cancel Linear canary ${issue.identifier} (${issue.state.name}) ${issue.url}`, async () => {
      await linear(
        `mutation($id: String!, $body: String!) {
          commentCreate(input: { issueId: $id, body: $body }) { success }
        }`,
        { id: issue.id, body: "Cancelling stale Symphony canary via janitor." },
      );
      await linear(
        `mutation($id: String!, $stateId: String!) {
          issueUpdate(id: $id, input: { stateId: $stateId }) { success }
        }`,
        { id: issue.id, stateId },
      );
    });
  }
}

function inspectLanes() {
  console.log("\n== Local Symphony lanes ==");
  const output = sh("pgrep", ["-fl", "symphony"], { allowFailure: true });
  const running = output
    .trim()
    .split("\n")
    .filter(Boolean)
    .filter((line) => /elixir\/workflows\/.+\.md/.test(line));
  if (running.length === 0) {
    console.log("running lanes: none observed");
  } else {
    for (const line of running) console.log(line);
  }
}

async function action(label, fn) {
  if (!apply) {
    console.log(`would: ${label}`);
    return;
  }
  const result = fn();
  if (result && typeof result.then === "function") {
    await result;
    console.log(`done: ${label}`);
    return;
  }
  console.log(`done: ${label}`);
}

async function linear(query, variables = {}) {
  const response = await fetch("https://api.linear.app/graphql", {
    method: "POST",
    headers: {
      Authorization: process.env.LINEAR_API_KEY,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ query, variables }),
  });
  const payload = await response.json();
  if (!response.ok || payload.errors) {
    throw new Error(`Linear API failed: ${JSON.stringify(payload.errors ?? payload)}`);
  }
  return payload;
}

function jsonGh(args) {
  const output = gh(args);
  return output.trim() ? JSON.parse(output) : [];
}

function gh(args) {
  return sh("gh", args);
}

function sh(command, args, opts = {}) {
  try {
    return execFileSync(command, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  } catch (error) {
    if (opts.allowFailure) return `${error.stdout ?? ""}${error.stderr ?? ""}`;
    throw error;
  }
}

function valueArg(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : null;
}

function numberArg(name, fallback) {
  const value = Number(valueArg(name));
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
