defmodule SymphonyElixir.RepairPolicy do
  @moduledoc """
  Classifies failed harness evidence into deterministic retry decisions.
  """

  @spec retryable?(map(), atom() | String.t(), non_neg_integer()) :: boolean()
  def retryable?(policy, failure_bucket, attempt_number) do
    next_action(policy, failure_bucket, attempt_number) == :retry_same_branch
  end

  @spec next_action(map(), atom() | String.t(), non_neg_integer()) :: :retry_same_branch | :human_required
  def next_action(policy, failure_bucket, attempt_number) do
    bucket = normalize_bucket(failure_bucket)

    cond do
      bucket in bucket_list(policy, :terminal_failure_buckets) ->
        :human_required

      bucket in bucket_list(policy, :retryable_failure_buckets) and attempt_number < max_attempts(policy) ->
        :retry_same_branch

      true ->
        :human_required
    end
  end

  defp max_attempts(%{max_attempts: attempts}) when is_integer(attempts) and attempts > 0, do: attempts
  defp max_attempts(_policy), do: 2

  defp bucket_list(policy, key) when is_map(policy) do
    policy
    |> Map.get(key, [])
    |> Enum.map(&normalize_bucket/1)
  end

  defp normalize_bucket(bucket) when is_atom(bucket), do: Atom.to_string(bucket)
  defp normalize_bucket(bucket) when is_binary(bucket), do: bucket
  defp normalize_bucket(bucket), do: to_string(bucket)
end
