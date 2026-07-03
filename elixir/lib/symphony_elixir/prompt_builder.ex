defmodule SymphonyElixir.PromptBuilder do
  @moduledoc """
  Builds agent prompts from Linear issue data.
  """

  alias SymphonyElixir.{Config, Tracker, Workflow}

  @render_opts [strict_variables: true, strict_filters: true]
  @max_harness_comments 3
  @max_harness_comment_chars 4_000

  @spec build_prompt(SymphonyElixir.Linear.Issue.t(), keyword()) :: String.t()
  def build_prompt(issue, opts \\ []) do
    template =
      Workflow.current()
      |> prompt_template!()
      |> parse_template!()

    template
    |> Solid.render!(
      %{
        "attempt" => Keyword.get(opts, :attempt),
        "issue" => issue |> issue_context() |> to_solid_map()
      },
      @render_opts
    )
    |> IO.iodata_to_binary()
  end

  defp issue_context(issue) do
    issue
    |> Map.from_struct()
    |> Map.put(:recent_harness_context, recent_harness_context(issue))
  end

  defp recent_harness_context(%{id: issue_id}) when is_binary(issue_id) do
    case Tracker.fetch_comments(issue_id) do
      {:ok, comments} ->
        comments
        |> Enum.filter(&harness_repair_comment?/1)
        |> Enum.take(-@max_harness_comments)
        |> Enum.map_join("\n\n---\n\n", &truncate_comment/1)
        |> nil_if_blank()

      {:error, _reason} ->
        nil
    end
  end

  defp recent_harness_context(_issue), do: nil

  defp nil_if_blank(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp harness_repair_comment?(body) when is_binary(body) do
    String.contains?(body, "## Symphony Repair Packet") or
      String.contains?(body, "## Symphony Harness Blocker") or
      (String.contains?(body, "## Codex Workpad") and String.match?(body, ~r/(Branch|Draft PR|PR):/i)) or
      (String.contains?(body, "## Symphony Evidence Gate") and String.match?(body, ~r/result:\s*failed/i))
  end

  defp truncate_comment(body) when byte_size(body) <= @max_harness_comment_chars, do: body

  defp truncate_comment(body), do: String.slice(body, 0, @max_harness_comment_chars) <> "\n[truncated]"

  defp prompt_template!({:ok, %{prompt_template: prompt}}), do: default_prompt(prompt)

  defp prompt_template!({:error, reason}) do
    raise RuntimeError, "workflow_unavailable: #{inspect(reason)}"
  end

  defp parse_template!(prompt) when is_binary(prompt) do
    Solid.parse!(prompt)
  rescue
    error ->
      reraise %RuntimeError{
                message: "template_parse_error: #{Exception.message(error)} template=#{inspect(prompt)}"
              },
              __STACKTRACE__
  end

  defp to_solid_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), to_solid_value(value)} end)
  end

  defp to_solid_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp to_solid_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp to_solid_value(%Date{} = value), do: Date.to_iso8601(value)
  defp to_solid_value(%Time{} = value), do: Time.to_iso8601(value)
  defp to_solid_value(%_{} = value), do: value |> Map.from_struct() |> to_solid_map()
  defp to_solid_value(value) when is_map(value), do: to_solid_map(value)
  defp to_solid_value(value) when is_list(value), do: Enum.map(value, &to_solid_value/1)
  defp to_solid_value(value), do: value

  defp default_prompt(prompt) when is_binary(prompt) do
    if String.trim(prompt) == "" do
      Config.workflow_prompt()
    else
      prompt
    end
  end
end
