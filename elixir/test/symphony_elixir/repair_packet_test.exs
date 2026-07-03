defmodule SymphonyElixir.RepairPacketTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.RepairPacket

  test "from_report extracts failing check URLs from observed check shapes" do
    write_workflow_file!(Workflow.workflow_file_path(),
      validation_fast: "mix test",
      repair_max_attempts: 2,
      repair_retryable_failure_buckets: ["ci_failed"]
    )

    atom_check_packet =
      RepairPacket.from_report(%{
        failures: ["required PR check failed: unit-tests"],
        evidence: %{
          branch: "codex/BEC-10-fix",
          pr_url: "https://github.com/Subconscious-ai/example/pull/10",
          commit_sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          checker: %{
            observed_checks: [
              %{name: "ignored"},
              %{url: "https://github.com/Subconscious-ai/example/actions/runs/10/job/11", state: :failure}
            ]
          }
        }
      })

    assert atom_check_packet.failing_check_url =~ "/actions/runs/10/job/11"
    assert atom_check_packet.validation_command == "mix test"
    assert atom_check_packet.retry_allowed == true

    string_check_packet =
      RepairPacket.from_report(%{
        failures: ["required PR check failed: integration"],
        evidence: %{
          checker: %{
            observed_checks: [
              %{"url" => "https://github.com/Subconscious-ai/example/actions/runs/12/job/13", "state" => "error"}
            ]
          }
        }
      })

    assert string_check_packet.failing_check_url =~ "/actions/runs/12/job/13"
  end

  test "from_report falls back to deployment evidence or nil failing check URLs" do
    write_workflow_file!(Workflow.workflow_file_path(), validation_full: "mix test --cover")

    deployment_packet =
      RepairPacket.from_report(%{
        failures: ["missing validation"],
        evidence: %{deployment_url: "https://vercel.example/deploy/1"}
      })

    assert deployment_packet.failing_check_url == "https://vercel.example/deploy/1"
    assert deployment_packet.validation_command == "mix test --cover"

    no_evidence_packet =
      RepairPacket.from_report(%{
        failures: ["ambiguous delivery state"],
        evidence: nil
      })

    assert no_evidence_packet.failing_check_url == nil
  end

  test "from_preflight formats timeout, generic, and truncated hook failures" do
    write_workflow_file!(Workflow.workflow_file_path(), validation_preflight: "mix deps.get")

    timeout_packet = RepairPacket.from_preflight({:workspace_hook_timeout, "validation.preflight", 1234})
    assert timeout_packet.validation_command == "mix deps.get"
    assert timeout_packet.failures == ["validation.preflight timed out after 1234ms"]

    generic_packet = RepairPacket.from_preflight(:manual_blocker)
    assert generic_packet.failures == [":manual_blocker"]

    truncated_packet =
      RepairPacket.from_preflight(
        {:workspace_hook_failed, "validation.preflight", 17, String.duplicate("a", 1_050)},
        repair_attempt: 2
      )

    assert truncated_packet.attempt == 2
    assert hd(truncated_packet.failures) =~ "validation.preflight exited 17"
    assert hd(truncated_packet.failures) =~ "... (truncated)"
  end
end
