defmodule SymphonyElixir.MergeGateTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.MergeGate

  @green_pr %{
    "headRefName" => "codex/BEC-200-normalize-glossary-term",
    "headRefOid" => "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "isDraft" => false,
    "labels" => [%{"name" => "symphony"}],
    "statusCheckRollup" => [
      %{
        "__typename" => "CheckRun",
        "name" => "symphony-gate",
        "status" => "COMPLETED",
        "conclusion" => "SUCCESS",
        "detailsUrl" => "https://github.com/acme/repo/actions/runs/1/job/1"
      },
      %{
        "__typename" => "CheckRun",
        "name" => "CI",
        "status" => "COMPLETED",
        "conclusion" => "SUCCESS",
        "detailsUrl" => "https://github.com/acme/repo/actions/runs/1/job/2"
      }
    ],
    "url" => "https://github.com/acme/repo/pull/12"
  }

  test "merges low-risk approved work when mechanical evidence is complete" do
    issue = merging_issue()
    comments = [evidence_comment()]

    assert {:ok, result} =
             MergeGate.evaluate(issue,
               comments: comments,
               command_runner:
                 fake_gh(%{
                   view: @green_pr,
                   merge: {"Merged pull request #12", 0}
                 })
             )

    assert result.pr_url == "https://github.com/acme/repo/pull/12"
    assert result.head_sha == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    assert result.comment =~ "## Symphony Merge Gate"
    assert result.comment =~ "Result: merged"
  end

  test "draft PR blocks and returns to Human Review" do
    pr = Map.put(@green_pr, "isDraft", true)

    assert {:blocked, result} =
             MergeGate.evaluate(merging_issue(),
               comments: [evidence_comment()],
               command_runner: fake_gh(%{view: pr})
             )

    assert result.state == "Human Review"
    assert result.comment =~ "PR is still draft"
  end

  test "missing PR evidence blocks and returns to Human Review" do
    assert {:blocked, result} =
             MergeGate.evaluate(merging_issue(),
               comments: [String.replace(evidence_comment(), "PR: https://github.com/acme/repo/pull/12", "")],
               command_runner: fake_gh(%{view: @green_pr})
             )

    assert result.state == "Human Review"
    assert result.comment =~ "Missing PR URL"
  end

  test "branch mismatch blocks and returns to Human Review" do
    pr = Map.put(@green_pr, "headRefName", "codex/BEC-999-wrong-branch")

    assert {:blocked, result} =
             MergeGate.evaluate(merging_issue(),
               comments: [evidence_comment()],
               command_runner: fake_gh(%{view: pr})
             )

    assert result.state == "Human Review"
    assert result.comment =~ "PR branch does not match"
  end

  test "missing symphony label blocks and returns to Human Review" do
    pr = Map.put(@green_pr, "labels", [])

    assert {:blocked, result} =
             MergeGate.evaluate(merging_issue(),
               comments: [evidence_comment()],
               command_runner: fake_gh(%{view: pr})
             )

    assert result.state == "Human Review"
    assert result.comment =~ "PR is missing `symphony` label"
  end

  test "stale evidence SHA blocks and returns to Human Review" do
    assert {:blocked, result} =
             MergeGate.evaluate(merging_issue(),
               comments: [
                 String.replace(
                   evidence_comment(),
                   "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                   "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
                 )
               ],
               command_runner: fake_gh(%{view: @green_pr})
             )

    assert result.state == "Human Review"
    assert result.comment =~ "Evidence SHA does not match PR head"
  end

  test "failed checks move the issue to Rework" do
    pr =
      put_in(
        @green_pr,
        ["statusCheckRollup"],
        [
          %{
            "__typename" => "CheckRun",
            "name" => "symphony-gate",
            "status" => "COMPLETED",
            "conclusion" => "SUCCESS"
          },
          %{
            "__typename" => "CheckRun",
            "name" => "CI",
            "status" => "COMPLETED",
            "conclusion" => "FAILURE",
            "detailsUrl" => "https://github.com/acme/repo/actions/runs/1/job/2"
          }
        ]
      )

    assert {:blocked, result} =
             MergeGate.evaluate(merging_issue(),
               comments: [evidence_comment()],
               command_runner: fake_gh(%{view: pr})
             )

    assert result.state == "Rework"
    assert result.comment =~ "CI failed"
  end

  test "missing symphony-gate blocks and returns to Human Review" do
    pr =
      Map.put(@green_pr, "statusCheckRollup", [
        %{
          "__typename" => "CheckRun",
          "name" => "CI",
          "status" => "COMPLETED",
          "conclusion" => "SUCCESS"
        }
      ])

    assert {:blocked, result} =
             MergeGate.evaluate(merging_issue(),
               comments: [evidence_comment()],
               command_runner: fake_gh(%{view: pr})
             )

    assert result.state == "Human Review"
    assert result.comment =~ "`symphony-gate` is missing or not green"
  end

  test "medium-risk work is not auto-merged" do
    issue = %{merging_issue() | description: String.replace(merging_issue().description, "low", "medium")}

    assert {:blocked, result} =
             MergeGate.evaluate(issue,
               comments: [evidence_comment()],
               command_runner: fake_gh(%{view: @green_pr})
             )

    assert result.state == "Human Review"
    assert result.comment =~ "manual merge required"
  end

  test "Vercel evidence requires a review URL and instruction" do
    issue = %{
      merging_issue()
      | description: String.replace(merging_issue().description, "GitHub Actions check.", "Vercel preview URL.")
    }

    assert {:blocked, result} =
             MergeGate.evaluate(issue,
               comments: [evidence_comment()],
               command_runner: fake_gh(%{view: @green_pr})
             )

    assert result.state == "Human Review"
    assert result.comment =~ "Vercel review target is missing"
  end

  test "Vercel evidence with a review target can merge" do
    issue = %{
      merging_issue()
      | description: String.replace(merging_issue().description, "GitHub Actions check.", "Vercel preview URL.")
    }

    assert {:ok, result} =
             MergeGate.evaluate(issue,
               comments: [evidence_comment() <> "\nReview this change: https://subconscious-git-bec-200.vercel.app"],
               command_runner:
                 fake_gh(%{
                   view: @green_pr,
                   merge: {"Merged pull request #12", 0}
                 })
             )

    assert result.comment =~ "Result: merged"
  end

  defp merging_issue do
    %Issue{
      id: "issue-merge",
      identifier: "BEC-200",
      state: "Merging",
      title: "Merge approved work",
      description: """
      ## Goal
      Prove deterministic merging.

      ## Repo
      repo: market-ontology
      base branch: main
      branch rule: codex/BEC-200-normalize-glossary-term

      ## Risk Tier
      low

      ## Scope
      Include: merge approved work.
      Exclude: product behavior.

      ## Acceptance
      Merge only after checks pass.

      ## Validation
      bash scripts/agent/validate-fast.sh

      ## Deploy / Check Evidence
      GitHub Actions check.

      ## Exit Policy
      Human moves to Merging; Symphony moves to Done after merge.
      """
    }
  end

  defp evidence_comment do
    """
    ## Symphony Evidence Gate

    Result: passed
    Branch: codex/BEC-200-normalize-glossary-term
    Commit: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    PR: https://github.com/acme/repo/pull/12
    Deployment/Check: https://github.com/acme/repo/actions/runs/1/job/1
    """
  end

  defp fake_gh(results) do
    fn
      "gh", ["pr", "view", _pr_url, "--json", _fields] ->
        {Jason.encode!(Map.fetch!(results, :view)), 0}

      "gh", ["pr", "merge", _pr_url, "--squash", "--delete-branch"] ->
        Map.get(results, :merge, {"", 0})
    end
  end
end
