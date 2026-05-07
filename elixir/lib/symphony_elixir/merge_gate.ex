defmodule SymphonyElixir.MergeGate do
  @moduledoc """
  Deterministic merge gate for Linear issues approved by moving them to Merging.
  """

  alias SymphonyElixir.{Linear.Issue, Tracker}

  @json_fields "url,headRefName,headRefOid,isDraft,labels,statusCheckRollup"

  @type gate_result :: %{
          comment: String.t(),
          head_sha: String.t() | nil,
          pr_url: String.t() | nil,
          state: String.t() | nil
        }

  @spec run(Issue.t()) :: :ok | {:blocked, String.t()} | {:error, term()}
  def run(%Issue{id: issue_id} = issue) when is_binary(issue_id) do
    case Tracker.fetch_issue_comments(issue_id) do
      {:ok, comments} -> persist_result(evaluate(issue, comments: comments), issue_id)
      {:error, reason} -> {:error, reason}
    end
  end

  def run(_issue), do: {:error, :invalid_issue}

  @spec evaluate(Issue.t()) :: {:ok, gate_result()} | {:blocked, gate_result()}
  def evaluate(issue), do: evaluate(issue, [])

  @spec evaluate(Issue.t(), keyword()) :: {:ok, gate_result()} | {:blocked, gate_result()}
  def evaluate(%Issue{} = issue, opts) do
    comments = Keyword.get(opts, :comments, [])
    command_runner = Keyword.get(opts, :command_runner, default_command_runner())
    text = evidence_text(issue, comments)

    with :ok <- require_low_risk(issue),
         {:ok, evidence} <- extract_evidence(text),
         {:ok, pr} <- fetch_pr(evidence.pr_url, command_runner),
         :ok <- validate_branch(issue, pr),
         :ok <- validate_label(pr),
         :ok <- validate_not_draft(pr),
         :ok <- validate_head_sha(evidence, pr),
         :ok <- validate_checks(pr),
         :ok <- validate_vercel_review_target(text),
         :ok <- merge_pr(evidence.pr_url, command_runner) do
      {:ok,
       %{
         comment: merged_comment(evidence, pr),
         head_sha: head_sha(pr),
         pr_url: evidence.pr_url,
         state: nil
       }}
    else
      {:block, state, reason} ->
        {:blocked,
         %{
           comment: blocker_comment(state, reason),
           head_sha: nil,
           pr_url: nil,
           state: state
         }}
    end
  end

  def evaluate(_issue, _opts) do
    {:blocked,
     %{
       comment: blocker_comment("Human Review", "Invalid Linear issue."),
       head_sha: nil,
       pr_url: nil,
       state: "Human Review"
     }}
  end

  defp persist_result({:ok, result}, issue_id) do
    persist_state_result(issue_id, result.comment, "Done", :ok)
  end

  defp persist_result({:blocked, result}, issue_id) do
    persist_state_result(issue_id, result.comment, result.state, {:blocked, result.state})
  end

  defp persist_state_result(issue_id, comment, state, success) do
    with :ok <- Tracker.create_comment(issue_id, comment),
         :ok <- Tracker.update_issue_state(issue_id, state) do
      success
    end
  end

  defp require_low_risk(%Issue{description: description}) do
    if Regex.match?(~r/##\s*Risk Tier\s*\n\s*low\b/i, description || "") do
      :ok
    else
      {:block, "Human Review", "Risk tier is not low; manual merge required."}
    end
  end

  defp extract_evidence(text) do
    with {:ok, pr_url} <- extract_pr_url(text),
         {:ok, sha} <- extract_sha(text) do
      {:ok, %{pr_url: pr_url, sha: sha}}
    end
  end

  defp extract_pr_url(text) when is_binary(text) do
    case Regex.run(~r/https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/pull\/\d+/, text) do
      [url | _] -> {:ok, url}
      _ -> {:block, "Human Review", "Missing PR URL in Symphony evidence."}
    end
  end

  defp extract_sha(text) when is_binary(text) do
    case Regex.run(~r/\b[0-9a-f]{40}\b/i, text) do
      [sha | _] -> {:ok, String.downcase(sha)}
      _ -> {:block, "Human Review", "Missing evidence commit SHA."}
    end
  end

  defp fetch_pr(pr_url, command_runner) when is_binary(pr_url) and is_function(command_runner, 2) do
    case command_runner.("gh", ["pr", "view", pr_url, "--json", @json_fields]) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{} = pr} -> {:ok, pr}
          {:error, _reason} -> {:block, "Human Review", "Could not parse GitHub PR metadata."}
        end

      {_output, _status} ->
        {:block, "Human Review", "Could not read GitHub PR metadata."}
    end
  end

  defp validate_branch(%Issue{identifier: identifier}, pr) when is_binary(identifier) do
    expected_prefix = "codex/#{identifier}-"

    if String.starts_with?(to_string(pr["headRefName"]), expected_prefix) do
      :ok
    else
      {:block, "Human Review", "PR branch does not match `#{expected_prefix}<short-slug>`."}
    end
  end

  defp validate_branch(_issue, _pr), do: {:block, "Human Review", "Linear issue identifier is missing."}

  defp validate_label(pr) do
    labels =
      pr
      |> Map.get("labels", [])
      |> Enum.map(&String.downcase(to_string(&1["name"])))

    if "symphony" in labels do
      :ok
    else
      {:block, "Human Review", "PR is missing `symphony` label."}
    end
  end

  defp validate_not_draft(%{"isDraft" => false}), do: :ok
  defp validate_not_draft(_pr), do: {:block, "Human Review", "PR is still draft."}

  defp validate_head_sha(%{sha: sha}, pr) do
    if sha == head_sha(pr) do
      :ok
    else
      {:block, "Human Review", "Evidence SHA does not match PR head."}
    end
  end

  defp validate_checks(pr) do
    checks = Map.get(pr, "statusCheckRollup", [])

    cond do
      checks == [] ->
        {:block, "Human Review", "No GitHub checks found on the PR."}

      check_failed?(checks) ->
        {:block, "Rework", "CI failed."}

      check_pending?(checks) ->
        {:block, "Human Review", "GitHub checks are still pending."}

      !symphony_gate_green?(checks) ->
        {:block, "Human Review", "`symphony-gate` is missing or not green."}

      true ->
        :ok
    end
  end

  defp validate_vercel_review_target(text) do
    if requires_vercel?(text) and !has_vercel_review_target?(text) do
      {:block, "Human Review", "Vercel review target is missing."}
    else
      :ok
    end
  end

  defp merge_pr(pr_url, command_runner) do
    case command_runner.("gh", ["pr", "merge", pr_url, "--squash", "--delete-branch"]) do
      {_output, 0} -> :ok
      {_output, _status} -> {:block, "Human Review", "GitHub merge command failed."}
    end
  end

  defp check_failed?(checks) do
    Enum.any?(checks, fn check ->
      check_conclusion(check) in ["FAILURE", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED"]
    end)
  end

  defp check_pending?(checks) do
    Enum.any?(checks, fn check ->
      status = String.upcase(to_string(check["status"] || check["state"]))
      status not in ["COMPLETED", "SUCCESS"]
    end)
  end

  defp symphony_gate_green?(checks) do
    Enum.any?(checks, fn check ->
      String.downcase(to_string(check["name"] || check["context"])) == "symphony-gate" and
        check_success?(check)
    end)
  end

  defp check_success?(check) do
    check_conclusion(check) in ["SUCCESS", "SKIPPED", "NEUTRAL"] or
      String.upcase(to_string(check["state"])) == "SUCCESS"
  end

  defp check_conclusion(check) do
    String.upcase(to_string(check["conclusion"] || check["state"]))
  end

  defp requires_vercel?(text), do: Regex.match?(~r/\bvercel\b/i, text)

  defp has_vercel_review_target?(text) do
    Regex.match?(~r/Review this change:\s*https?:\/\/\S*vercel\S*/i, text)
  end

  defp evidence_text(%Issue{description: description}, comments) when is_list(comments) do
    ([description || ""] ++ Enum.map(comments, &to_string/1))
    |> Enum.join("\n\n")
  end

  defp head_sha(pr), do: String.downcase(to_string(pr["headRefOid"]))

  defp merged_comment(evidence, pr) do
    """
    ## Symphony Merge Gate

    Result: merged
    PR: #{evidence.pr_url}
    Commit: #{head_sha(pr)}

    Symphony merged this issue after deterministic checks passed.
    """
    |> String.trim()
  end

  defp blocker_comment(state, reason) do
    """
    ## Symphony Merge Gate

    Result: blocked
    Returned state: #{state}
    Blocker: #{reason}
    """
    |> String.trim()
  end

  defp default_command_runner do
    Application.get_env(
      :symphony_elixir,
      :merge_gate_command_runner,
      fn command, args -> run_command(command, args) end
    )
  end

  defp run_command(command, args) do
    case System.find_executable(command) do
      nil -> {"#{command} executable not found", 127}
      executable -> System.cmd(executable, args, stderr_to_stdout: true)
    end
  end
end
