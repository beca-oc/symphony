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

  @spec record(map(), atom() | String.t(), atom() | String.t(), map()) :: :ok
  def record(running_entry, outcome, failure_bucket, details) when is_map(running_entry) and is_map(details) do
    sanitized_details = sanitize(details)

    payload =
      running_entry
      |> base_payload(outcome, failure_bucket)
      |> merge_detail_evidence(sanitized_details)
      |> merge_attempt_lineage(sanitized_details)
      |> Map.merge(%{
        details: sanitized_details,
        recorded_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    trace_file()
    |> append_payload(payload)
  end

  def record(_running_entry, _outcome, _failure_bucket, _details), do: :ok

  @spec recent(pos_integer()) :: [map()]
  def recent(limit \\ 20)

  @spec recent(pos_integer()) :: [map()]
  def recent(limit) when is_integer(limit) and limit > 0 do
    trace_file()
    |> read_trace_lines()
    |> Enum.map(&decode_trace_line/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(limit)
  end

  def recent(_limit), do: []

  defp base_payload(running_entry, outcome, failure_bucket) do
    issue = Map.get(running_entry, :issue)
    started_at = Map.get(running_entry, :started_at)
    finished_at = DateTime.utc_now()

    %{
      issue_id: Map.get(running_entry, :issue_id) || Map.get(issue || %{}, :id),
      issue_identifier: Map.get(running_entry, :identifier) || Map.get(issue || %{}, :identifier),
      issue_state: Map.get(issue || %{}, :state),
      repo: repo_payload(running_entry),
      outcome: to_string(outcome),
      failure_bucket: to_string(failure_bucket || "none"),
      pr_url: evidence_url(running_entry, :pr_url),
      check_url: evidence_url(running_entry, :check_url),
      manual_rescue_count: manual_rescue_count(running_entry),
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

  defp read_trace_lines(path) when is_binary(path) do
    case File.read(path) do
      {:ok, contents} ->
        contents
        |> String.split("\n", trim: true)
        |> Enum.reverse()

      {:error, :enoent} ->
        []

      {:error, reason} ->
        Logger.warning("Failed to read Symphony run trace path=#{path}: #{inspect(reason)}")
        []
    end
  end

  defp decode_trace_line(line) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, %{} = payload} -> payload
      _ -> nil
    end
  end

  defp repo_payload(running_entry) do
    case Map.get(running_entry, :repo_name) || get_in(running_entry, [:repo, :name]) do
      name when is_binary(name) and name != "" -> %{name: name}
      _ -> nil
    end
  end

  defp evidence_url(running_entry, key) do
    case Map.get(running_entry, key) || get_in(running_entry, [:delivery_evidence, key]) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp merge_detail_evidence(payload, details) when is_map(payload) and is_map(details) do
    delivery_evidence = map_value(details, "delivery_evidence")
    checker = map_value(details, "checker")

    payload
    |> maybe_put_detail_value(:pr_url, details, "pr_url")
    |> maybe_put_detail_value(:pr_url, delivery_evidence, "pr_url")
    |> maybe_put_detail_value(:check_url, details, "check_url")
    |> maybe_put_detail_value(:check_url, delivery_evidence, "deployment_url")
    |> maybe_put_map(:delivery_evidence, delivery_evidence)
    |> maybe_put_map(:checker, checker)
    |> maybe_put_manual_rescue_count(details)
  end

  defp merge_attempt_lineage(payload, details) when is_map(payload) and is_map(details) do
    payload
    |> maybe_put_detail_value(:attempt_kind, details, "attempt_kind")
    |> maybe_put_detail_value(:attempt_number, details, "attempt_number")
    |> maybe_put_detail_value(:repair_of_trace_id, details, "repair_of_trace_id")
    |> maybe_put_detail_value(:failing_check_url, details, "failing_check_url")
    |> maybe_put_detail_value(:passing_check_url, details, "passing_check_url")
    |> maybe_put_detail_value(:reviewed_sha, details, "reviewed_sha")
    |> maybe_put_detail_value(:merge_eligibility, details, "merge_eligibility")
    |> maybe_put_map(:semantic_review, map_value(details, "semantic_review"))
    |> maybe_put_map(:repair_packet, map_value(details, "repair_packet"))
  end

  defp map_value(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_map(value) -> value
      _ -> %{}
    end
  end

  defp maybe_put_map(payload, _key, value) when value == %{}, do: payload
  defp maybe_put_map(payload, key, value) when is_map(value), do: Map.put(payload, key, value)
  defp maybe_put_map(payload, _key, _value), do: payload

  defp maybe_put_detail_value(payload, payload_key, details, details_key) do
    if present?(Map.get(payload, payload_key)) do
      payload
    else
      value = Map.get(details, details_key)

      if present?(value) do
        Map.put(payload, payload_key, value)
      else
        payload
      end
    end
  end

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(value), do: not is_nil(value)

  defp maybe_put_manual_rescue_count(payload, %{"manual_rescue_count" => value}) when is_integer(value) and value >= 0,
    do: Map.put(payload, :manual_rescue_count, value)

  defp maybe_put_manual_rescue_count(payload, _details), do: payload

  defp manual_rescue_count(running_entry) do
    case Map.get(running_entry, :manual_rescue_count) do
      value when is_integer(value) and value >= 0 -> value
      _ -> 0
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
  defp sanitize(value) when is_boolean(value), do: value
  defp sanitize(value) when is_atom(value), do: to_string(value)
  defp sanitize(value), do: value
end
