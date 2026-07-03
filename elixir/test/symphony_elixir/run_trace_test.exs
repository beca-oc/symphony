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

  test "record promotes repair and semantic review lineage into top-level telemetry" do
    test_root = Path.join(System.tmp_dir!(), "symphony-elixir-run-trace-lineage-#{System.unique_integer([:positive])}")
    trace_file = Path.join(test_root, "runs.ndjson")
    old_trace_file = Application.get_env(:symphony_elixir, :run_trace_file)

    try do
      Application.put_env(:symphony_elixir, :run_trace_file, trace_file)

      RunTrace.record(
        %{
          identifier: "BEC-200",
          issue: %Issue{id: "issue-200", identifier: "BEC-200", state: "Rework"},
          started_at: DateTime.utc_now()
        },
        :rework,
        :ci_failed,
        %{
          attempt_kind: :repair,
          attempt_number: 2,
          repair_of_trace_id: "trace-delivery-1",
          failing_check_url: "https://github.com/Subconscious-ai/example/actions/runs/10/job/11",
          passing_check_url: "https://github.com/Subconscious-ai/example/actions/runs/12/job/13",
          semantic_review: %{verdict: :pass, reviewer_id: "openclaw-reviewer-merge-captain"},
          reviewed_sha: "abc123",
          merge_eligibility: :human_review
        }
      )

      [line] = trace_file |> File.read!() |> String.trim() |> String.split("\n")
      assert {:ok, payload} = Jason.decode(line)
      assert payload["attempt_kind"] == "repair"
      assert payload["attempt_number"] == 2
      assert payload["repair_of_trace_id"] == "trace-delivery-1"
      assert payload["failing_check_url"] =~ "/actions/runs/10/job/11"
      assert payload["passing_check_url"] =~ "/actions/runs/12/job/13"
      assert payload["semantic_review"]["verdict"] == "pass"
      assert payload["reviewed_sha"] == "abc123"
      assert payload["merge_eligibility"] == "human_review"
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

  test "recent reads latest valid trace records first and ignores malformed lines" do
    test_root = Path.join(System.tmp_dir!(), "symphony-elixir-run-trace-recent-#{System.unique_integer([:positive])}")
    trace_file = Path.join(test_root, "runs.ndjson")
    old_trace_file = Application.get_env(:symphony_elixir, :run_trace_file)

    try do
      Application.put_env(:symphony_elixir, :run_trace_file, trace_file)
      File.mkdir_p!(test_root)

      File.write!(trace_file, Jason.encode!(%{issue_identifier: "BEC-1", recorded_at: "2026-05-05T01:00:00Z"}) <> "\n")
      File.write!(trace_file, "not json\n", [:append])
      File.write!(trace_file, Jason.encode!(%{issue_identifier: "BEC-2", recorded_at: "2026-05-05T02:00:00Z"}) <> "\n", [:append])

      assert [
               %{"issue_identifier" => "BEC-2"},
               %{"issue_identifier" => "BEC-1"}
             ] = RunTrace.recent(10)

      assert [%{"issue_identifier" => "BEC-2"}] = RunTrace.recent(1)
    after
      restore_app_env(:run_trace_file, old_trace_file)
      File.rm_rf(test_root)
    end
  end

  test "record handles default details, invalid inputs, and direct entry evidence" do
    test_root = Path.join(System.tmp_dir!(), "symphony-elixir-run-trace-defaults-#{System.unique_integer([:positive])}")
    trace_file = Path.join(test_root, "runs.ndjson")
    old_trace_file = Application.get_env(:symphony_elixir, :run_trace_file)

    try do
      Application.put_env(:symphony_elixir, :run_trace_file, trace_file)

      assert :ok =
               RunTrace.record(
                 %{
                   identifier: "BEC-3",
                   pr_url: "https://github.com/Subconscious-ai/example/pull/3",
                   check_url: "https://github.com/Subconscious-ai/example/actions/runs/3/job/4",
                   manual_rescue_count: 2,
                   started_at: nil
                 },
                 :completed,
                 :none
               )

      assert :ok = RunTrace.record(:invalid, :completed, :none, %{})
      assert [] = RunTrace.recent(0)

      assert [%{"issue_identifier" => "BEC-3"} = payload] = RunTrace.recent()
      assert payload["pr_url"] == "https://github.com/Subconscious-ai/example/pull/3"
      assert payload["check_url"] == "https://github.com/Subconscious-ai/example/actions/runs/3/job/4"
      assert payload["manual_rescue_count"] == 2
      assert payload["started_at"] == nil
      assert payload["runtime_seconds"] == 0
    after
      restore_app_env(:run_trace_file, old_trace_file)
      File.rm_rf(test_root)
    end
  end

  test "recent and record degrade gracefully when trace files are missing or unwritable" do
    test_root = Path.join(System.tmp_dir!(), "symphony-elixir-run-trace-errors-#{System.unique_integer([:positive])}")
    missing_trace_file = Path.join(test_root, "missing.ndjson")
    unwritable_trace_file = Path.join(test_root, "trace-directory")
    old_trace_file = Application.get_env(:symphony_elixir, :run_trace_file)

    try do
      Application.put_env(:symphony_elixir, :run_trace_file, missing_trace_file)
      assert [] = RunTrace.recent(5)

      File.mkdir_p!(unwritable_trace_file)
      Application.put_env(:symphony_elixir, :run_trace_file, unwritable_trace_file)

      read_log =
        capture_log(fn ->
          assert [] = RunTrace.recent(5)
        end)

      assert read_log =~ "Failed to read Symphony run trace"

      write_log =
        capture_log(fn ->
          assert :ok = RunTrace.record(%{identifier: "BEC-4"}, :completed, :none)
        end)

      assert write_log =~ "Failed to append Symphony run trace"
    after
      restore_app_env(:run_trace_file, old_trace_file)
      File.rm_rf(test_root)
    end
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:symphony_elixir, key)
  defp restore_app_env(key, value), do: Application.put_env(:symphony_elixir, key, value)
end
