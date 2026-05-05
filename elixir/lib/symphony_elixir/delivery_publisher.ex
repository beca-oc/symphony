defmodule SymphonyElixir.DeliveryPublisher do
  @moduledoc """
  Symphony-owned publisher for post-agent delivery bookkeeping.

  Codex should leave a committed local branch. This module handles the
  deterministic GitHub/Linear evidence path so those tool calls do not need to
  be part of the agent conversation.
  """

  require Logger

  alias SymphonyElixir.{Config, Tracker}
  alias SymphonyElixir.Linear.Issue

  @type evidence :: %{
          branch: String.t(),
          commit_sha: String.t(),
          pr_url: String.t(),
          deployment_url: String.t() | nil,
          validation_command: String.t(),
          validation_output: String.t()
        }

  @spec publish(Issue.t(), Path.t()) :: {:ok, evidence()} | {:error, term()}
  def publish(%Issue{} = issue, workspace) when is_binary(workspace) do
    settings = Config.settings!()

    with {:ok, repo} <- repo(settings),
         {:ok, branch} <- git_value(workspace, ["rev-parse", "--abbrev-ref", "HEAD"]),
         :ok <- verify_branch(issue, branch),
         {:ok, commit_sha} <- git_value(workspace, ["rev-parse", "HEAD"]),
         :ok <- verify_clean_commit(commit_sha),
         {:ok, validation_command, validation_output} <- run_validation(workspace, settings),
         :ok <- git_push(workspace, branch),
         {:ok, pr_url} <- create_or_find_pr(issue, settings, repo, branch),
         :ok <- ensure_symphony_label(repo),
         :ok <- add_symphony_label(repo, pr_url),
         {:ok, pull_request} <- poll_pr_with_evidence(repo, pr_url, settings) do
      deployment_url = deployment_url(pull_request)

      evidence = %{
        branch: branch,
        commit_sha: commit_sha,
        pr_url: pr_url,
        deployment_url: deployment_url,
        validation_command: validation_command,
        validation_output: validation_output
      }

      with :ok <- Tracker.create_comment(issue.id, workpad_comment(issue, workspace, evidence)) do
        {:ok, evidence}
      end
    else
      {:error, reason} = error ->
        Logger.warning("Delivery publisher failed for #{issue.identifier}: #{inspect(reason)}")
        maybe_create_blocker_workpad(issue, workspace, reason)
        error

      reason ->
        Logger.warning("Delivery publisher failed for #{issue.identifier}: #{inspect(reason)}")
        maybe_create_blocker_workpad(issue, workspace, reason)
        {:error, reason}
    end
  end

  def publish(_issue, _workspace), do: {:error, :invalid_publish_inputs}

  defp repo(%{repo: %{github_repo: repo}}) when is_binary(repo) and repo != "", do: {:ok, repo}
  defp repo(_settings), do: {:error, :missing_repo_github_repo}

  defp verify_branch(%Issue{identifier: identifier}, branch)
       when is_binary(identifier) and is_binary(branch) do
    if String.starts_with?(branch, "codex/#{identifier}") do
      :ok
    else
      {:error, {:unexpected_branch, branch, "codex/#{identifier}"}}
    end
  end

  defp verify_branch(_issue, _branch), do: :ok

  defp verify_clean_commit(commit_sha) when is_binary(commit_sha) and byte_size(commit_sha) == 40, do: :ok
  defp verify_clean_commit(commit_sha), do: {:error, {:invalid_commit_sha, commit_sha}}

  defp run_validation(workspace, settings) do
    command = validation_command(settings)

    if is_binary(command) and String.trim(command) != "" do
      case System.cmd("sh", ["-lc", command], cd: workspace, stderr_to_stdout: true) do
        {output, 0} -> {:ok, command, truncate_output(output)}
        {output, status} -> {:error, {:validation_failed, status, truncate_output(output)}}
      end
    else
      {:ok, "not configured", "No validation.fast command configured; Symphony recorded local commit evidence only."}
    end
  end

  defp validation_command(%{validation: %{fast: fast}}) when is_binary(fast) and fast != "", do: fast
  defp validation_command(_settings), do: nil

  defp git_push(workspace, branch) do
    case System.cmd("git", ["-C", workspace, "push", "-u", "origin", branch], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:git_push_failed, status, truncate_output(output)}}
    end
  end

  defp create_or_find_pr(issue, settings, repo, branch) do
    body_path = write_pr_body!(issue)
    default_branch = default_branch(settings)

    args = [
      "pr",
      "create",
      "--draft",
      "--repo",
      repo,
      "--base",
      default_branch,
      "--head",
      branch,
      "--title",
      pr_title(issue),
      "--body-file",
      body_path
    ]

    try do
      case System.cmd("gh", args, stderr_to_stdout: true) do
        {output, 0} -> pr_url_from_output(output)
        {output, _status} -> find_existing_pr(repo, branch, output)
      end
    after
      File.rm(body_path)
    end
  end

  defp write_pr_body!(issue) do
    path = Path.join(System.tmp_dir!(), "symphony-pr-body-#{System.unique_integer([:positive, :monotonic])}.md")

    File.write!(path, """
    Refs #{issue.identifier}

    Linear: #{issue.url || "n/a"}

    This draft PR was published by Symphony after Codex completed the local branch work.
    """)

    path
  end

  defp find_existing_pr(repo, branch, original_output) do
    case System.cmd(
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
             "url"
           ],
           stderr_to_stdout: true
         ) do
      {json, 0} ->
        case Jason.decode(json) do
          {:ok, [%{"url" => url} | _]} when is_binary(url) -> {:ok, url}
          _ -> {:error, {:gh_pr_create_failed, truncate_output(original_output)}}
        end

      {output, status} ->
        {:error, {:gh_pr_create_failed, status, truncate_output(original_output <> "\n" <> output)}}
    end
  end

  defp pr_url_from_output(output) do
    case Regex.run(~r/https:\/\/github\.com\/\S+\/pull\/\d+/, output) do
      [url | _] -> {:ok, String.trim(url)}
      _ -> {:error, {:missing_pr_url, truncate_output(output)}}
    end
  end

  defp ensure_symphony_label(repo) do
    System.cmd(
      "gh",
      [
        "label",
        "create",
        "symphony",
        "--repo",
        repo,
        "--description",
        "Symphony automation",
        "--color",
        "6f42c1",
        "--force"
      ],
      stderr_to_stdout: true
    )

    :ok
  end

  defp add_symphony_label(repo, pr_url) do
    with {:ok, number} <- pr_number(pr_url) do
      System.cmd(
        "gh",
        [
          "api",
          "--method",
          "POST",
          "repos/#{repo}/issues/#{number}/labels",
          "-f",
          "labels[]=symphony"
        ],
        stderr_to_stdout: true
      )
    end
    |> case do
      {_output, 0} -> :ok
      {:error, reason} -> {:error, reason}
      {output, status} -> {:error, {:gh_label_failed, status, truncate_output(output)}}
    end
  end

  defp pr_number(pr_url) when is_binary(pr_url) do
    case Regex.run(~r/\/pull\/(\d+)/, pr_url) do
      [_match, number] -> {:ok, number}
      _ -> {:error, {:missing_pr_number, pr_url}}
    end
  end

  defp pr_number(pr_url), do: {:error, {:missing_pr_number, pr_url}}

  defp poll_pr(repo, pr_url) do
    case System.cmd(
           "gh",
           [
             "pr",
             "view",
             pr_url,
             "--repo",
             repo,
             "--json",
             "url,isDraft,headRefOid,title,body,labels,statusCheckRollup"
           ],
           stderr_to_stdout: true
         ) do
      {json, 0} ->
        case Jason.decode(json) do
          {:ok, pull_request} when is_map(pull_request) -> {:ok, pull_request}
          _ -> {:error, {:gh_pr_view_decode_failed, truncate_output(json)}}
        end

      {output, status} ->
        {:error, {:gh_pr_view_failed, status, truncate_output(output)}}
    end
  end

  defp poll_pr_with_evidence(repo, pr_url, settings) do
    deadline = System.monotonic_time(:millisecond) + evidence_poll_timeout_ms(settings)
    poll_pr_with_evidence(repo, pr_url, evidence_required?(settings), settings.evidence_gate, deadline, nil)
  end

  defp poll_pr_with_evidence(repo, pr_url, evidence_required?, evidence_gate, deadline, last_pull_request) do
    case poll_pr(repo, pr_url) do
      {:ok, pull_request} ->
        case pr_evidence_state(pull_request, evidence_required?, evidence_gate) do
          :ready ->
            {:ok, pull_request}

          {:failed, failures} ->
            {:error, {:pr_checks_failed, failures}}

          {:pending, failures} ->
            if System.monotonic_time(:millisecond) >= deadline do
              {:error, {:pr_checks_timeout, failures}}
            else
              Process.sleep(evidence_poll_interval_ms())
              poll_pr_with_evidence(repo, pr_url, evidence_required?, evidence_gate, deadline, pull_request)
            end
        end

      {:error, _reason} = error ->
        case last_pull_request do
          nil -> error
          pull_request -> {:ok, pull_request}
        end
    end
  end

  defp evidence_required?(%{validation: %{deploy_evidence: deploy_evidence}}),
    do: deploy_evidence in ["vercel", "github_checks"]

  defp evidence_required?(_settings), do: false

  defp pr_evidence_state(_pull_request, false, _evidence_gate), do: :ready

  defp pr_evidence_state(pull_request, true, evidence_gate) when is_map(pull_request) do
    checks =
      pull_request
      |> Map.get("statusCheckRollup", [])
      |> List.wrap()

    failures =
      (checks
       |> Enum.map(&check_failure(&1, evidence_gate))
       |> Enum.reject(&is_nil/1)) ++ missing_required_check_failures(checks, evidence_gate)

    cond do
      not is_binary(deployment_url(pull_request)) ->
        {:pending, ["missing deployment/check evidence"]}

      Enum.any?(failures, &String.contains?(&1, "failed")) ->
        {:failed, failures}

      Enum.any?(failures, &String.contains?(&1, "skipped")) ->
        {:failed, failures}

      failures != [] ->
        {:pending, failures}

      true ->
        :ready
    end
  end

  defp pr_evidence_state(_pull_request, true, _evidence_gate), do: {:pending, ["missing pull request evidence"]}

  defp check_failure(check, evidence_gate) when is_map(check) do
    name = check_name(check)

    cond do
      configured_required_checks?(evidence_gate) and not check_configured?(name, evidence_gate.github_required_checks) ->
        nil

      check_configured?(name, evidence_gate.github_optional_checks) ->
        nil

      check_state(check) == :skipped and check_configured?(name, evidence_gate.allow_skipped_checks) ->
        nil

      true ->
        case check_state(check) do
          :success -> nil
          :pending -> "required PR check still pending: #{name}"
          :skipped -> "required PR check skipped: #{name}"
          :failed -> "required PR check failed: #{name}"
        end
    end
  end

  defp check_failure(_check, _evidence_gate), do: nil

  defp configured_required_checks?(%{github_required_checks: checks}) when is_list(checks), do: checks != []
  defp configured_required_checks?(_evidence_gate), do: false

  defp missing_required_check_failures(checks, evidence_gate) do
    present_names = Enum.map(checks, &check_name/1)

    evidence_gate.github_required_checks
    |> Enum.reject(&check_configured?(&1, present_names))
    |> Enum.map(&("missing required PR check: " <> &1))
  end

  defp check_configured?(name, configured_names) when is_binary(name) and is_list(configured_names) do
    Enum.any?(configured_names, &(&1 == name))
  end

  defp check_configured?(_name, _configured_names), do: false

  defp check_state(check) do
    case String.upcase(to_string(Map.get(check, "__typename"))) do
      "STATUSCONTEXT" -> status_context_state(check)
      _ -> check_run_state(check)
    end
  end

  defp check_run_state(check) do
    status = check |> Map.get("status") |> to_string() |> String.upcase()
    conclusion = check |> Map.get("conclusion") |> to_string() |> String.upcase()

    cond do
      status != "COMPLETED" -> :pending
      conclusion == "SUCCESS" -> :success
      conclusion == "SKIPPED" -> :skipped
      true -> :failed
    end
  end

  defp status_context_state(check) do
    case check |> Map.get("state") |> to_string() |> String.upcase() do
      "SUCCESS" -> :success
      "FAILURE" -> :failed
      "ERROR" -> :failed
      _ -> :pending
    end
  end

  defp check_name(check) do
    Map.get(check, "name") || Map.get(check, "context") || "unknown"
  end

  defp evidence_poll_timeout_ms(settings) do
    cond do
      is_integer(settings.evidence_gate.timeout_seconds) ->
        settings.evidence_gate.timeout_seconds * 1_000

      true ->
        Application.get_env(:symphony_elixir, :delivery_publisher_poll_timeout_ms, 60_000)
    end
  end

  defp evidence_poll_interval_ms do
    Application.get_env(:symphony_elixir, :delivery_publisher_poll_interval_ms, 2_000)
  end

  defp deployment_url(pull_request) when is_map(pull_request) do
    pull_request
    |> Map.get("statusCheckRollup", [])
    |> List.wrap()
    |> Enum.find_value(fn
      %{"targetUrl" => url} when is_binary(url) and url != "" -> url
      %{"detailsUrl" => url} when is_binary(url) and url != "" -> url
      _ -> nil
    end)
  end

  defp workpad_comment(issue, workspace, evidence) do
    """
    ## Codex Workpad

    - Linear: #{issue.url || issue.identifier}
    - Workspace: `#{workspace}`
    - Branch: `#{evidence.branch}`
    - Draft PR: #{evidence.pr_url}
    - PR label `symphony`: present
    - Final commit SHA: `#{evidence.commit_sha}`
    - Validation: `#{evidence.validation_command}` -> pass
    - Validation output:
      ```
      #{String.trim(evidence.validation_output)}
      ```
    - Deployment/Check: #{evidence.deployment_url || "n/a"}

    ### Notes / Blockers
    - _none_
    """
  end

  defp maybe_create_blocker_workpad(%Issue{id: issue_id} = issue, workspace, reason) when is_binary(issue_id) do
    branch = git_value(workspace, ["rev-parse", "--abbrev-ref", "HEAD"]) |> value_or("unknown")
    commit = git_value(workspace, ["rev-parse", "HEAD"]) |> value_or("unknown")

    Tracker.create_comment(issue_id, """
    ## Codex Workpad

    - Linear: #{issue.url || issue.identifier}
    - Workspace: `#{workspace || "unknown"}`
    - Branch: `#{branch}`
    - Final commit SHA: `#{commit}`
    - Validation: blocked before complete publication

    ### Blocker
    - Symphony publisher failed: `#{inspect(reason)}`
    """)
  end

  defp maybe_create_blocker_workpad(_issue, _workspace, _reason), do: :ok

  defp git_value(workspace, args) when is_binary(workspace) do
    case System.cmd("git", ["-C", workspace | args], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, status} -> {:error, {:git_failed, args, status, truncate_output(output)}}
    end
  end

  defp git_value(_workspace, _args), do: {:error, :missing_workspace}

  defp value_or({:ok, value}, _fallback), do: value
  defp value_or(_error, fallback), do: fallback

  defp default_branch(%{repo: %{default_branch: branch}}) when is_binary(branch) and branch != "", do: branch
  defp default_branch(_settings), do: "main"

  defp pr_title(%Issue{identifier: identifier, title: title}) when is_binary(identifier) and is_binary(title),
    do: "#{identifier}: #{title}"

  defp pr_title(%Issue{identifier: identifier}) when is_binary(identifier), do: identifier
  defp pr_title(_issue), do: "Symphony delivery"

  defp truncate_output(output, max_bytes \\ 4_000) do
    text = IO.iodata_to_binary(output || "")

    if byte_size(text) <= max_bytes do
      text
    else
      binary_part(text, 0, max_bytes) <> "\n... (truncated)"
    end
  end
end
