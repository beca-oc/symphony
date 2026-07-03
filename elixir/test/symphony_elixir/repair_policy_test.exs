defmodule SymphonyElixir.RepairPolicyTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.{Config, RepairPolicy}

  test "default policy retries deterministic harness failures and blocks terminal failures" do
    write_workflow_file!(Workflow.workflow_file_path())
    policy = Config.settings!().repair

    assert RepairPolicy.retryable?(policy, :validation_failed, 0)
    assert RepairPolicy.retryable?(policy, :ci_failed, 1)
    refute RepairPolicy.retryable?(policy, :ci_failed, 2)
    refute RepairPolicy.retryable?(policy, :missing_secret, 0)
    refute RepairPolicy.retryable?(policy, :auth_blocked, 0)
  end

  test "next action is explicit for retryable, exhausted, and terminal buckets" do
    write_workflow_file!(Workflow.workflow_file_path(), repair_max_attempts: 2)
    policy = Config.settings!().repair

    assert RepairPolicy.next_action(policy, :ci_failed, 1) == :retry_same_branch
    assert RepairPolicy.next_action(policy, :ci_failed, 2) == :human_required
    assert RepairPolicy.next_action(policy, :unsafe_side_effect, 0) == :human_required
    assert RepairPolicy.next_action(%{retryable_failure_buckets: ["ci_failed"]}, :ci_failed, 1) == :retry_same_branch
    assert RepairPolicy.next_action(%{terminal_failure_buckets: [123]}, 123, 0) == :human_required
  end
end
