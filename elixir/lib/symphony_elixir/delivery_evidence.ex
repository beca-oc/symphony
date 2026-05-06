defmodule SymphonyElixir.DeliveryEvidence do
  @moduledoc """
  Deterministic post-agent evidence gate for Symphony-managed engineering work.
  """

  require Logger

  alias SymphonyElixir.{Config, Tracker}
  alias SymphonyElixir.Linear.Issue

  @workpad_heading "## Codex Workpad"
  @validation_result_pattern ~r/(validation|validate|verify|test|ci).*(pass|passed|success|succeeded|exit\s*0|0)/i

  @type evidence :: %{
          branch: String.t(),
          commit_sha: String.t(),
          pr_url: String.t() | nil,
          deployment_url: String.t() | nil,
          workpad: String.t(),
          checker: map()
        }

  @type report :: %{failures: [String.t()], evidence: map()}

  @spec required?() :: boolean()
  def required? do
    Config.settings!().validation.evidence_required == true
  end

  @spec finalize_issue(Issue.t(), Path.t() | nil, keyword()) :: :ok | {:error, term()}
  def finalize_issue(%Issue{} = issue, workspace, opts \\ []) do
    if required?() do
      case finalize_issue_with_report(issue, workspace, opts) do
        {:ok, _report} -> :ok
        {:error, %{failures: failures}} -> {:error, {:evidence_gate_failed, failures}}
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  @spec finalize_issue_with_report(Issue.t(), Path.t() | nil, keyword()) ::
          {:ok, map()} | {:error, report()} | {:error, term()}
  def finalize_issue_with_report(%Issue{} = issue, workspace, opts \\ []) do
    if required?() do
      case poll_evaluation_for_issue(issue, workspace, opts) do
        {:ok, evidence} -> approve_issue_with_report(issue, evidence)
        {:error, report} -> block_issue(issue, report)
        {:fetch_error, reason} -> {:error, reason}
      end
    else
      {:ok,
       %{
         evidence: %{},
         checker: %{passed: true, failure_bucket: :none, failures: [], required_checks: [], observed_checks: []}
       }}
    end
  end

  @spec failure_bucket(term()) :: atom()
  def failure_bucket({:evidence_gate_failed, failures}) when is_list(failures), do: failure_bucket(failures)
  def failure_bucket({:validation_failed, _status, _output}), do: :validation_failed
  def failure_bucket({:pr_checks_failed, _failures}), do: :ci_failed
  def failure_bucket({:pr_checks_timeout, _failures}), do: :ci_timeout
  def failure_bucket({:git_push_failed, _status, _output}), do: :git_push_failed
  def failure_bucket({:gh_pr_create_failed, _output}), do: :missing_pr
  def failure_bucket({:gh_pr_create_failed, _status, _output}), do: :missing_pr
  def failure_bucket({:gh_label_failed, _status, _output}), do: :missing_label

  def failure_bucket(failures) when is_list(failures) do
    text =
      failures
      |> Enum.map_join("\n", &to_string/1)
      |> String.downcase()

    cond do
      String.contains?(text, "missing linear workpad") -> :missing_workpad
      String.contains?(text, "branch does not start") -> :branch_mismatch
      String.contains?(text, "missing git branch") -> :branch_mismatch
      String.contains?(text, "missing final commit sha") -> :missing_pushed_sha
      String.contains?(text, "head commit does not match") -> :pushed_sha_mismatch
      String.contains?(text, "missing draft pull request") -> :missing_pr
      String.contains?(text, "not draft") -> :missing_pr
      String.contains?(text, "missing symphony label") -> :missing_label
      String.contains?(text, "missing validation") -> :missing_validation
      String.contains?(text, "missing deployment/check evidence") -> :missing_deploy_evidence
      String.contains?(text, "merge conflicts") -> :merge_conflict
      String.contains?(text, "check failed") -> :ci_failed
      String.contains?(text, "check skipped") -> :ci_failed
      String.contains?(text, "check still pending") -> :ci_pending
      String.contains?(text, "missing required pr check") -> :ci_pending
      true -> :evidence_gate
    end
  end

  def failure_bucket(reason) when is_atom(reason), do: reason
  def failure_bucket(_reason), do: :unknown

  defp evaluation_for_issue(issue, workspace, opts) do
    case comments_for_issue(issue, opts) do
      {:ok, comments} ->
        pull_request = pull_request_for_workspace(workspace, opts)
        evaluate(issue, workspace, comments: comments, pull_request: pull_request)

      {:error, reason} ->
        {:fetch_error, reason}
    end
  end

  defp approve_issue_with_report(%Issue{id: issue_id}, evidence) do
    case create_comment_once(issue_id, "## Symphony Evidence Gate", success_comment(evidence)) do
      :ok ->
        case Tracker.update_issue_state(issue_id, "Human Review") do
          :ok -> {:ok, %{evidence: evidence, checker: evidence.checker}}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp block_issue(%Issue{id: issue_id}, report) do
    case create_comment_once(issue_id, "## Symphony Harness Blocker", blocker_comment(report)) do
      :ok ->
        case Tracker.update_issue_state(issue_id, "Rework") do
          :ok -> {:error, report}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_comment_once(issue_id, heading, body) when is_binary(issue_id) and is_binary(heading) and is_binary(body) do
    case Tracker.fetch_comments(issue_id) do
      {:ok, comments} ->
        if Enum.any?(comments, &(is_binary(&1) and String.contains?(&1, heading))) do
          :ok
        else
          Tracker.create_comment(issue_id, body)
        end

      {:error, _reason} ->
        Tracker.create_comment(issue_id, body)
    end
  end

  defp poll_evaluation_for_issue(issue, workspace, opts) do
    deadline = System.monotonic_time(:millisecond) + poll_timeout_ms()
    poll_evaluation_for_issue(issue, workspace, opts, deadline, nil)
  end

  defp poll_evaluation_for_issue(issue, workspace, opts, deadline, last_report) do
    case evaluation_for_issue(issue, workspace, opts) do
      {:error, report} = error ->
        if pending_report?(report) and System.monotonic_time(:millisecond) < deadline do
          Process.sleep(poll_interval_ms())
          poll_evaluation_for_issue(issue, workspace, opts, deadline, report)
        else
          error
        end

      {:fetch_error, _reason} = error ->
        case last_report do
          nil -> error
          report -> {:error, report}
        end

      result ->
        result
    end
  end

  defp pending_report?(%{failures: failures}) when is_list(failures) do
    failure_bucket(failures) in [:ci_pending, :missing_deploy_evidence]
  end

  defp pending_report?(_report), do: false

  defp poll_timeout_ms do
    Application.get_env(:symphony_elixir, :delivery_evidence_poll_timeout_ms, 60_000)
  end

  defp poll_interval_ms do
    Application.get_env(:symphony_elixir, :delivery_evidence_poll_interval_ms, 2_000)
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
      workpad: workpad,
      checker: %{}
    }

    failures =
      []
      |> require_workpad(workpad)
      |> require_branch(issue, branch)
      |> require_commit(commit_sha)
      |> require_pull_request(issue, pull_request, commit_sha)
      |> require_validation(workpad)
      |> require_check_or_deployment_evidence(deployment_url)
      |> require_pr_checks(pull_request)
      |> Enum.reverse()

    evidence = %{evidence | checker: checker_report(pull_request, failures)}

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
      {:ok, pull_request} ->
        pull_request

      :error ->
        case Keyword.fetch(opts, :pull_request_fetcher) do
          {:ok, fetcher} when is_function(fetcher, 0) -> fetcher.()
          _ -> fetch_pull_request(workspace)
        end
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
               "url,isDraft,headRefOid,title,body,labels,statusCheckRollup,mergeable"
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
    |> require_mergeable_pr(pull_request)
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

  defp require_mergeable_pr(failures, pull_request) do
    case map_get(pull_request, :mergeable) do
      value when value in ["CONFLICTING", :CONFLICTING, "conflicting", :conflicting] ->
        ["pull request has merge conflicts" | failures]

      _ ->
        failures
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
    if Regex.match?(@validation_result_pattern, workpad) do
      failures
    else
      ["missing validation command/result evidence" | failures]
    end
  end

  defp require_validation(failures, _workpad), do: ["missing validation command/result evidence" | failures]

  defp require_check_or_deployment_evidence(failures, deployment_url) do
    if check_or_deployment_evidence_required?() and !is_binary(deployment_url) do
      ["missing deployment/check evidence" | failures]
    else
      failures
    end
  end

  defp require_pr_checks(failures, pull_request) do
    if check_or_deployment_evidence_required?() do
      gate = Config.settings!().evidence_gate
      checks = status_check_rollup(pull_request)

      checks
      |> Enum.reduce(failures, &require_pr_check(&1, &2, gate))
      |> require_configured_checks(checks, gate)
    else
      failures
    end
  end

  defp check_or_deployment_evidence_required? do
    settings = Config.settings!()
    settings.validation.deploy_evidence != "none" or configured_required_checks?(settings.evidence_gate)
  end

  defp status_check_rollup(pull_request) when is_map(pull_request) do
    pull_request
    |> map_get(:statusCheckRollup)
    |> List.wrap()
  end

  defp status_check_rollup(_pull_request), do: []

  defp require_pr_check(check, failures, gate) when is_map(check) do
    name = check_name(check)

    cond do
      check_configured?(name, gate.github_optional_checks) ->
        failures

      check_state(check) == :skipped and check_configured?(name, gate.allow_skipped_checks) ->
        failures

      require_all_checks?(gate) ->
        require_check_state(check, name, failures)

      configured_required_checks?(gate) and not check_configured?(name, gate.github_required_checks) ->
        failures

      true ->
        require_check_state(check, name, failures)
    end
  end

  defp require_pr_check(_check, failures, _gate), do: failures

  defp require_check_state(check, name, failures) do
    case check_state(check) do
      :success -> failures
      :pending -> ["required PR check still pending: #{name}" | failures]
      :skipped -> ["required PR check skipped: #{name}" | failures]
      :failed -> ["required PR check failed: #{name}" | failures]
    end
  end

  defp configured_required_checks?(%{github_required_checks: checks}) when is_list(checks), do: checks != []
  defp configured_required_checks?(_gate), do: false

  defp require_all_checks?(%{require_all_checks: true}), do: true
  defp require_all_checks?(_gate), do: false

  defp require_configured_checks(failures, checks, gate) do
    present_names = Enum.map(checks, &check_name/1)

    gate.github_required_checks
    |> Enum.reject(&check_configured?(&1, present_names))
    |> Enum.reduce(failures, fn name, acc -> ["missing required PR check: #{name}" | acc] end)
  end

  defp check_configured?(name, configured_names) when is_binary(name) and is_list(configured_names) do
    Enum.any?(configured_names, &(&1 == name))
  end

  defp check_configured?(_name, _configured_names), do: false

  defp check_state(check) do
    case String.upcase(to_string(map_get(check, :__typename))) do
      "STATUSCONTEXT" -> status_context_state(check)
      _ -> check_run_state(check)
    end
  end

  defp check_run_state(check) do
    status = check |> map_get(:status) |> to_string() |> String.upcase()
    conclusion = check |> map_get(:conclusion) |> to_string() |> String.upcase()

    cond do
      status != "COMPLETED" -> :pending
      conclusion == "SUCCESS" -> :success
      conclusion == "SKIPPED" -> :skipped
      true -> :failed
    end
  end

  defp status_context_state(check) do
    case check |> map_get(:state) |> to_string() |> String.upcase() do
      "SUCCESS" -> :success
      "FAILURE" -> :failed
      "ERROR" -> :failed
      _ -> :pending
    end
  end

  defp check_name(check) do
    map_get(check, :name) || map_get(check, :context) || "unknown"
  end

  defp checker_report(pull_request, failures) do
    %{
      passed: failures == [],
      failure_bucket: if(failures == [], do: :none, else: failure_bucket(failures)),
      failures: failures,
      required_checks: required_check_names(),
      observed_checks: observed_check_summaries(pull_request)
    }
  end

  defp required_check_names do
    case Config.settings!().evidence_gate.github_required_checks do
      checks when is_list(checks) -> checks
      _ -> []
    end
  end

  defp observed_check_summaries(pull_request) do
    pull_request
    |> status_check_rollup()
    |> Enum.map(fn check ->
      %{
        name: check_name(check),
        state: check_state(check),
        url: check_url(check)
      }
    end)
  end

  defp check_url(check) when is_map(check) do
    map_get(check, :targetUrl) || map_get(check, :detailsUrl)
  end

  defp check_url(_check), do: nil

  defp deployment_url(comments, pull_request) do
    deployment_url_from_pr(pull_request) || deployment_url_from_comments(comments)
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

    if Regex.match?(~r/^\s*[-*]?\s*(deployment|deploy|preview|vercel|check|checks|ci|status)(\/deploy)?\s*:/, normalized) do
      Regex.run(~r/https?:\/\/\S+/, line)
      |> case do
        [url | _] -> String.trim_trailing(url, ".,)")
        _ -> nil
      end
    end
  end

  defp deployment_url_from_pr(nil), do: nil

  defp deployment_url_from_pr(pull_request) when is_map(pull_request) do
    checks =
      pull_request
      |> map_get(:statusCheckRollup)
      |> List.wrap()

    required_check_url(checks) || successful_check_url(checks) || first_check_url(checks)
  end

  defp required_check_url(checks) when is_list(checks) do
    required = required_check_names()

    checks
    |> Enum.find_value(fn check ->
      if check_configured?(check_name(check), required), do: check_url(check)
    end)
  end

  defp successful_check_url(checks) when is_list(checks) do
    Enum.find_value(checks, fn check ->
      if check_state(check) == :success, do: check_url(check)
    end)
  end

  defp first_check_url(checks) when is_list(checks) do
    Enum.find_value(checks, &check_url/1)
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

    ### Measurement
    - PR URL: #{evidence.pr_url || "n/a"}
    - Check/Deploy URL: #{evidence.deployment_url || "n/a"}
    - Failure bucket: none

    ### Checker
    - Required checks: #{checker_required_checks(evidence.checker)}
    - Observed checks:
    #{checker_observed_checks(evidence.checker)}

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
    Failure bucket: #{failure_bucket(report.failures)}

    #{failures}

    ### Checker
    - Required checks: #{checker_required_checks(report.evidence.checker)}
    - Observed checks:
    #{checker_observed_checks(report.evidence.checker)}

    Symphony moved this issue to Rework because required delivery evidence is incomplete.
    """
  end

  defp checker_required_checks(%{required_checks: []}), do: "none configured"

  defp checker_required_checks(%{required_checks: checks}) when is_list(checks) do
    Enum.join(checks, ", ")
  end

  defp checker_required_checks(_checker), do: "none configured"

  defp checker_observed_checks(%{observed_checks: []}), do: "    - none reported"

  defp checker_observed_checks(%{observed_checks: checks}) when is_list(checks) do
    checks
    |> Enum.map(fn check ->
      url = if is_binary(check.url), do: " (#{check.url})", else: ""
      "    - #{check.name}: #{check.state}#{url}"
    end)
    |> Enum.join("\n")
  end

  defp checker_observed_checks(_checker), do: "    - none reported"
end
