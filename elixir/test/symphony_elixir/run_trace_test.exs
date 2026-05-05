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
        %{reason: {:evidence_gate_failed, ["missing PR"]}}
      )

      [line] = trace_file |> File.read!() |> String.trim() |> String.split("\n")
      assert {:ok, payload} = Jason.decode(line)
      assert payload["issue_identifier"] == "BEC-123"
      assert payload["outcome"] == "rework"
      assert payload["failure_bucket"] == "evidence_gate"
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

  defp restore_app_env(key, nil), do: Application.delete_env(:symphony_elixir, key)
  defp restore_app_env(key, value), do: Application.put_env(:symphony_elixir, key, value)
end
