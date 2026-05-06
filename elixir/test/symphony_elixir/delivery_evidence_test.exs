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
      assert DeliveryEvidence.failure_bucket({:evidence_gate_failed, report.failures}) == :missing_workpad
      assert "missing draft pull request" in report.failures
      assert "missing deployment/check evidence" in report.failures
    after
      File.rm_rf(test_root)
    end
  end

  test "evidence evaluator trusts fresh publisher validation when Linear comments are stale" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-evidence-publisher-#{System.unique_integer([:positive])}"
      )

    try do
      {workspace, sha} = committed_workspace!(test_root, "codex/BEC-44-marker")

      write_workflow_file!(Workflow.workflow_file_path(),
        repo_github_repo: "Subconscious-ai/example",
        validation_deploy_evidence: "github_checks",
        validation_evidence_required: true,
        evidence_gate_github_required_checks: ["symphony-gate"]
      )

      issue = %Issue{
        id: "issue-publisher",
        identifier: "BEC-44",
        title: "Publisher evidence",
        state: "In Progress"
      }

      stale_comments = [
        """
        ## Codex Workpad

        Validation: blocked before complete publication
        """
      ]

      pull_request = %{
        "url" => "https://github.com/Subconscious-ai/example/pull/44",
        "isDraft" => true,
        "headRefOid" => sha,
        "title" => "BEC-44 publisher delivery",
        "body" => "Refs BEC-44",
        "labels" => [%{"name" => "symphony"}],
        "statusCheckRollup" => [
          %{
            "__typename" => "CheckRun",
            "name" => "symphony-gate",
            "status" => "COMPLETED",
            "conclusion" => "SUCCESS",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/44/job/1"
          }
        ]
      }

      publisher_evidence = %{
        branch: "codex/BEC-44-marker",
        commit_sha: sha,
        pr_url: "https://github.com/Subconscious-ai/example/pull/44",
        deployment_url: "https://github.com/Subconscious-ai/example/actions/runs/44/job/1",
        validation_command: "bash scripts/agent/validate-fast.sh",
        validation_output: "agent readiness: ok\nall tests passed"
      }

      assert {:ok, evidence} =
               DeliveryEvidence.evaluate(issue, workspace,
                 comments: stale_comments,
                 pull_request: pull_request,
                 publisher_evidence: publisher_evidence
               )

      assert evidence.workpad =~ "Validation: `bash scripts/agent/validate-fast.sh` -> pass"
      assert evidence.deployment_url == "https://github.com/Subconscious-ai/example/actions/runs/44/job/1"
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
      assert DeliveryEvidence.failure_bucket({:evidence_gate_failed, failed_report.failures}) == :ci_failed
    after
      File.rm_rf(test_root)
    end
  end

  test "evidence evaluator prefers final workpad with passing validation over stale setup workpad" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-evidence-final-workpad-#{System.unique_integer([:positive])}"
      )

    try do
      {workspace, sha} = committed_workspace!(test_root, "codex/BEC-47-marker")

      write_workflow_file!(Workflow.workflow_file_path(),
        repo_github_repo: "Subconscious-ai/example",
        validation_deploy_evidence: "github_checks",
        validation_evidence_required: true,
        evidence_gate_github_required_checks: ["symphony-gate"]
      )

      issue = %Issue{
        id: "issue-final-workpad",
        identifier: "BEC-47",
        title: "Final workpad gate",
        state: "In Progress"
      }

      setup_workpad = """
      ## Codex Workpad

      Validation result: failing by design before repair.
      PR: https://github.com/Subconscious-ai/example/pull/47
      """

      final_workpad = """
      ## Codex Workpad

      Validation: bash scripts/agent/validate-fast.sh passed
      PR: https://github.com/Subconscious-ai/example/pull/47
      Check: https://github.com/Subconscious-ai/example/actions/runs/47/job/1
      """

      pull_request = %{
        "url" => "https://github.com/Subconscious-ai/example/pull/47",
        "isDraft" => true,
        "headRefOid" => sha,
        "title" => "BEC-47 final workpad gate",
        "body" => "Refs BEC-47",
        "labels" => [%{"name" => "symphony"}],
        "statusCheckRollup" => [
          %{
            "__typename" => "CheckRun",
            "name" => "symphony-gate",
            "status" => "COMPLETED",
            "conclusion" => "SUCCESS",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/47/job/1"
          }
        ]
      }

      assert {:ok, evidence} =
               DeliveryEvidence.evaluate(issue, workspace,
                 comments: [setup_workpad, final_workpad],
                 pull_request: pull_request
               )

      assert evidence.workpad == final_workpad
    after
      File.rm_rf(test_root)
    end
  end

  test "evidence evaluator only requires configured PR checks when present" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-evidence-configured-check-#{System.unique_integer([:positive])}"
      )

    try do
      {workspace, sha} = committed_workspace!(test_root, "codex/BEC-48-marker")

      write_workflow_file!(Workflow.workflow_file_path(),
        repo_github_repo: "Subconscious-ai/example",
        validation_deploy_evidence: "github_checks",
        validation_evidence_required: true,
        evidence_gate_github_required_checks: ["symphony-gate"]
      )

      issue = %Issue{
        id: "issue-configured-check",
        identifier: "BEC-48",
        title: "Configured check gate",
        state: "In Progress"
      }

      workpad = """
      ## Codex Workpad

      Validation: bash scripts/agent/validate-fast.sh passed
      PR: https://github.com/Subconscious-ai/example/pull/48
      Check: https://github.com/Subconscious-ai/example/actions/runs/48/job/1
      """

      pull_request = %{
        "url" => "https://github.com/Subconscious-ai/example/pull/48",
        "isDraft" => true,
        "headRefOid" => sha,
        "title" => "BEC-48 configured check gate",
        "body" => "Refs BEC-48",
        "labels" => [%{"name" => "symphony"}],
        "statusCheckRollup" => [
          %{
            "__typename" => "CheckRun",
            "name" => "symphony-gate",
            "status" => "COMPLETED",
            "conclusion" => "SUCCESS",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/48/job/1"
          },
          %{
            "__typename" => "CheckRun",
            "name" => "legacy-e2e",
            "status" => "COMPLETED",
            "conclusion" => "FAILURE",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/48/job/2"
          }
        ]
      }

      assert {:ok, evidence} =
               DeliveryEvidence.evaluate(issue, workspace,
                 comments: [workpad],
                 pull_request: pull_request
               )

      assert evidence.deployment_url == "https://github.com/Subconscious-ai/example/actions/runs/48/job/1"
    after
      File.rm_rf(test_root)
    end
  end

  test "evidence evaluator requires every non-optional check when configured" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-evidence-all-checks-#{System.unique_integer([:positive])}"
      )

    try do
      {workspace, sha} = committed_workspace!(test_root, "codex/BEC-54-marker")

      write_workflow_file!(Workflow.workflow_file_path(),
        repo_github_repo: "Subconscious-ai/example",
        validation_deploy_evidence: "github_checks",
        validation_evidence_required: true,
        evidence_gate_github_required_checks: ["symphony-gate"],
        evidence_gate_github_optional_checks: ["CodeRabbit"],
        evidence_gate_require_all_checks: true
      )

      issue = %Issue{
        id: "issue-all-checks",
        identifier: "BEC-54",
        title: "All checks gate",
        state: "In Progress"
      }

      workpad = """
      ## Codex Workpad

      Validation: bash scripts/agent/validate-fast.sh passed
      PR: https://github.com/Subconscious-ai/example/pull/54
      Check: https://github.com/Subconscious-ai/example/actions/runs/54/job/1
      """

      base_pr = %{
        "url" => "https://github.com/Subconscious-ai/example/pull/54",
        "isDraft" => true,
        "headRefOid" => sha,
        "title" => "BEC-54 all checks gate",
        "body" => "Refs BEC-54",
        "labels" => [%{"name" => "symphony"}]
      }

      pending_codeql =
        Map.put(base_pr, "statusCheckRollup", [
          %{
            "__typename" => "CheckRun",
            "name" => "symphony-gate",
            "status" => "COMPLETED",
            "conclusion" => "SUCCESS",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/54/job/1"
          },
          %{
            "__typename" => "CheckRun",
            "name" => "Analyze (python)",
            "status" => "IN_PROGRESS",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/54/job/2"
          },
          %{
            "__typename" => "StatusContext",
            "context" => "CodeRabbit",
            "state" => "PENDING"
          }
        ])

      assert {:error, pending_report} =
               DeliveryEvidence.evaluate(issue, workspace,
                 comments: [workpad],
                 pull_request: pending_codeql
               )

      assert "required PR check still pending: Analyze (python)" in pending_report.failures
      refute Enum.any?(pending_report.failures, &String.contains?(&1, "CodeRabbit"))

      failed_codeql =
        put_in(
          pending_codeql,
          ["statusCheckRollup", Access.at(1)],
          %{
            "__typename" => "CheckRun",
            "name" => "Analyze (python)",
            "status" => "COMPLETED",
            "conclusion" => "FAILURE",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/54/job/2"
          }
        )

      assert {:error, failed_report} =
               DeliveryEvidence.evaluate(issue, workspace,
                 comments: [workpad],
                 pull_request: failed_codeql
               )

      assert "required PR check failed: Analyze (python)" in failed_report.failures

      complete_pr =
        put_in(
          pending_codeql,
          ["statusCheckRollup", Access.at(1)],
          %{
            "__typename" => "CheckRun",
            "name" => "Analyze (python)",
            "status" => "COMPLETED",
            "conclusion" => "SUCCESS",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/54/job/2"
          }
        )

      assert {:ok, evidence} =
               DeliveryEvidence.evaluate(issue, workspace,
                 comments: [workpad],
                 pull_request: complete_pr
               )

      assert evidence.deployment_url == "https://github.com/Subconscious-ai/example/actions/runs/54/job/1"
    after
      File.rm_rf(test_root)
    end
  end

  test "evidence evaluator blocks merge-conflicting pull requests" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-evidence-merge-conflict-#{System.unique_integer([:positive])}"
      )

    try do
      {workspace, sha} = committed_workspace!(test_root, "codex/BEC-55-marker")

      write_workflow_file!(Workflow.workflow_file_path(),
        repo_github_repo: "Subconscious-ai/example",
        validation_deploy_evidence: "github_checks",
        validation_evidence_required: true,
        evidence_gate_github_required_checks: ["symphony-gate"],
        evidence_gate_require_all_checks: true
      )

      issue = %Issue{
        id: "issue-merge-conflict",
        identifier: "BEC-55",
        title: "Merge conflict gate",
        state: "In Progress"
      }

      workpad = """
      ## Codex Workpad

      Validation: bash scripts/agent/validate-fast.sh passed
      PR: https://github.com/Subconscious-ai/example/pull/55
      Check: https://github.com/Subconscious-ai/example/actions/runs/55/job/1
      """

      pull_request = %{
        "url" => "https://github.com/Subconscious-ai/example/pull/55",
        "isDraft" => true,
        "headRefOid" => sha,
        "title" => "BEC-55 merge conflict gate",
        "body" => "Refs BEC-55",
        "mergeable" => "CONFLICTING",
        "labels" => [%{"name" => "symphony"}],
        "statusCheckRollup" => [
          %{
            "__typename" => "CheckRun",
            "name" => "symphony-gate",
            "status" => "COMPLETED",
            "conclusion" => "SUCCESS",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/55/job/1"
          }
        ]
      }

      assert {:error, report} =
               DeliveryEvidence.evaluate(issue, workspace,
                 comments: [workpad],
                 pull_request: pull_request
               )

      assert "pull request has merge conflicts" in report.failures
      assert DeliveryEvidence.failure_bucket({:evidence_gate_failed, report.failures}) == :merge_conflict
    after
      File.rm_rf(test_root)
    end
  end

  test "evidence evaluator does not treat Linear issue URLs as check evidence" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-evidence-linear-url-#{System.unique_integer([:positive])}"
      )

    try do
      {workspace, sha} = committed_workspace!(test_root, "codex/BEC-53-marker")

      write_workflow_file!(Workflow.workflow_file_path(),
        repo_github_repo: "Subconscious-ai/example",
        validation_deploy_evidence: "github_checks",
        validation_evidence_required: true,
        evidence_gate_github_required_checks: ["symphony-gate"]
      )

      issue = %Issue{
        id: "issue-linear-url",
        identifier: "BEC-53",
        title: "Checker telemetry",
        state: "In Progress"
      }

      workpad = """
      ## Codex Workpad

      Linear: https://linear.app/subconscious/issue/BEC-53/symphony-level-11-verify-merged-checker-telemetry-trace
      Validation: bash scripts/agent/validate-fast.sh passed
      PR: https://github.com/Subconscious-ai/example/pull/53
      """

      pull_request = %{
        "url" => "https://github.com/Subconscious-ai/example/pull/53",
        "isDraft" => true,
        "headRefOid" => sha,
        "title" => "BEC-53 checker telemetry",
        "body" => "Refs BEC-53",
        "labels" => [%{"name" => "symphony"}],
        "statusCheckRollup" => [
          %{
            "__typename" => "CheckRun",
            "name" => "Analyze (actions)",
            "status" => "IN_PROGRESS",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/53/job/1"
          },
          %{
            "__typename" => "CheckRun",
            "name" => "symphony-gate",
            "status" => "COMPLETED",
            "conclusion" => "SUCCESS",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/53/job/2"
          }
        ]
      }

      assert {:ok, evidence} =
               DeliveryEvidence.evaluate(issue, workspace,
                 comments: [workpad],
                 pull_request: pull_request
               )

      assert evidence.deployment_url == "https://github.com/Subconscious-ai/example/actions/runs/53/job/2"
    after
      File.rm_rf(test_root)
    end
  end

  test "evidence evaluator requires configured CI check evidence even without deploy previews" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-evidence-ci-only-#{System.unique_integer([:positive])}"
      )

    try do
      {workspace, sha} = committed_workspace!(test_root, "codex/BEC-49-marker")

      write_workflow_file!(Workflow.workflow_file_path(),
        repo_github_repo: "Subconscious-ai/example",
        validation_deploy_evidence: "none",
        validation_evidence_required: true,
        evidence_gate_github_required_checks: ["symphony-gate"]
      )

      issue = %Issue{
        id: "issue-ci-only",
        identifier: "BEC-49",
        title: "CI only gate",
        state: "In Progress"
      }

      workpad = """
      ## Codex Workpad

      Validation: bash scripts/agent/validate-fast.sh passed
      PR: https://github.com/Subconscious-ai/example/pull/49
      """

      base_pr = %{
        "url" => "https://github.com/Subconscious-ai/example/pull/49",
        "isDraft" => true,
        "headRefOid" => sha,
        "title" => "BEC-49 ci only gate",
        "body" => "Refs BEC-49",
        "labels" => [%{"name" => "symphony"}]
      }

      missing_check_url =
        Map.put(base_pr, "statusCheckRollup", [
          %{
            "__typename" => "CheckRun",
            "name" => "symphony-gate",
            "status" => "COMPLETED",
            "conclusion" => "SUCCESS"
          }
        ])

      assert {:error, missing_url_report} =
               DeliveryEvidence.evaluate(issue, workspace,
                 comments: [workpad],
                 pull_request: missing_check_url
               )

      assert "missing deployment/check evidence" in missing_url_report.failures

      complete_pr =
        put_in(
          missing_check_url,
          ["statusCheckRollup", Access.at(0), "detailsUrl"],
          "https://github.com/Subconscious-ai/example/actions/runs/49/job/1"
        )

      assert {:ok, evidence} =
               DeliveryEvidence.evaluate(issue, workspace,
                 comments: [workpad],
                 pull_request: complete_pr
               )

      assert evidence.deployment_url == "https://github.com/Subconscious-ai/example/actions/runs/49/job/1"
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
      assert pass_comment =~ "### Measurement"
      assert pass_comment =~ "- PR URL: https://github.com/Subconscious-ai/example/pull/44"
      assert pass_comment =~ "- Check/Deploy URL: n/a"
      assert pass_comment =~ "- Failure bucket: none"
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
      assert block_comment =~ "Failure bucket: missing_workpad"
      assert_receive {:memory_tracker_state_update, "issue-finalize-blocked", "Rework"}, 500
    after
      File.rm_rf(test_root)
    end
  end

  test "failure buckets are stable for common evidence failures" do
    cases = [
      {["missing Linear workpad comment headed ## Codex Workpad"], :missing_workpad},
      {["branch does not start with codex/BEC-1"], :branch_mismatch},
      {["missing final commit SHA"], :missing_pushed_sha},
      {["missing draft pull request"], :missing_pr},
      {["pull request is missing symphony label"], :missing_label},
      {["missing validation command/result evidence"], :missing_validation},
      {["missing deployment/check evidence"], :missing_deploy_evidence},
      {["pull request has merge conflicts"], :merge_conflict},
      {["required PR check failed: symphony-gate"], :ci_failed},
      {["required PR check still pending: symphony-gate"], :ci_pending},
      {["pull request head commit does not match workspace HEAD"], :pushed_sha_mismatch}
    ]

    for {failures, bucket} <- cases do
      assert DeliveryEvidence.failure_bucket({:evidence_gate_failed, failures}) == bucket
    end
  end

  test "finalize_issue does not duplicate an existing Symphony evidence gate comment on resume" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-finalize-resume-#{System.unique_integer([:positive])}"
      )

    try do
      {workspace, sha} = committed_workspace!(test_root, "codex/BEC-50-marker")

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        validation_evidence_required: true
      )

      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      Application.put_env(:symphony_elixir, :memory_tracker_comments, %{
        "issue-finalize-resume" => ["## Symphony Evidence Gate\n\nResult: passed"]
      })

      issue = %Issue{
        id: "issue-finalize-resume",
        identifier: "BEC-50",
        title: "Finalize resume delivery",
        state: "In Progress"
      }

      workpad = """
      ## Codex Workpad

      Validation: mix test passed
      PR: https://github.com/Subconscious-ai/example/pull/50
      """

      pull_request = %{
        "url" => "https://github.com/Subconscious-ai/example/pull/50",
        "isDraft" => true,
        "headRefOid" => sha,
        "title" => "BEC-50 finalization",
        "body" => "Refs BEC-50",
        "labels" => [%{"name" => "symphony"}]
      }

      assert :ok =
               DeliveryEvidence.finalize_issue(issue, workspace,
                 comments: [workpad],
                 pull_request: pull_request
               )

      refute_receive {:memory_tracker_comment, "issue-finalize-resume", _body}, 100
      assert_receive {:memory_tracker_state_update, "issue-finalize-resume", "Human Review"}, 500
    after
      Application.delete_env(:symphony_elixir, :memory_tracker_comments)
      File.rm_rf(test_root)
    end
  end

  test "finalize_issue waits for pending required checks before routing to Rework" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-finalize-wait-#{System.unique_integer([:positive])}"
      )

    old_timeout = Application.get_env(:symphony_elixir, :delivery_evidence_poll_timeout_ms)
    old_interval = Application.get_env(:symphony_elixir, :delivery_evidence_poll_interval_ms)

    try do
      Application.put_env(:symphony_elixir, :delivery_evidence_poll_timeout_ms, 500)
      Application.put_env(:symphony_elixir, :delivery_evidence_poll_interval_ms, 1)

      {workspace, sha} = committed_workspace!(test_root, "codex/BEC-51-marker")

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        validation_deploy_evidence: "github_checks",
        validation_evidence_required: true,
        evidence_gate_github_required_checks: ["symphony-gate"],
        evidence_gate_require_all_checks: true
      )

      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      issue = %Issue{
        id: "issue-finalize-wait",
        identifier: "BEC-51",
        title: "Finalize wait delivery",
        state: "In Progress"
      }

      workpad = """
      ## Codex Workpad

      Validation: mix test passed
      PR: https://github.com/Subconscious-ai/example/pull/51
      Check: https://github.com/Subconscious-ai/example/actions/runs/51/job/1
      """

      base_pr = %{
        "url" => "https://github.com/Subconscious-ai/example/pull/51",
        "isDraft" => true,
        "headRefOid" => sha,
        "title" => "BEC-51 finalization",
        "body" => "Refs BEC-51",
        "labels" => [%{"name" => "symphony"}]
      }

      {:ok, counter} = Agent.start_link(fn -> 0 end)

      pull_request_fetcher = fn ->
        count = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})

        symphony_gate_status =
          if count == 1 do
            %{"status" => "COMPLETED", "conclusion" => "SUCCESS"}
          else
            %{"status" => "COMPLETED", "conclusion" => "SUCCESS"}
          end

        Map.put(base_pr, "statusCheckRollup", [
          Map.merge(
            %{
              "__typename" => "CheckRun",
              "name" => "symphony-gate",
              "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/51/job/1"
            },
            symphony_gate_status
          ),
          if(count == 1,
            do: %{
              "__typename" => "CheckRun",
              "name" => "Analyze (python)",
              "status" => "IN_PROGRESS",
              "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/51/job/2"
            },
            else: %{
              "__typename" => "CheckRun",
              "name" => "Analyze (python)",
              "status" => "COMPLETED",
              "conclusion" => "SUCCESS",
              "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/51/job/2"
            }
          ),
          if(count == 1,
            do: %{"__typename" => "StatusContext", "context" => "CodeQL", "state" => "FAILURE"},
            else: %{"__typename" => "StatusContext", "context" => "CodeQL", "state" => "SUCCESS"}
          )
        ])
      end

      assert :ok =
               DeliveryEvidence.finalize_issue(issue, workspace,
                 comments: [workpad],
                 pull_request_fetcher: pull_request_fetcher
               )

      assert Agent.get(counter, & &1) >= 2
      assert_receive {:memory_tracker_comment, "issue-finalize-wait", pass_comment}, 500
      assert pass_comment =~ "Result: passed"
      assert_receive {:memory_tracker_state_update, "issue-finalize-wait", "Human Review"}, 500
    after
      restore_app_env(:delivery_evidence_poll_timeout_ms, old_timeout)
      restore_app_env(:delivery_evidence_poll_interval_ms, old_interval)
      File.rm_rf(test_root)
    end
  end

  test "finalize_issue uses workflow evidence timeout instead of the short app default" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-finalize-workflow-timeout-#{System.unique_integer([:positive])}"
      )

    old_timeout = Application.get_env(:symphony_elixir, :delivery_evidence_poll_timeout_ms)
    old_interval = Application.get_env(:symphony_elixir, :delivery_evidence_poll_interval_ms)

    try do
      Application.put_env(:symphony_elixir, :delivery_evidence_poll_timeout_ms, 0)
      Application.put_env(:symphony_elixir, :delivery_evidence_poll_interval_ms, 1)

      {workspace, sha} = committed_workspace!(test_root, "codex/BEC-52-marker")

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        validation_deploy_evidence: "github_checks",
        validation_evidence_required: true,
        evidence_gate_github_required_checks: ["symphony-gate"],
        evidence_gate_require_all_checks: true,
        evidence_gate_timeout_seconds: 1
      )

      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      issue = %Issue{
        id: "issue-finalize-workflow-timeout",
        identifier: "BEC-52",
        title: "Finalize workflow timeout",
        state: "In Progress"
      }

      workpad = """
      ## Codex Workpad

      Validation: mix test passed
      PR: https://github.com/Subconscious-ai/example/pull/52
      Check: https://github.com/Subconscious-ai/example/actions/runs/52/job/1
      """

      base_pr = %{
        "url" => "https://github.com/Subconscious-ai/example/pull/52",
        "isDraft" => true,
        "headRefOid" => sha,
        "title" => "BEC-52 finalization",
        "body" => "Refs BEC-52",
        "labels" => [%{"name" => "symphony"}]
      }

      {:ok, counter} = Agent.start_link(fn -> 0 end)

      pull_request_fetcher = fn ->
        count = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})

        check =
          if count == 1 do
            %{
              "__typename" => "CheckRun",
              "name" => "symphony-gate",
              "status" => "IN_PROGRESS",
              "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/52/job/1"
            }
          else
            %{
              "__typename" => "CheckRun",
              "name" => "symphony-gate",
              "status" => "COMPLETED",
              "conclusion" => "SUCCESS",
              "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/52/job/1"
            }
          end

        Map.put(base_pr, "statusCheckRollup", [check])
      end

      assert :ok =
               DeliveryEvidence.finalize_issue(issue, workspace,
                 comments: [workpad],
                 pull_request_fetcher: pull_request_fetcher
               )

      assert Agent.get(counter, & &1) >= 2
      assert_receive {:memory_tracker_state_update, "issue-finalize-workflow-timeout", "Human Review"}, 500
    after
      restore_app_env(:delivery_evidence_poll_timeout_ms, old_timeout)
      restore_app_env(:delivery_evidence_poll_interval_ms, old_interval)
      File.rm_rf(test_root)
    end
  end

  test "finalize_issue_with_report returns auditable checker telemetry and comments required checks" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-finalize-report-#{System.unique_integer([:positive])}"
      )

    try do
      {workspace, sha} = committed_workspace!(test_root, "codex/BEC-52-marker")

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        validation_deploy_evidence: "github_checks",
        validation_evidence_required: true,
        evidence_gate_github_required_checks: ["symphony-gate", "static-checks"]
      )

      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      issue = %Issue{
        id: "issue-finalize-report",
        identifier: "BEC-52",
        title: "Finalize report delivery",
        state: "In Progress"
      }

      workpad = """
      ## Codex Workpad

      Validation: bash scripts/agent/validate-fast.sh passed
      PR: https://github.com/Subconscious-ai/example/pull/52
      Check: https://github.com/Subconscious-ai/example/actions/runs/52/job/1
      """

      pull_request = %{
        "url" => "https://github.com/Subconscious-ai/example/pull/52",
        "isDraft" => true,
        "headRefOid" => sha,
        "title" => "BEC-52 finalization",
        "body" => "Refs BEC-52",
        "labels" => [%{"name" => "symphony"}],
        "statusCheckRollup" => [
          %{
            "__typename" => "CheckRun",
            "name" => "symphony-gate",
            "status" => "COMPLETED",
            "conclusion" => "SUCCESS",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/52/job/1"
          },
          %{
            "__typename" => "CheckRun",
            "name" => "static-checks",
            "status" => "COMPLETED",
            "conclusion" => "SUCCESS",
            "detailsUrl" => "https://github.com/Subconscious-ai/example/actions/runs/52/job/2"
          }
        ]
      }

      assert {:ok, report} =
               DeliveryEvidence.finalize_issue_with_report(issue, workspace,
                 comments: [workpad],
                 pull_request: pull_request
               )

      assert report.checker.passed == true
      assert report.checker.failure_bucket == :none
      assert report.checker.required_checks == ["symphony-gate", "static-checks"]
      assert Enum.map(report.checker.observed_checks, & &1.name) == ["symphony-gate", "static-checks"]
      assert Enum.all?(report.checker.observed_checks, &(&1.state == :success))

      assert_receive {:memory_tracker_comment, "issue-finalize-report", pass_comment}, 500
      assert pass_comment =~ "### Checker"
      assert pass_comment =~ "- Required checks: symphony-gate, static-checks"
      assert pass_comment =~ "- Observed checks:"
      assert pass_comment =~ "symphony-gate: success"
      assert pass_comment =~ "static-checks: success"
      assert_receive {:memory_tracker_state_update, "issue-finalize-report", "Human Review"}, 500
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

  defp restore_app_env(key, nil), do: Application.delete_env(:symphony_elixir, key)
  defp restore_app_env(key, value), do: Application.put_env(:symphony_elixir, key, value)
end
