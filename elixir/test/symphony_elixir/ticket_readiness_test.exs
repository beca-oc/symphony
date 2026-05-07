defmodule SymphonyElixir.TicketReadinessTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.TicketReadiness

  test "validates the Symphony-ready Linear issue contract" do
    issue = %Issue{
      id: "issue-ready",
      identifier: "BEC-123",
      title: "Ready issue",
      state: "Todo",
      branch_name: "codex/BEC-123-ready-issue",
      description: """
      ## Goal
      Ship the bounded change.

      ## Repo
      repo: causalflow
      base branch: main

      ## Risk Tier
      low

      ## Scope
      Include: update the readiness gate.
      Exclude: unrelated worker behavior.

      ## Acceptance
      The gate rejects malformed tickets.

      ## Validation
      rtk mise exec -- mix test

      ## Deploy / Check Evidence
      GitHub Actions symphony-gate check.

      ## Exit Policy
      Move to Human Review only after evidence passes; otherwise Rework.
      """
    }

    assert :ok = TicketReadiness.validate(issue, Config.settings!())
  end

  test "accepts branch rule from the ticket body when Linear branch name is absent" do
    issue = %Issue{
      id: "issue-ready-body-branch",
      identifier: "BEC-128",
      title: "Ready issue with body branch rule",
      state: "Todo",
      description: """
      ## Goal
      Ship the bounded change.

      ## Repo
      repo: causalflow
      base branch: main
      branch rule: codex/BEC-128-ready-body-branch

      ## Risk Tier
      low

      ## Scope
      Include: update the readiness gate.
      Exclude: unrelated worker behavior.

      ## Acceptance
      The gate accepts the body branch rule.

      ## Validation
      rtk mise exec -- mix test

      ## Deploy / Check Evidence
      GitHub Actions symphony-gate check.

      ## Exit Policy
      Move to Human Review only after evidence passes; otherwise Rework.
      """
    }

    assert :ok = TicketReadiness.validate(issue, Config.settings!())
  end

  test "reports precise missing fields without exposing issue content" do
    issue = %Issue{
      id: "issue-malformed",
      identifier: "BEC-124",
      title: "Malformed issue",
      state: "Todo",
      description: """
      ## Goal
      Do work.

      ## Repo
      repo: causalflow
      """
    }

    assert {:error, failures} = TicketReadiness.validate(issue, Config.settings!())
    assert "Repo must name a base branch." in failures
    assert "Risk Tier section is missing." in failures
    assert "Scope section is missing." in failures
    assert "Validation section is missing." in failures
    assert "Deploy / Check Evidence section is missing." in failures
    assert "Exit Policy section is missing." in failures
  end

  test "blocking an unready issue comments precisely and moves it to Rework" do
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "memory")
    Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

    issue = %Issue{
      id: "issue-blocked-readiness",
      identifier: "BEC-125",
      title: "Blocked readiness",
      state: "Todo",
      description: """
      ## Goal
      Do work.
      """
    }

    assert {:blocked, failures} = Orchestrator.readiness_gate_for_test(issue)
    assert "Repo section is missing." in failures

    assert_receive {:memory_tracker_comment, "issue-blocked-readiness", body}, 500
    assert body =~ "## Symphony Readiness Blocker"
    assert body =~ "- Repo section is missing."
    refute body =~ "Do work."

    assert_receive {:memory_tracker_state_update, "issue-blocked-readiness", "Rework"}, 500
  end

  test "prompt includes compact Symphony start context" do
    issue = %Issue{
      id: "issue-context",
      identifier: "BEC-126",
      title: "Context issue",
      state: "Todo",
      branch_name: "codex/BEC-126-context-issue",
      description: """
      ## Goal
      Ship the bounded change.

      ## Repo
      repo: causalflow
      base branch: main

      ## Risk Tier
      low

      ## Scope
      Include: context.
      Exclude: unrelated behavior.

      ## Acceptance
      Context appears.

      ## Validation
      rtk mise exec -- mix test

      ## Deploy / Check Evidence
      GitHub Actions symphony-gate check.

      ## Exit Policy
      Human Review on pass; Rework on failure.
      """
    }

    prompt = PromptBuilder.build_prompt(issue)

    assert prompt =~ "Symphony readiness: passed"
    assert prompt =~ "Validation command: rtk mise exec -- mix test"
    assert prompt =~ "Symphony owns validation, push, PR publication, Linear evidence, and Linear state transitions"
  end

  test "dispatch loop blocks unready Linear issues before worker launch" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "memory",
      poll_interval_ms: 30_000,
      max_concurrent_agents: 1
    )

    Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

    issue = %Issue{
      id: "issue-dispatch-blocked-readiness",
      identifier: "BEC-127",
      title: "Dispatch blocked readiness",
      state: "Todo",
      description: """
      ## Goal
      Do work.
      """
    }

    Application.put_env(:symphony_elixir, :memory_tracker_issues, [issue])

    orchestrator_name = Module.concat(__MODULE__, :ReadinessDispatchOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)

    send(pid, :tick)

    assert_receive {:memory_tracker_comment, "issue-dispatch-blocked-readiness", body}, 1_000
    assert body =~ "## Symphony Readiness Blocker"
    assert_receive {:memory_tracker_state_update, "issue-dispatch-blocked-readiness", "Rework"}, 1_000

    state = :sys.get_state(pid)
    assert state.running == %{}
    assert MapSet.member?(state.completed, "issue-dispatch-blocked-readiness")
  end
end
