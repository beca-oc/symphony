defmodule SymphonyElixir.TicketReadiness do
  @moduledoc """
  Mechanical readiness checks for Linear issues before Symphony claims work.
  """

  alias SymphonyElixir.Config.Schema
  alias SymphonyElixir.Linear.Issue

  @required_sections [
    "Goal",
    "Repo",
    "Risk Tier",
    "Scope",
    "Acceptance",
    "Validation",
    "Deploy / Check Evidence"
  ]

  @exit_policy_sections ["Exit Policy", "Failure Handling"]

  @spec validate(Issue.t(), Schema.t()) :: :ok | {:error, [String.t()]}
  def validate(%Issue{} = issue, %Schema{} = settings) do
    sections = parse_sections(issue.description)

    failures =
      []
      |> require_sections(sections)
      |> require_exit_policy(sections)
      |> require_repo_contract(sections, settings)
      |> require_scope_boundaries(sections)
      |> require_branch_rule(issue, sections)

    case Enum.reverse(failures) do
      [] -> :ok
      failures -> {:error, failures}
    end
  end

  def validate(_issue, _settings), do: {:error, ["Linear issue is unavailable."]}

  @spec start_context(Issue.t(), Schema.t()) :: String.t()
  def start_context(%Issue{} = issue, %Schema{} = _settings) do
    sections = parse_sections(issue.description)
    validation_command = section_body(sections, "Validation")
    repo = section_body(sections, "Repo")
    evidence = section_body(sections, "Deploy / Check Evidence")

    """
    Symphony readiness: passed
    Setup: passed
    Repo: #{one_line(repo) || "from Linear Repo section"}
    Branch rule: #{branch_rule(issue)}
    Validation command: #{one_line(validation_command) || "from Linear Validation section"}
    Evidence: #{one_line(evidence) || "from Linear Deploy / Check Evidence section"}
    Boundary: Symphony owns validation, push, PR publication, Linear evidence, and Linear state transitions. Codex edits and commits only.
    """
    |> String.trim()
  end

  def start_context(_issue, _settings), do: ""

  @spec blocker_comment(Issue.t(), [String.t()]) :: String.t()
  def blocker_comment(%Issue{} = issue, failures) when is_list(failures) do
    """
    ## Symphony Readiness Blocker

    Symphony did not claim #{issue.identifier || issue.id || "this issue"} because the Linear ticket is not mechanically ready.

    Missing or invalid fields:
    #{Enum.map_join(failures, "\n", &("- " <> &1))}

    Repair the Linear issue using the existing Symphony ticket contract before moving it back into a dispatchable state.
    """
    |> String.trim()
  end

  defp require_sections(failures, sections) do
    Enum.reduce(@required_sections, failures, fn section, failures_acc ->
      if present_section?(sections, section), do: failures_acc, else: ["#{section} section is missing." | failures_acc]
    end)
  end

  defp require_exit_policy(failures, sections) do
    if Enum.any?(@exit_policy_sections, &present_section?(sections, &1)) do
      failures
    else
      ["Exit Policy section is missing." | failures]
    end
  end

  defp require_repo_contract(failures, sections, settings) do
    case section_body(sections, "Repo") do
      nil ->
        failures

      body ->
        failures
        |> require_repo_name(body, settings)
        |> require_base_branch(body, settings)
    end
  end

  defp require_repo_name(failures, body, settings) do
    cond do
      contains_token?(body, repo_name(settings)) ->
        failures

      contains_token?(body, repo_github_repo(settings)) ->
        failures

      Regex.match?(~r/\brepo\s*:/i, body) ->
        failures

      true ->
        ["Repo section must name the repository." | failures]
    end
  end

  defp require_base_branch(failures, body, settings) do
    cond do
      contains_token?(body, repo_default_branch(settings)) ->
        failures

      Regex.match?(~r/\bbase(?:\s+branch)?\s*:/i, body) ->
        failures

      true ->
        ["Repo must name a base branch." | failures]
    end
  end

  defp require_scope_boundaries(failures, sections) do
    case section_body(sections, "Scope") do
      nil ->
        failures

      body ->
        if Regex.match?(~r/\binclude\b/i, body) and Regex.match?(~r/\bexclude\b/i, body) do
          failures
        else
          ["Scope section must name Include and Exclude boundaries." | failures]
        end
    end
  end

  defp require_branch_rule(failures, %Issue{} = issue, sections) do
    branch = issue.branch_name || ""
    identifier = issue.identifier || ""
    body = Enum.map_join(sections, "\n", fn {_heading, section_body} -> section_body end)

    cond do
      identifier == "" ->
        ["Linear issue identifier is missing." | failures]

      valid_branch_rule?(branch, identifier) ->
        failures

      valid_branch_rule?(body, identifier) ->
        failures

      true ->
        ["Branch rule must be codex/#{identifier}-<short-slug>." | failures]
    end
  end

  defp valid_branch_rule?(value, identifier) when is_binary(value) and is_binary(identifier) do
    Regex.match?(~r/codex\/#{Regex.escape(identifier)}-[a-z0-9][a-z0-9-]*/i, value)
  end

  defp parse_sections(description) when is_binary(description) do
    Regex.split(~r/^##\s+/m, description)
    |> Enum.drop(1)
    |> Enum.reduce(%{}, fn section, acc ->
      [heading | body_lines] = String.split(section, "\n")
      heading = normalize_heading(heading)
      body = body_lines |> Enum.join("\n") |> String.trim()
      Map.put(acc, heading, body)
    end)
  end

  defp parse_sections(_description), do: %{}

  defp present_section?(sections, heading) do
    case section_body(sections, heading) do
      nil -> false
      body -> String.trim(body) != ""
    end
  end

  defp section_body(sections, heading), do: Map.get(sections, normalize_heading(heading))

  defp normalize_heading(heading) when is_binary(heading) do
    heading
    |> String.trim()
    |> String.trim_trailing("#")
    |> String.trim()
    |> String.downcase()
  end

  defp contains_token?(_body, value) when value in [nil, ""], do: false

  defp contains_token?(body, value) when is_binary(body) and is_binary(value) do
    String.contains?(String.downcase(body), String.downcase(value))
  end

  defp one_line(value) when is_binary(value) do
    value
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("; ")
  end

  defp one_line(_value), do: nil

  defp repo_name(settings), do: setting_in(settings, [:repo, :name])
  defp repo_github_repo(settings), do: setting_in(settings, [:repo, :github_repo])
  defp repo_default_branch(settings), do: setting_in(settings, [:repo, :default_branch])

  defp setting_in(value, []), do: value

  defp setting_in(value, [key | rest]) when is_map(value) do
    value
    |> Map.get(key)
    |> setting_in(rest)
  end

  defp setting_in(_value, _path), do: nil

  defp branch_rule(%Issue{identifier: identifier}) when is_binary(identifier), do: "codex/#{identifier}-<short-slug>"
  defp branch_rule(_issue), do: "codex/<issue-id>-<short-slug>"
end
