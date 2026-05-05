defmodule SymphonyElixir.RunTraceTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.RunTrace

  test "record appends token, tool, retry, outcome, and failure bucket data as ndjson" do
    test_root = Path.join(System.tmp_dir!(), "symphony-elixir-run-trace-#{System.unique_integer([:positive])}")
    trace_file = Path.join(test_root, "runs.ndjson")
    old_trace_file = Application.get_env(:symphony_elixir, :run_trace_file)

    try do
      Application.put_env(:symphony_elixir, :run_trace_file, trace_file)

      started_at = DateTime.add(DateTime.utc_now(), -5, :second)

      RunTrace.record(
        %{
          identifier: "BEC-123",
          issue: %Issue{id: "issue-123", identifier: "BEC-123", state: "In Progress"},
          repo_name: "ai-chatbot",
          session_id: "thread-turn",
          workspace_path: "/tmp/workspace",
          worker_host: nil,
          retry_attempt: 2,
          turn_count: 1,
          started_at: started_at,
          codex_input_tokens: 100,
          codex_cached_input_tokens: 25,
          codex_uncached_input_tokens: 75,
          codex_output_tokens: 30,
          codex_uncached_total_tokens: 105,
          codex_total_tokens: 130,
          codex_tool_calls: 3,
          codex_tool_call_failures: 1,
          codex_unsupported_tool_calls: 1,
          codex_tool_input_auto_answers: 2,
          codex_event_counts: %{"tool_call_completed" => 2}
        },
        :rework,
        :evidence_gate,
        %{
          reason: {:evidence_gate_failed, ["missing PR"]},
          pr_url: "https://github.com/Subconscious-ai/ai-chatbot/pull/123",
          check_url: "https://github.com/Subconscious-ai/ai-chatbot/actions/runs/1/job/2",
          manual_rescue_count: 1
        }
      )

      [line] = trace_file |> File.read!() |> String.trim() |> String.split("\n")
      assert {:ok, payload} = Jason.decode(line)
      assert payload["issue_identifier"] == "BEC-123"
      assert payload["repo"] == %{"name" => "ai-chatbot"}
      assert payload["outcome"] == "rework"
      assert payload["failure_bucket"] == "evidence_gate"
      assert payload["pr_url"] == "https://github.com/Subconscious-ai/ai-chatbot/pull/123"
      assert payload["check_url"] == "https://github.com/Subconscious-ai/ai-chatbot/actions/runs/1/job/2"
      assert payload["manual_rescue_count"] == 1
      assert payload["retry_attempt"] == 2
      assert payload["tokens"]["uncached_total_tokens"] == 105
      assert payload["tool_calls"]["total"] == 3
      assert payload["tool_calls"]["failed"] == 1
      assert payload["event_counts"]["tool_call_completed"] == 2
      assert payload["details"]["reason"] == ["evidence_gate_failed", ["missing PR"]]
    after
      restore_app_env(:run_trace_file, old_trace_file)
      File.rm_rf(test_root)
    end
  end

  test "record promotes delivery evidence and checker report into top-level telemetry" do
    test_root = Path.join(System.tmp_dir!(), "symphony-elixir-run-trace-evidence-#{System.unique_integer([:positive])}")
    trace_file = Path.join(test_root, "runs.ndjson")
    old_trace_file = Application.get_env(:symphony_elixir, :run_trace_file)

    try do
      Application.put_env(:symphony_elixir, :run_trace_file, trace_file)

      RunTrace.record(
        %{
          identifier: "BEC-124",
          issue: %Issue{id: "issue-124", identifier: "BEC-124", state: "Todo"},
          started_at: DateTime.utc_now(),
          codex_total_tokens: 10
        },
        :human_review,
        :none,
        %{
          delivery_evidence: %{
            pr_url: "https://github.com/Subconscious-ai/example/pull/124",
            deployment_url: "https://github.com/Subconscious-ai/example/actions/runs/124/job/1",
            branch: "codex/BEC-124-marker",
            commit_sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
          },
          checker: %{
            passed: true,
            failure_bucket: :none,
            failures: [],
            observed_checks: [%{name: "symphony-gate", state: :success}],
            required_checks: ["symphony-gate"]
          }
        }
      )

      [line] = trace_file |> File.read!() |> String.trim() |> String.split("\n")
      assert {:ok, payload} = Jason.decode(line)
      assert payload["pr_url"] == "https://github.com/Subconscious-ai/example/pull/124"
      assert payload["check_url"] == "https://github.com/Subconscious-ai/example/actions/runs/124/job/1"
      assert payload["delivery_evidence"]["branch"] == "codex/BEC-124-marker"
      assert payload["checker"]["passed"] == true
      assert payload["checker"]["failure_bucket"] == "none"
      assert payload["checker"]["observed_checks"] == [%{"name" => "symphony-gate", "state" => "success"}]
      assert payload["checker"]["required_checks"] == ["symphony-gate"]
    after
      restore_app_env(:run_trace_file, old_trace_file)
      File.rm_rf(test_root)
    end
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:symphony_elixir, key)
  defp restore_app_env(key, value), do: Application.put_env(:symphony_elixir, key, value)
end
