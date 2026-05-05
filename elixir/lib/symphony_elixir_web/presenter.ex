defmodule SymphonyElixirWeb.Presenter do
  @moduledoc """
  Shared projections for the observability API and dashboard.
  """

  alias SymphonyElixir.{Config, Orchestrator, RunTrace, StatusDashboard}

  @spec state_payload(GenServer.name(), timeout()) :: map()
  def state_payload(orchestrator, snapshot_timeout_ms) do
    generated_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    case Orchestrator.snapshot(orchestrator, snapshot_timeout_ms) do
      %{} = snapshot ->
        %{
          generated_at: generated_at,
          counts: %{
            running: length(snapshot.running),
            retrying: length(snapshot.retrying)
          },
          running: Enum.map(snapshot.running, &running_entry_payload/1),
          retrying: Enum.map(snapshot.retrying, &retry_entry_payload/1),
          codex_totals: codex_totals_payload(snapshot.codex_totals),
          rate_limits: snapshot.rate_limits,
          completed_runs: completed_runs_payload()
        }

      :timeout ->
        %{generated_at: generated_at, error: %{code: "snapshot_timeout", message: "Snapshot timed out"}}

      :unavailable ->
        %{generated_at: generated_at, error: %{code: "snapshot_unavailable", message: "Snapshot unavailable"}}
    end
  end

  @spec issue_payload(String.t(), GenServer.name(), timeout()) :: {:ok, map()} | {:error, :issue_not_found}
  def issue_payload(issue_identifier, orchestrator, snapshot_timeout_ms) when is_binary(issue_identifier) do
    case Orchestrator.snapshot(orchestrator, snapshot_timeout_ms) do
      %{} = snapshot ->
        running = Enum.find(snapshot.running, &(&1.identifier == issue_identifier))
        retry = Enum.find(snapshot.retrying, &(&1.identifier == issue_identifier))

        if is_nil(running) and is_nil(retry) do
          {:error, :issue_not_found}
        else
          {:ok, issue_payload_body(issue_identifier, running, retry)}
        end

      _ ->
        {:error, :issue_not_found}
    end
  end

  @spec refresh_payload(GenServer.name()) :: {:ok, map()} | {:error, :unavailable}
  def refresh_payload(orchestrator) do
    case Orchestrator.request_refresh(orchestrator) do
      :unavailable ->
        {:error, :unavailable}

      payload ->
        {:ok, Map.update!(payload, :requested_at, &DateTime.to_iso8601/1)}
    end
  end

  defp issue_payload_body(issue_identifier, running, retry) do
    %{
      issue_identifier: issue_identifier,
      issue_id: issue_id_from_entries(running, retry),
      status: issue_status(running, retry),
      workspace: %{
        path: workspace_path(issue_identifier, running, retry),
        host: workspace_host(running, retry)
      },
      attempts: %{
        restart_count: restart_count(retry),
        current_retry_attempt: retry_attempt(retry)
      },
      running: running && running_issue_payload(running),
      retry: retry && retry_issue_payload(retry),
      logs: %{
        codex_session_logs: []
      },
      recent_events: (running && recent_events_payload(running)) || [],
      last_error: retry && retry.error,
      tracked: %{}
    }
  end

  defp issue_id_from_entries(running, retry),
    do: (running && running.issue_id) || (retry && retry.issue_id)

  defp restart_count(retry), do: max(retry_attempt(retry) - 1, 0)
  defp retry_attempt(nil), do: 0
  defp retry_attempt(retry), do: retry.attempt || 0

  defp issue_status(_running, nil), do: "running"
  defp issue_status(nil, _retry), do: "retrying"
  defp issue_status(_running, _retry), do: "running"

  defp running_entry_payload(entry) do
    %{
      issue_id: entry.issue_id,
      issue_identifier: entry.identifier,
      state: entry.state,
      worker_host: Map.get(entry, :worker_host),
      workspace_path: Map.get(entry, :workspace_path),
      session_id: entry.session_id,
      turn_count: Map.get(entry, :turn_count, 0),
      last_event: entry.last_codex_event,
      last_message: summarize_message(entry.last_codex_message),
      started_at: iso8601(entry.started_at),
      last_event_at: iso8601(entry.last_codex_timestamp),
      tokens: tokens_payload(entry)
    }
  end

  defp retry_entry_payload(entry) do
    %{
      issue_id: entry.issue_id,
      issue_identifier: entry.identifier,
      attempt: entry.attempt,
      due_at: due_at_iso8601(entry.due_in_ms),
      error: entry.error,
      worker_host: Map.get(entry, :worker_host),
      workspace_path: Map.get(entry, :workspace_path)
    }
  end

  defp completed_runs_payload do
    RunTrace.recent(20)
    |> Enum.map(&completed_run_payload/1)
  end

  defp completed_run_payload(entry) when is_map(entry) do
    %{
      issue_identifier: Map.get(entry, "issue_identifier"),
      outcome: Map.get(entry, "outcome"),
      failure_bucket: Map.get(entry, "failure_bucket"),
      pr_url: Map.get(entry, "pr_url"),
      check_url: Map.get(entry, "check_url"),
      runtime_seconds: Map.get(entry, "runtime_seconds"),
      manual_rescue_count: Map.get(entry, "manual_rescue_count"),
      tokens: completed_run_tokens_payload(Map.get(entry, "tokens")),
      recorded_at: Map.get(entry, "recorded_at")
    }
  end

  defp completed_run_tokens_payload(tokens) when is_map(tokens) do
    %{
      uncached_total_tokens: map_value(tokens, :uncached_total_tokens, 0),
      total_tokens: map_value(tokens, :total_tokens, 0)
    }
  end

  defp completed_run_tokens_payload(_tokens), do: completed_run_tokens_payload(%{})

  defp running_issue_payload(running) do
    %{
      worker_host: Map.get(running, :worker_host),
      workspace_path: Map.get(running, :workspace_path),
      session_id: running.session_id,
      turn_count: Map.get(running, :turn_count, 0),
      state: running.state,
      started_at: iso8601(running.started_at),
      last_event: running.last_codex_event,
      last_message: summarize_message(running.last_codex_message),
      last_event_at: iso8601(running.last_codex_timestamp),
      tokens: tokens_payload(running)
    }
  end

  defp codex_totals_payload(totals) when is_map(totals) do
    input_tokens = map_value(totals, :input_tokens, 0)
    cached_input_tokens = map_value(totals, :cached_input_tokens, 0)
    output_tokens = map_value(totals, :output_tokens, 0)
    total_tokens = map_value(totals, :total_tokens, input_tokens + output_tokens)

    %{
      input_tokens: input_tokens,
      cached_input_tokens: cached_input_tokens,
      uncached_input_tokens: map_value(totals, :uncached_input_tokens, max(input_tokens - cached_input_tokens, 0)),
      output_tokens: output_tokens,
      uncached_total_tokens: map_value(totals, :uncached_total_tokens, max(total_tokens - cached_input_tokens, 0)),
      total_tokens: total_tokens,
      seconds_running: map_value(totals, :seconds_running, 0)
    }
  end

  defp codex_totals_payload(_totals), do: codex_totals_payload(%{})

  defp tokens_payload(entry) when is_map(entry) do
    input_tokens = map_value(entry, :codex_input_tokens, 0)
    cached_input_tokens = map_value(entry, :codex_cached_input_tokens, 0)
    output_tokens = map_value(entry, :codex_output_tokens, 0)
    total_tokens = map_value(entry, :codex_total_tokens, input_tokens + output_tokens)

    %{
      input_tokens: input_tokens,
      cached_input_tokens: cached_input_tokens,
      uncached_input_tokens: map_value(entry, :codex_uncached_input_tokens, max(input_tokens - cached_input_tokens, 0)),
      output_tokens: output_tokens,
      uncached_total_tokens: map_value(entry, :codex_uncached_total_tokens, max(total_tokens - cached_input_tokens, 0)),
      total_tokens: total_tokens
    }
  end

  defp map_value(map, key, default) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default
  end

  defp retry_issue_payload(retry) do
    %{
      attempt: retry.attempt,
      due_at: due_at_iso8601(retry.due_in_ms),
      error: retry.error,
      worker_host: Map.get(retry, :worker_host),
      workspace_path: Map.get(retry, :workspace_path)
    }
  end

  defp workspace_path(issue_identifier, running, retry) do
    (running && Map.get(running, :workspace_path)) ||
      (retry && Map.get(retry, :workspace_path)) ||
      Path.join(Config.settings!().workspace.root, issue_identifier)
  end

  defp workspace_host(running, retry) do
    (running && Map.get(running, :worker_host)) || (retry && Map.get(retry, :worker_host))
  end

  defp recent_events_payload(running) do
    [
      %{
        at: iso8601(running.last_codex_timestamp),
        event: running.last_codex_event,
        message: summarize_message(running.last_codex_message)
      }
    ]
    |> Enum.reject(&is_nil(&1.at))
  end

  defp summarize_message(nil), do: nil
  defp summarize_message(message), do: StatusDashboard.humanize_codex_message(message)

  defp due_at_iso8601(due_in_ms) when is_integer(due_in_ms) do
    DateTime.utc_now()
    |> DateTime.add(div(due_in_ms, 1_000), :second)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp due_at_iso8601(_due_in_ms), do: nil

  defp iso8601(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp iso8601(_datetime), do: nil
end
