defmodule SymphonyElixir.DeliveryEvidenceTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.DeliveryEvidence

  test "evidence evaluator accepts a complete draft PR delivery packet" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-evidence-#{System.unique_integer([:positive])}"
      )

    try do
      workspace = Path.join(test_root, "workspace")
      File.mkdir_p!(workspace)
      File.write!(Path.join(workspace, "README.md"), "# complete\n")
      System.cmd("git", ["-C", workspace, "init", "-b", "codex/BEC-42-marker"])
      System.cmd("git", ["-C", workspace, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", workspace, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", workspace, "add", "README.md"])
      System.cmd("git", ["-C", workspace, "commit", "-m", "complete evidence"])

      {sha, 0} = System.cmd("git", ["-C", workspace, "rev-parse", "HEAD"])
      sha = String.trim(sha)

      write_workflow_file!(Workflow.workflow_file_path(),
        repo_github_repo: "Subconscious-ai/example",
        validation_deploy_evidence: "vercel",
        validation_evidence_required: true
      )

      issue = %Issue{
        id: "issue-complete",
        identifier: "BEC-42",
        title: "Complete delivery",
        state: "In Progress"
      }

      comments = [
        """
        ## Codex Workpad

        Branch: codex/BEC-42-marker
        Commit: #{sha}
        Validation: pnpm ci:quick passed
        PR: https://github.com/Subconscious-ai/example/pull/12
        Deployment: https://vercel.com/subconcious/example/abc123
        """
      ]

      pull_request = %{
        "url" => "https://github.com/Subconscious-ai/example/pull/12",
        "isDraft" => true,
        "headRefOid" => sha,
        "title" => "BEC-42 complete delivery",
        "body" => "Refs BEC-42",
        "labels" => [%{"name" => "symphony"}],
        "statusCheckRollup" => [
          %{
            "__typename" => "StatusContext",
            "context" => "Vercel",
            "state" => "SUCCESS",
            "targetUrl" => "https://vercel.com/subconcious/example/abc123"
          }
        ]
      }

      assert {:ok, evidence} =
               DeliveryEvidence.evaluate(issue, workspace,
                 comments: comments,
                 pull_request: pull_request
               )

      assert evidence.branch == "codex/BEC-42-marker"
      assert evidence.commit_sha == sha
      assert evidence.pr_url == "https://github.com/Subconscious-ai/example/pull/12"
      assert evidence.deployment_url == "https://vercel.com/subconcious/example/abc123"
    after
      File.rm_rf(test_root)
    end
  end

  test "evidence evaluator reports missing workpad, PR, and deploy evidence" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-evidence-missing-#{System.unique_integer([:positive])}"
      )

    try do
      workspace = Path.join(test_root, "workspace")
      File.mkdir_p!(workspace)
      File.write!(Path.join(workspace, "README.md"), "# incomplete\n")
      System.cmd("git", ["-C", workspace, "init", "-b", "codex/BEC-43-marker"])
      System.cmd("git", ["-C", workspace, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", workspace, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", workspace, "add", "README.md"])
      System.cmd("git", ["-C", workspace, "commit", "-m", "incomplete evidence"])

      write_workflow_file!(Workflow.workflow_file_path(),
        repo_github_repo: "Subconscious-ai/example",
        validation_deploy_evidence: "vercel",
        validation_evidence_required: true
      )

      issue = %Issue{
        id: "issue-incomplete",
        identifier: "BEC-43",
        title: "Incomplete delivery",
        state: "In Progress"
      }

      assert {:error, report} =
               DeliveryEvidence.evaluate(issue, workspace,
                 comments: ["No workpad yet"],
                 pull_request: nil
               )

      assert "missing Linear workpad comment headed ## Codex Workpad" in report.failures
      assert "missing draft pull request" in report.failures
      assert "missing deployment/check evidence" in report.failures
    after
      File.rm_rf(test_root)
    end
  end

  test "evidence evaluator blocks pending and failed required PR checks" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-evidence-check-state-#{System.unique_integer([:positive])}"
      )

    try do
      {workspace, sha} = committed_workspace!(test_root, "codex/BEC-46-marker")

      write_workflow_file!(Workflow.workflow_file_path(),
        repo_github_repo: "Subconscious-ai/example",
        validation_deploy_evidence: "github_checks",
        validation_evidence_required: true
      )

      issue = %Issue{
        id: "issue-check-state",
        identifier: "BEC-46",
        title: "Check state gate",
        state: "In Progress"
      }

      workpad = """
      ## Codex Workpad

      Validation: bash scripts/agent/validate-fast.sh passed
      PR: https://github.com/Subconscious-ai/example/pull/46
      Check: https://github.com/Subconscious-ai/example/actions/runs/46/job/1
      """

      base_pr = %{
        "url" => "https://github.com/Subconscious-ai/example/pull/46",
        "isDraft" => true,
        "headRefOid" => sha,
        "title" => "BEC-46 check state gate",
        "body" => "Refs BEC-46",
        "labels" => [%{"name" => "symphony"}]
      }

      pending_pr =
        Map.put(base_pr, "statusCheckRollup", [
          %{
            "__typename" => "CheckRun",
            "name" => "Run static checks",
            "status" => "IN_PROGRESS",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/46/job/1"
          }
        ])

      assert {:error, pending_report} =
               DeliveryEvidence.evaluate(issue, workspace,
                 comments: [workpad],
                 pull_request: pending_pr
               )

      assert "required PR check still pending: Run static checks" in pending_report.failures

      failed_pr =
        Map.put(base_pr, "statusCheckRollup", [
          %{
            "__typename" => "CheckRun",
            "name" => "review",
            "status" => "COMPLETED",
            "conclusion" => "FAILURE",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/46/job/2"
          }
        ])

      assert {:error, failed_report} =
               DeliveryEvidence.evaluate(issue, workspace,
                 comments: [workpad],
                 pull_request: failed_pr
               )

      assert "required PR check failed: review" in failed_report.failures
    after
      File.rm_rf(test_root)
    end
  end

  test "evidence evaluator allows explicitly configured skipped checks" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-evidence-skipped-check-#{System.unique_integer([:positive])}"
      )

    try do
      {workspace, sha} = committed_workspace!(test_root, "codex/BEC-47-marker")

      write_workflow_file!(Workflow.workflow_file_path(),
        repo_github_repo: "Subconscious-ai/example",
        validation_deploy_evidence: "github_checks",
        validation_evidence_required: true,
        evidence_gate_allow_skipped_checks: ["Run Storybook"]
      )

      issue = %Issue{
        id: "issue-skipped-check",
        identifier: "BEC-47",
        title: "Skipped check gate",
        state: "In Progress"
      }

      workpad = """
      ## Codex Workpad

      Validation: bash scripts/agent/validate-fast.sh passed
      PR: https://github.com/Subconscious-ai/example/pull/47
      Check: https://github.com/Subconscious-ai/example/actions/runs/47/job/1
      """

      pull_request = %{
        "url" => "https://github.com/Subconscious-ai/example/pull/47",
        "isDraft" => true,
        "headRefOid" => sha,
        "title" => "BEC-47 skipped check gate",
        "body" => "Refs BEC-47",
        "labels" => [%{"name" => "symphony"}],
        "statusCheckRollup" => [
          %{
            "__typename" => "CheckRun",
            "name" => "Run static checks",
            "status" => "COMPLETED",
            "conclusion" => "SUCCESS",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/47/job/1"
          },
          %{
            "__typename" => "CheckRun",
            "name" => "Run Storybook",
            "status" => "COMPLETED",
            "conclusion" => "SKIPPED",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/47/job/2"
          }
        ]
      }

      assert {:ok, evidence} =
               DeliveryEvidence.evaluate(issue, workspace,
                 comments: [workpad],
                 pull_request: pull_request
               )

      assert evidence.pr_url == "https://github.com/Subconscious-ai/example/pull/47"
    after
      File.rm_rf(test_root)
    end
  end

  test "finalize_issue moves complete deliveries to Human Review and blockers to Rework" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-finalize-#{System.unique_integer([:positive])}"
      )

    try do
      workspace = Path.join(test_root, "workspace")
      File.mkdir_p!(workspace)
      File.write!(Path.join(workspace, "README.md"), "# finalization\n")
      System.cmd("git", ["-C", workspace, "init", "-b", "codex/BEC-44-marker"])
      System.cmd("git", ["-C", workspace, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", workspace, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", workspace, "add", "README.md"])
      System.cmd("git", ["-C", workspace, "commit", "-m", "finalize evidence"])

      {sha, 0} = System.cmd("git", ["-C", workspace, "rev-parse", "HEAD"])
      sha = String.trim(sha)

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        validation_evidence_required: true
      )

      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      issue = %Issue{
        id: "issue-finalize",
        identifier: "BEC-44",
        title: "Finalize delivery",
        state: "In Progress"
      }

      workpad = """
      ## Codex Workpad

      Validation: mix test passed
      PR: https://github.com/Subconscious-ai/example/pull/44
      """

      pull_request = %{
        "url" => "https://github.com/Subconscious-ai/example/pull/44",
        "isDraft" => true,
        "headRefOid" => sha,
        "title" => "BEC-44 finalization",
        "body" => "Refs BEC-44",
        "labels" => [%{"name" => "symphony"}]
      }

      assert :ok =
               DeliveryEvidence.finalize_issue(issue, workspace,
                 comments: [workpad],
                 pull_request: pull_request
               )

      assert_receive {:memory_tracker_comment, "issue-finalize", pass_comment}, 500
      assert pass_comment =~ "## Symphony Evidence Gate"
      assert pass_comment =~ "Result: passed"
      assert_receive {:memory_tracker_state_update, "issue-finalize", "Human Review"}, 500

      incomplete_issue = %{issue | id: "issue-finalize-blocked", identifier: "BEC-45"}

      assert {:error, {:evidence_gate_failed, failures}} =
               DeliveryEvidence.finalize_issue(incomplete_issue, workspace,
                 comments: ["No workpad"],
                 pull_request: nil
               )

      assert "missing Linear workpad comment headed ## Codex Workpad" in failures
      assert_receive {:memory_tracker_comment, "issue-finalize-blocked", block_comment}, 500
      assert block_comment =~ "## Symphony Harness Blocker"
      assert_receive {:memory_tracker_state_update, "issue-finalize-blocked", "Rework"}, 500
    after
      File.rm_rf(test_root)
    end
  end

  defp committed_workspace!(test_root, branch) do
    workspace = Path.join(test_root, "workspace")
    File.mkdir_p!(workspace)
    File.write!(Path.join(workspace, "README.md"), "# evidence\n")
    System.cmd("git", ["-C", workspace, "init", "-b", branch])
    System.cmd("git", ["-C", workspace, "config", "user.name", "Test User"])
    System.cmd("git", ["-C", workspace, "config", "user.email", "test@example.com"])
    System.cmd("git", ["-C", workspace, "add", "README.md"])
    System.cmd("git", ["-C", workspace, "commit", "-m", "evidence"])

    {sha, 0} = System.cmd("git", ["-C", workspace, "rev-parse", "HEAD"])
    {workspace, String.trim(sha)}
  end
end
