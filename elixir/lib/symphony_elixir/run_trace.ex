defmodule SymphonyElixir.RunTrace do
  @moduledoc """
  Appends deterministic per-run records for later Symphony harness evals.
  """

  require Logger

  @default_trace_relative_path "log/symphony-runs.ndjson"

  @spec default_trace_file() :: Path.t()
  def default_trace_file do
    default_trace_file(File.cwd!())
  end

  @spec default_trace_file(Path.t()) :: Path.t()
  def default_trace_file(root) when is_binary(root) do
    Path.join(root, @default_trace_relative_path)
  end

  @spec record(map(), atom() | String.t(), atom() | String.t(), map()) :: :ok
  def record(running_entry, outcome, failure_bucket, details \\ %{})

  def record(running_entry, outcome, failure_bucket, details) when is_map(running_entry) and is_map(details) do
    payload =
      running_entry
      |> base_payload(outcome, failure_bucket)
      |> Map.merge(%{
        details: sanitize(details),
        recorded_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    trace_file()
    |> append_payload(payload)
  end

  def record(_running_entry, _outcome, _failure_bucket, _details), do: :ok

  defp base_payload(running_entry, outcome, failure_bucket) do
    issue = Map.get(running_entry, :issue)
    started_at = Map.get(running_entry, :started_at)
    finished_at = DateTime.utc_now()

    %{
      issue_id: Map.get(running_entry, :issue_id) || Map.get(issue || %{}, :id),
      issue_identifier: Map.get(running_entry, :identifier) || Map.get(issue || %{}, :identifier),
      issue_state: Map.get(issue || %{}, :state),
      outcome: to_string(outcome),
      failure_bucket: to_string(failure_bucket || "none"),
      session_id: Map.get(running_entry, :session_id),
      workspace_path: Map.get(running_entry, :workspace_path),
      worker_host: Map.get(running_entry, :worker_host),
      retry_attempt: Map.get(running_entry, :retry_attempt, 0),
      turn_count: Map.get(running_entry, :turn_count, 0),
      runtime_seconds: runtime_seconds(started_at, finished_at),
      tokens: %{
        input_tokens: Map.get(running_entry, :codex_input_tokens, 0),
        cached_input_tokens: Map.get(running_entry, :codex_cached_input_tokens, 0),
        uncached_input_tokens: Map.get(running_entry, :codex_uncached_input_tokens, 0),
        output_tokens: Map.get(running_entry, :codex_output_tokens, 0),
        uncached_total_tokens: Map.get(running_entry, :codex_uncached_total_tokens, 0),
        total_tokens: Map.get(running_entry, :codex_total_tokens, 0)
      },
      tool_calls: %{
        total: Map.get(running_entry, :codex_tool_calls, 0),
        failed: Map.get(running_entry, :codex_tool_call_failures, 0),
        unsupported: Map.get(running_entry, :codex_unsupported_tool_calls, 0),
        user_input_auto_answers: Map.get(running_entry, :codex_tool_input_auto_answers, 0)
      },
      event_counts: Map.get(running_entry, :codex_event_counts, %{}),
      started_at: iso8601(started_at),
      finished_at: DateTime.to_iso8601(finished_at)
    }
  end

  defp append_payload(path, payload) when is_binary(path) do
    json = Jason.encode!(payload)
    File.mkdir_p!(Path.dirname(path))

    case File.write(path, json <> "\n", [:append]) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to append Symphony run trace path=#{path}: #{inspect(reason)}")
        :ok
    end
  end

  defp trace_file do
    Application.get_env(:symphony_elixir, :run_trace_file, default_trace_file())
    |> Path.expand()
  end

  defp runtime_seconds(%DateTime{} = started_at, %DateTime{} = finished_at) do
    max(0, DateTime.diff(finished_at, started_at, :second))
  end

  defp runtime_seconds(_started_at, _finished_at), do: 0

  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso8601(_value), do: nil

  defp sanitize(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), sanitize(nested)} end)
  end

  defp sanitize(value) when is_tuple(value), do: value |> Tuple.to_list() |> sanitize()
  defp sanitize(value) when is_list(value), do: Enum.map(value, &sanitize/1)
  defp sanitize(value) when is_atom(value), do: to_string(value)
  defp sanitize(value), do: value
end
