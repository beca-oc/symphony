defmodule SymphonyElixir.RepairPacket do
  @moduledoc """
  Builds deterministic Linear repair packets for Rework runs.
  """

  alias SymphonyElixir.{Config, DeliveryEvidence, RepairPolicy}

  @spec from_report(map(), keyword()) :: map()
  def from_report(%{failures: failures, evidence: evidence} = report, opts \\ []) when is_list(failures) do
    attempt = Keyword.get(opts, :repair_attempt, 1)
    bucket = DeliveryEvidence.failure_bucket(failures)
    policy = Config.settings!().repair
    next_action = RepairPolicy.next_action(policy, bucket, attempt)

    %{
      gate: "delivery evidence",
      attempt: attempt,
      failure_bucket: bucket,
      retry_allowed: next_action == :retry_same_branch,
      next_action: next_action,
      failures: failures,
      branch: Map.get(evidence || %{}, :branch),
      pr_url: Map.get(evidence || %{}, :pr_url),
      head_sha: Map.get(evidence || %{}, :commit_sha),
      failing_check_url: failing_check_url(report),
      validation_command: validation_command()
    }
  end

  @spec from_preflight(term(), keyword()) :: map()
  def from_preflight(reason, opts \\ []) do
    attempt = Keyword.get(opts, :repair_attempt, 1)
    policy = Config.settings!().repair
    next_action = RepairPolicy.next_action(policy, :preflight, attempt)

    %{
      gate: "validation.preflight",
      attempt: attempt,
      failure_bucket: :preflight,
      retry_allowed: next_action == :retry_same_branch,
      next_action: next_action,
      failures: [format_preflight_reason(reason)],
      branch: nil,
      pr_url: nil,
      head_sha: nil,
      failing_check_url: nil,
      validation_command: Config.settings!().validation.preflight
    }
  end

  @spec render(map()) :: String.t()
  def render(packet) when is_map(packet) do
    failures =
      packet
      |> Map.get(:failures, [])
      |> Enum.map_join("\n", &("- " <> to_string(&1)))

    """
    ## Symphony Repair Packet

    Gate: #{Map.get(packet, :gate) || "delivery evidence"}
    Result: failed
    Attempt: #{Map.get(packet, :attempt, 1)}
    Failure bucket: #{Map.get(packet, :failure_bucket)}
    Retry allowed: #{Map.get(packet, :retry_allowed)}
    Next action: #{Map.get(packet, :next_action)}
    Branch: #{Map.get(packet, :branch) || "n/a"}
    PR: #{Map.get(packet, :pr_url) || "n/a"}
    Head SHA: #{Map.get(packet, :head_sha) || "n/a"}
    Failing check/deploy URL: #{Map.get(packet, :failing_check_url) || "n/a"}
    Validation command: #{Map.get(packet, :validation_command) || "n/a"}

    ### Failures
    #{failures}

    Symphony moved this issue to Rework. If retry is allowed, the next worker must continue the same branch and PR, repair only this packet, and avoid duplicate PRs.
    """
  end

  defp failing_check_url(%{evidence: %{checker: %{observed_checks: checks}}}) when is_list(checks) do
    Enum.find_value(checks, fn
      %{url: url, state: state} when is_binary(url) and state in [:failure, :error, :cancelled, "failure", "error", "cancelled"] ->
        url

      %{"url" => url, "state" => state}
      when is_binary(url) and state in [:failure, :error, :cancelled, "failure", "error", "cancelled"] ->
        url

      _ ->
        nil
    end)
  end

  defp failing_check_url(%{evidence: evidence}) when is_map(evidence) do
    Map.get(evidence, :deployment_url)
  end

  defp failing_check_url(_report), do: nil

  defp validation_command do
    settings = Config.settings!()
    settings.validation.fast || settings.validation.preflight || settings.validation.full
  end

  defp format_preflight_reason({:workspace_hook_failed, "validation.preflight", status, output}) do
    "validation.preflight exited #{status}: #{truncate_output(output)}"
  end

  defp format_preflight_reason({:workspace_hook_timeout, "validation.preflight", timeout_ms}) do
    "validation.preflight timed out after #{timeout_ms}ms"
  end

  defp format_preflight_reason(reason), do: inspect(reason)

  defp truncate_output(output, max_bytes \\ 1_024) do
    text = IO.iodata_to_binary(output || "")

    if byte_size(text) <= max_bytes do
      text
    else
      binary_part(text, 0, max_bytes) <> "... (truncated)"
    end
  end
end
