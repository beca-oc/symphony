defmodule SymphonyElixir.Config do
  @moduledoc """
  Runtime configuration loaded from `WORKFLOW.md`.
  """

  alias SymphonyElixir.Config.Schema
  alias SymphonyElixir.Workflow

  @missing_required_environment_marker "__SYMPHONY_MISSING_REQUIRED_ENV__:"

  @default_prompt_template """
  You are working on a Linear issue.

  Identifier: {{ issue.identifier }}
  Title: {{ issue.title }}

  Body:
  {% if issue.description %}
  {{ issue.description }}
  {% else %}
  No description provided.
  {% endif %}
  """

  @type codex_runtime_settings :: %{
          approval_policy: String.t() | map(),
          thread_sandbox: String.t(),
          turn_sandbox_policy: map()
        }

  @spec settings() :: {:ok, Schema.t()} | {:error, term()}
  def settings do
    case Workflow.current() do
      {:ok, %{config: config}} when is_map(config) ->
        Schema.parse(config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec settings!() :: Schema.t()
  def settings! do
    case settings() do
      {:ok, settings} ->
        settings

      {:error, reason} ->
        raise ArgumentError, message: format_config_error(reason)
    end
  end

  @spec max_concurrent_agents_for_state(term()) :: pos_integer()
  def max_concurrent_agents_for_state(state_name) when is_binary(state_name) do
    config = settings!()

    Map.get(
      config.agent.max_concurrent_agents_by_state,
      Schema.normalize_issue_state(state_name),
      config.agent.max_concurrent_agents
    )
  end

  def max_concurrent_agents_for_state(_state_name), do: settings!().agent.max_concurrent_agents

  @spec codex_turn_sandbox_policy(Path.t() | nil) :: map()
  def codex_turn_sandbox_policy(workspace \\ nil) do
    case Schema.resolve_runtime_turn_sandbox_policy(settings!(), workspace) do
      {:ok, policy} ->
        policy

      {:error, reason} ->
        raise ArgumentError, message: "Invalid codex turn sandbox policy: #{inspect(reason)}"
    end
  end

  @spec workflow_prompt() :: String.t()
  def workflow_prompt do
    case Workflow.current() do
      {:ok, %{prompt_template: prompt}} ->
        if String.trim(prompt) == "", do: @default_prompt_template, else: prompt

      _ ->
        @default_prompt_template
    end
  end

  @spec server_port() :: non_neg_integer() | nil
  def server_port do
    case Application.get_env(:symphony_elixir, :server_port_override) do
      port when is_integer(port) and port >= 0 -> port
      _ -> settings!().server.port
    end
  end

  @spec validate!() :: :ok | {:error, term()}
  def validate! do
    with {:ok, settings} <- settings() do
      validate_semantics(settings)
    end
  end

  @spec codex_runtime_settings(Path.t() | nil, keyword()) ::
          {:ok, codex_runtime_settings()} | {:error, term()}
  def codex_runtime_settings(workspace \\ nil, opts \\ []) do
    with {:ok, settings} <- settings() do
      with {:ok, turn_sandbox_policy} <-
             Schema.resolve_runtime_turn_sandbox_policy(settings, workspace, opts) do
        {:ok,
         %{
           approval_policy: settings.codex.approval_policy,
           thread_sandbox: settings.codex.thread_sandbox,
           turn_sandbox_policy: turn_sandbox_policy
         }}
      end
    end
  end

  @spec missing_required_environment(Schema.t() | nil) :: [String.t()]
  def missing_required_environment(settings \\ nil) do
    settings = settings || settings!()

    Enum.filter(settings.codex.required_environment, fn name ->
      case System.get_env(name) do
        nil -> true
        "" -> true
        _value -> false
      end
    end)
  end

  @spec codex_local_port_env(Schema.t() | nil) :: [{charlist(), charlist() | false}]
  def codex_local_port_env(settings \\ nil) do
    settings = settings || settings!()
    allowlist = MapSet.new(settings.codex.environment_allowlist)
    current_env = System.get_env()

    unset_env =
      current_env
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(allowlist, &1))
      |> Enum.map(&{String.to_charlist(&1), false})

    preserved_env =
      settings.codex.environment_allowlist
      |> Enum.flat_map(fn name ->
        case Map.fetch(current_env, name) do
          {:ok, value} -> [{String.to_charlist(name), String.to_charlist(value)}]
          :error -> []
        end
      end)

    unset_env ++ preserved_env
  end

  @spec codex_remote_exec_command(String.t(), Schema.t() | nil) :: String.t()
  def codex_remote_exec_command(command, settings \\ nil) when is_binary(command) do
    settings = settings || settings!()

    [
      remote_required_environment_guard(settings.codex.required_environment),
      remote_env_exec(command, settings.codex.environment_allowlist)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" && ")
  end

  @spec parse_missing_required_environment_marker(String.t()) ::
          {:ok, [String.t()]} | :error
  def parse_missing_required_environment_marker(line) when is_binary(line) do
    trimmed = String.trim(line)

    if String.starts_with?(trimmed, @missing_required_environment_marker) do
      names =
        trimmed
        |> String.replace_prefix(@missing_required_environment_marker, "")
        |> String.split(",", trim: true)

      {:ok, names}
    else
      :error
    end
  end

  defp validate_semantics(settings) do
    cond do
      is_nil(settings.tracker.kind) ->
        {:error, :missing_tracker_kind}

      settings.tracker.kind not in ["linear", "memory"] ->
        {:error, {:unsupported_tracker_kind, settings.tracker.kind}}

      settings.tracker.kind == "linear" and not is_binary(settings.tracker.api_key) ->
        {:error, :missing_linear_api_token}

      settings.tracker.kind == "linear" and not is_binary(settings.tracker.project_slug) ->
        {:error, :missing_linear_project_slug}

      true ->
        :ok
    end
  end

  defp remote_required_environment_guard([]), do: ""

  defp remote_required_environment_guard(names) when is_list(names) do
    checks =
      Enum.map_join(names, " ", fn name ->
        "[ -z \"${#{name}-}\" ] && missing=\"${missing}${missing:+,}#{name}\";"
      end)

    "missing=''; #{checks} if [ -n \"$missing\" ]; then printf '%s%s\\n' '#{@missing_required_environment_marker}' \"$missing\"; exit 78; fi"
  end

  defp remote_env_exec(command, allowlist) do
    assignments =
      allowlist
      |> Enum.map_join(" ", fn name -> "#{name}=\"${#{name}-}\"" end)

    case assignments do
      "" -> "exec env -i #{command}"
      _ -> "exec env -i #{assignments} #{command}"
    end
  end

  defp format_config_error(reason) do
    case reason do
      {:invalid_workflow_config, message} ->
        "Invalid WORKFLOW.md config: #{message}"

      {:missing_workflow_file, path, raw_reason} ->
        "Missing WORKFLOW.md at #{path}: #{inspect(raw_reason)}"

      {:workflow_parse_error, raw_reason} ->
        "Failed to parse WORKFLOW.md: #{inspect(raw_reason)}"

      :workflow_front_matter_not_a_map ->
        "Failed to parse WORKFLOW.md: workflow front matter must decode to a map"

      other ->
        "Invalid WORKFLOW.md config: #{inspect(other)}"
    end
  end
end
