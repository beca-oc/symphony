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
          %{"targetUrl" => "https://vercel.com/subconcious/example/abc123"}
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
end
