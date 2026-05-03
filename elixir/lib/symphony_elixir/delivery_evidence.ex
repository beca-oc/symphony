defmodule SymphonyElixir.DeliveryEvidence do
  @moduledoc """
  Deterministic post-agent evidence gate for Symphony-managed engineering work.
  """

  require Logger

  alias SymphonyElixir.{Config, Tracker}
  alias SymphonyElixir.Linear.Issue

  @workpad_heading "## Codex Workpad"
  @validation_words ~w(validation validated verify verified test tests ci passed pass exit)

  @type evidence :: %{
          branch: String.t(),
          commit_sha: String.t(),
          pr_url: String.t() | nil,
          deployment_url: String.t() | nil,
          workpad: String.t()
        }

  @type report :: %{failures: [String.t()], evidence: map()}

  @spec required?() :: boolean()
  def required? do
    Config.settings!().validation.evidence_required == true
  end

  @spec finalize_issue(Issue.t(), Path.t() | nil, keyword()) :: :ok | {:error, term()}
  def finalize_issue(%Issue{} = issue, workspace, opts \\ []) do
    if required?() do
      case evaluation_for_issue(issue, workspace, opts) do
        {:ok, evidence} -> approve_issue(issue, evidence)
        {:error, report} -> block_issue(issue, report)
        {:fetch_error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp evaluation_for_issue(issue, workspace, opts) do
    case comments_for_issue(issue, opts) do
      {:ok, comments} ->
        pull_request = pull_request_for_workspace(workspace, opts)
        evaluate(issue, workspace, comments: comments, pull_request: pull_request)

      {:error, reason} ->
        {:fetch_error, reason}
    end
  end

  defp approve_issue(%Issue{id: issue_id}, evidence) do
    case Tracker.create_comment(issue_id, success_comment(evidence)) do
      :ok -> Tracker.update_issue_state(issue_id, "Human Review")
      {:error, reason} -> {:error, reason}
    end
  end

  defp block_issue(%Issue{id: issue_id}, report) do
    case Tracker.create_comment(issue_id, blocker_comment(report)) do
      :ok ->
        case Tracker.update_issue_state(issue_id, "Rework") do
          :ok -> {:error, {:evidence_gate_failed, report.failures}}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec evaluate(Issue.t(), Path.t() | nil, keyword()) ::
          {:ok, evidence()} | {:error, report()}
  def evaluate(%Issue{} = issue, workspace, opts \\ []) do
    comments = Keyword.get(opts, :comments, [])
    pull_request = Keyword.get(opts, :pull_request)
    workpad = find_workpad(comments)
    branch = git_value(workspace, ["rev-parse", "--abbrev-ref", "HEAD"])
    commit_sha = git_value(workspace, ["rev-parse", "HEAD"])
    pr_url = pull_request_url(pull_request)
    deployment_url = deployment_url(comments, pull_request)

    evidence = %{
      branch: branch,
      commit_sha: commit_sha,
      pr_url: pr_url,
      deployment_url: deployment_url,
      workpad: workpad
    }

    failures =
      []
      |> require_workpad(workpad)
      |> require_branch(issue, branch)
      |> require_commit(commit_sha)
      |> require_pull_request(issue, pull_request, commit_sha)
      |> require_validation(workpad)
      |> require_deployment(deployment_url)
      |> Enum.reverse()

    case failures do
      [] -> {:ok, evidence}
      _ -> {:error, %{failures: failures, evidence: evidence}}
    end
  end

  defp comments_for_issue(%Issue{id: issue_id}, opts) when is_binary(issue_id) do
    case Keyword.fetch(opts, :comments) do
      {:ok, comments} -> {:ok, comments}
      :error -> Tracker.fetch_comments(issue_id)
    end
  end

  defp comments_for_issue(_issue, opts), do: {:ok, Keyword.get(opts, :comments, [])}

  defp pull_request_for_workspace(workspace, opts) do
    case Keyword.fetch(opts, :pull_request) do
      {:ok, pull_request} -> pull_request
      :error -> fetch_pull_request(workspace)
    end
  end

  defp fetch_pull_request(workspace) do
    settings = Config.settings!()
    repo = settings.repo.github_repo

    with repo when is_binary(repo) and repo != "" <- repo,
         branch when is_binary(branch) and branch != "" <- git_value(workspace, ["rev-parse", "--abbrev-ref", "HEAD"]),
         {json, 0} <-
           System.cmd(
             "gh",
             [
               "pr",
               "list",
               "--repo",
               repo,
               "--head",
               branch,
               "--state",
               "open",
               "--json",
               "url,isDraft,headRefOid,title,body,labels,statusCheckRollup"
             ],
             stderr_to_stdout: true
           ),
         {:ok, [pull_request | _]} <- Jason.decode(json) do
      pull_request
    else
      reason ->
        Logger.debug("Delivery evidence PR lookup did not find an open PR: #{inspect(reason)}")
        nil
    end
  end

  defp git_value(workspace, args) when is_binary(workspace) do
    case System.cmd("git", ["-C", workspace | args], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp git_value(_workspace, _args), do: nil

  defp find_workpad(comments) when is_list(comments) do
    Enum.find(comments, fn
      body when is_binary(body) -> String.contains?(body, @workpad_heading)
      _ -> false
    end)
  end

  defp find_workpad(_comments), do: nil

  defp require_workpad(failures, workpad) when is_binary(workpad), do: failures
  defp require_workpad(failures, _workpad), do: ["missing Linear workpad comment headed ## Codex Workpad" | failures]

  defp require_branch(failures, %Issue{identifier: identifier}, branch)
       when is_binary(identifier) and is_binary(branch) do
    expected_prefix = "codex/#{identifier}"

    if String.starts_with?(branch, expected_prefix) do
      failures
    else
      ["branch does not start with #{expected_prefix}" | failures]
    end
  end

  defp require_branch(failures, _issue, branch) when is_binary(branch), do: failures
  defp require_branch(failures, _issue, _branch), do: ["missing git branch evidence" | failures]

  defp require_commit(failures, commit_sha) when is_binary(commit_sha) and byte_size(commit_sha) == 40,
    do: failures

  defp require_commit(failures, _commit_sha), do: ["missing final commit SHA" | failures]

  defp require_pull_request(failures, issue, nil, _commit_sha),
    do: ["missing draft pull request" | maybe_require_pr_reference(failures, issue, nil)]

  defp require_pull_request(failures, issue, pull_request, commit_sha) when is_map(pull_request) do
    failures
    |> require_draft_pr(pull_request)
    |> require_symphony_label(pull_request)
    |> require_pr_commit(pull_request, commit_sha)
    |> maybe_require_pr_reference(issue, pull_request)
  end

  defp require_draft_pr(failures, %{"isDraft" => true}), do: failures
  defp require_draft_pr(failures, %{isDraft: true}), do: failures
  defp require_draft_pr(failures, _pull_request), do: ["pull request is not draft" | failures]

  defp require_symphony_label(failures, pull_request) do
    labels =
      pull_request
      |> map_get(:labels)
      |> List.wrap()
      |> Enum.map(&label_name/1)

    if Enum.any?(labels, &(String.downcase(&1) == "symphony")) do
      failures
    else
      ["pull request is missing symphony label" | failures]
    end
  end

  defp require_pr_commit(failures, _pull_request, nil), do: failures

  defp require_pr_commit(failures, pull_request, commit_sha) do
    case map_get(pull_request, :headRefOid) do
      ^commit_sha -> failures
      nil -> failures
      _ -> ["pull request head commit does not match workspace HEAD" | failures]
    end
  end

  defp maybe_require_pr_reference(failures, %Issue{identifier: identifier}, pull_request)
       when is_binary(identifier) and is_map(pull_request) do
    text = "#{map_get(pull_request, :title)}\n#{map_get(pull_request, :body)}"

    if String.contains?(text, identifier) do
      failures
    else
      ["pull request does not reference #{identifier}" | failures]
    end
  end

  defp maybe_require_pr_reference(failures, _issue, _pull_request), do: failures

  defp require_validation(failures, workpad) when is_binary(workpad) do
    normalized = String.downcase(workpad)

    if Enum.any?(@validation_words, &String.contains?(normalized, &1)) do
      failures
    else
      ["missing validation command/result evidence" | failures]
    end
  end

  defp require_validation(failures, _workpad), do: ["missing validation command/result evidence" | failures]

  defp require_deployment(failures, deployment_url) do
    if Config.settings!().validation.deploy_evidence == "none" or is_binary(deployment_url) do
      failures
    else
      ["missing deployment/check evidence" | failures]
    end
  end

  defp deployment_url(comments, pull_request) do
    deployment_url_from_comments(comments) || deployment_url_from_pr(pull_request)
  end

  defp deployment_url_from_comments(comments) when is_list(comments) do
    comments
    |> Enum.find_value(fn
      body when is_binary(body) ->
        body
        |> String.split("\n")
        |> Enum.find_value(&deployment_url_from_line/1)

      _ ->
        nil
    end)
  end

  defp deployment_url_from_comments(_comments), do: nil

  defp deployment_url_from_line(line) when is_binary(line) do
    normalized = String.downcase(line)

    if String.contains?(normalized, ["deploy", "preview", "vercel", "check"]) do
      Regex.run(~r/https?:\/\/\S+/, line)
      |> case do
        [url | _] -> String.trim_trailing(url, ".,)")
        _ -> nil
      end
    end
  end

  defp deployment_url_from_pr(nil), do: nil

  defp deployment_url_from_pr(pull_request) when is_map(pull_request) do
    pull_request
    |> map_get(:statusCheckRollup)
    |> List.wrap()
    |> Enum.find_value(fn
      check when is_map(check) ->
        map_get(check, :targetUrl) || map_get(check, :detailsUrl)

      _ ->
        nil
    end)
  end

  defp pull_request_url(nil), do: nil
  defp pull_request_url(pull_request) when is_map(pull_request), do: map_get(pull_request, :url)

  defp label_name(%{"name" => name}) when is_binary(name), do: name
  defp label_name(%{name: name}) when is_binary(name), do: name
  defp label_name(name) when is_binary(name), do: name
  defp label_name(_label), do: ""

  defp map_get(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, Atom.to_string(key)) || Map.get(map, key)
  end

  defp success_comment(evidence) do
    """
    ## Symphony Evidence Gate

    Result: passed
    Branch: #{evidence.branch}
    Commit: #{evidence.commit_sha}
    PR: #{evidence.pr_url || "n/a"}
    Deployment/Check: #{evidence.deployment_url || "n/a"}

    Symphony moved this issue to Human Review after verifying required delivery evidence.
    """
  end

  defp blocker_comment(report) do
    failures =
      report.failures
      |> Enum.map_join("\n", &("- " <> &1))

    """
    ## Symphony Harness Blocker

    Gate: delivery evidence
    Result: failed

    #{failures}

    Symphony moved this issue to Rework because required delivery evidence is incomplete.
    """
  end
end
