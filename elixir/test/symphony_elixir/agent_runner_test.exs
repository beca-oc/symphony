defmodule SymphonyElixir.AgentRunnerTest do
  use SymphonyElixir.TestSupport

  test "missing required Codex env leaves issue in Rework without retrying" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-env-#{System.unique_integer([:positive])}"
      )

    missing_name = "SYMP_AGENT_REQUIRED_#{System.unique_integer([:positive])}"
    previous_missing = System.get_env(missing_name)
    on_exit(fn -> restore_env(missing_name, previous_missing) end)
    System.delete_env(missing_name)

    try do
      workspace_root = Path.join(test_root, "workspaces")
      File.mkdir_p!(workspace_root)

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        workspace_root: workspace_root,
        codex_required_environment: [missing_name]
      )

      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      issue = %Issue{
        id: "issue-agent-env",
        identifier: "MT-AGENT-ENV",
        title: "Validate agent env handling",
        description: "Missing env should block before Codex starts",
        state: "In Progress",
        url: "https://example.org/issues/MT-AGENT-ENV",
        labels: ["backend"]
      }

      assert :ok = AgentRunner.run(issue, self(), max_turns: 1)

      assert_receive {:memory_tracker_comment, "issue-agent-env", body}
      assert body =~ "Codex setup is missing required environment variables"
      assert body =~ missing_name
      refute body =~ "secret"

      assert_receive {:memory_tracker_state_update, "issue-agent-env", "Rework"}
    after
      File.rm_rf(test_root)
    end
  end
end
