defmodule SymphonyElixir.DeliveryPublisherTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.DeliveryPublisher

  test "publisher turns a local committed branch into PR and Linear workpad evidence" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-publisher-#{System.unique_integer([:positive])}"
      )

    try do
      workspace = Path.join(test_root, "workspace")
      File.mkdir_p!(workspace)
      File.write!(Path.join(workspace, "README.md"), "# publisher\n")
      System.cmd("git", ["-C", workspace, "init", "-b", "codex/BEC-99-marker"])
      System.cmd("git", ["-C", workspace, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", workspace, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", workspace, "add", "README.md"])
      System.cmd("git", ["-C", workspace, "commit", "-m", "publisher evidence"])
      System.cmd("git", ["-C", workspace, "remote", "add", "origin", "https://github.com/Subconscious-ai/example.git"])

      {sha, 0} = System.cmd("git", ["-C", workspace, "rev-parse", "HEAD"])
      sha = String.trim(sha)

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        repo_github_repo: "Subconscious-ai/example",
        repo_default_branch: "main",
        validation_fast: "printf 'fast validation passed\\n'",
        validation_deploy_evidence: "vercel",
        validation_evidence_required: true
      )

      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      issue = %Issue{
        id: "issue-publish",
        identifier: "BEC-99",
        title: "Publish delivery",
        state: "In Progress",
        url: "https://linear.app/example/issue/BEC-99/publish-delivery"
      }

      with_fake_gh_and_git(fn log_path ->
        assert {:ok, evidence} = DeliveryPublisher.publish(issue, workspace)

        assert evidence.branch == "codex/BEC-99-marker"
        assert evidence.commit_sha == sha
        assert evidence.pr_url == "https://github.com/Subconscious-ai/example/pull/99"
        assert evidence.deployment_url == "https://vercel.com/example/preview"

        assert_receive {:memory_tracker_comment, "issue-publish", body}, 500
        assert body =~ "## Codex Workpad"
        assert body =~ "Draft PR: https://github.com/Subconscious-ai/example/pull/99"
        assert body =~ "Final commit SHA: `#{sha}`"
        assert body =~ "Validation: `printf 'fast validation passed"
        assert body =~ "fast validation passed"
        assert body =~ "Deployment/Check: https://vercel.com/example/preview"

        log = File.read!(log_path)
        assert log =~ "push -u origin codex/BEC-99-marker"
        assert log =~ "gh pr create --draft"
        assert log =~ "gh api --method POST repos/Subconscious-ai/example/issues/99/labels"
        assert log =~ "labels[]=symphony"
        assert log =~ "gh pr view https://github.com/Subconscious-ai/example/pull/99"
        assert log =~ "statusCheckRollup,mergeable"
        assert log =~ "--json"
      end)
    after
      File.rm_rf(test_root)
    end
  end

  test "publisher waits for terminal green GitHub check evidence after PR creation" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-publisher-checks-#{System.unique_integer([:positive])}"
      )

    counter_path = Path.join(test_root, "gh-view-count")

    old_timeout = Application.get_env(:symphony_elixir, :delivery_publisher_poll_timeout_ms)
    old_interval = Application.get_env(:symphony_elixir, :delivery_publisher_poll_interval_ms)

    try do
      Application.put_env(:symphony_elixir, :delivery_publisher_poll_timeout_ms, 250)
      Application.put_env(:symphony_elixir, :delivery_publisher_poll_interval_ms, 1)

      workspace = Path.join(test_root, "workspace")
      File.mkdir_p!(workspace)
      File.write!(Path.join(workspace, "README.md"), "# publisher\n")
      System.cmd("git", ["-C", workspace, "init", "-b", "codex/BEC-99-marker"])
      System.cmd("git", ["-C", workspace, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", workspace, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", workspace, "add", "README.md"])
      System.cmd("git", ["-C", workspace, "commit", "-m", "publisher evidence"])
      System.cmd("git", ["-C", workspace, "remote", "add", "origin", "https://github.com/Subconscious-ai/example.git"])

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        repo_github_repo: "Subconscious-ai/example",
        repo_default_branch: "main",
        validation_fast: "printf 'fast validation passed\\n'",
        validation_deploy_evidence: "github_checks",
        validation_evidence_required: true
      )

      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      issue = %Issue{
        id: "issue-publish",
        identifier: "BEC-99",
        title: "Publish delivery",
        state: "In Progress",
        url: "https://linear.app/example/issue/BEC-99/publish-delivery"
      }

      with_fake_gh_and_git(fn log_path ->
        System.put_env("GH_VIEW_COUNTER", counter_path)

        assert {:ok, evidence} = DeliveryPublisher.publish(issue, workspace)
        assert evidence.deployment_url == "https://github.com/Subconscious-ai/example/actions/runs/99/job/100"

        assert_receive {:memory_tracker_comment, "issue-publish", body}, 500
        assert body =~ "Deployment/Check: https://github.com/Subconscious-ai/example/actions/runs/99/job/100"

        log = File.read!(log_path)
        assert length(Regex.scan(~r/gh pr view https:\/\/github\.com\/Subconscious-ai\/example\/pull\/99/, log)) >= 3
      end)
    after
      restore_app_env(:delivery_publisher_poll_timeout_ms, old_timeout)
      restore_app_env(:delivery_publisher_poll_interval_ms, old_interval)
      System.delete_env("GH_VIEW_COUNTER")
      File.rm_rf(test_root)
    end
  end

  test "publisher only waits for configured required GitHub checks" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-publisher-required-check-#{System.unique_integer([:positive])}"
      )

    try do
      workspace = Path.join(test_root, "workspace")
      File.mkdir_p!(workspace)
      File.write!(Path.join(workspace, "README.md"), "# publisher\n")
      System.cmd("git", ["-C", workspace, "init", "-b", "codex/BEC-99-marker"])
      System.cmd("git", ["-C", workspace, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", workspace, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", workspace, "add", "README.md"])
      System.cmd("git", ["-C", workspace, "commit", "-m", "publisher evidence"])
      System.cmd("git", ["-C", workspace, "remote", "add", "origin", "https://github.com/Subconscious-ai/example.git"])

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        repo_github_repo: "Subconscious-ai/example",
        repo_default_branch: "main",
        validation_fast: "printf 'fast validation passed\\n'",
        validation_deploy_evidence: "github_checks",
        validation_evidence_required: true,
        evidence_gate_github_required_checks: ["symphony-gate"]
      )

      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      issue = %Issue{
        id: "issue-publish",
        identifier: "BEC-99",
        title: "Publish delivery",
        state: "In Progress",
        url: "https://linear.app/example/issue/BEC-99/publish-delivery"
      }

      with_fake_gh_and_git(fn _log_path ->
        System.put_env("GH_VIEW_REQUIRED_GATE", "1")

        assert {:ok, evidence} = DeliveryPublisher.publish(issue, workspace)
        assert evidence.deployment_url == "https://github.com/Subconscious-ai/example/actions/runs/99/job/100"
      end)
    after
      System.delete_env("GH_VIEW_REQUIRED_GATE")
      File.rm_rf(test_root)
    end
  end

  test "publisher waits for all non-optional GitHub checks when configured" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-publisher-all-checks-#{System.unique_integer([:positive])}"
      )

    counter_path = Path.join(test_root, "gh-view-count")

    old_timeout = Application.get_env(:symphony_elixir, :delivery_publisher_poll_timeout_ms)
    old_interval = Application.get_env(:symphony_elixir, :delivery_publisher_poll_interval_ms)

    try do
      Application.put_env(:symphony_elixir, :delivery_publisher_poll_timeout_ms, 250)
      Application.put_env(:symphony_elixir, :delivery_publisher_poll_interval_ms, 1)

      workspace = Path.join(test_root, "workspace")
      File.mkdir_p!(workspace)
      File.write!(Path.join(workspace, "README.md"), "# publisher\n")
      System.cmd("git", ["-C", workspace, "init", "-b", "codex/BEC-102-marker"])
      System.cmd("git", ["-C", workspace, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", workspace, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", workspace, "add", "README.md"])
      System.cmd("git", ["-C", workspace, "commit", "-m", "publisher all checks evidence"])
      System.cmd("git", ["-C", workspace, "remote", "add", "origin", "https://github.com/Subconscious-ai/example.git"])

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        repo_github_repo: "Subconscious-ai/example",
        repo_default_branch: "main",
        validation_fast: "printf 'fast validation passed\\n'",
        validation_deploy_evidence: "github_checks",
        validation_evidence_required: true,
        evidence_gate_github_required_checks: ["symphony-gate"],
        evidence_gate_github_optional_checks: ["CodeRabbit"],
        evidence_gate_require_all_checks: true
      )

      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      issue = %Issue{
        id: "issue-publish",
        identifier: "BEC-102",
        title: "Publish all-check delivery",
        state: "In Progress",
        url: "https://linear.app/example/issue/BEC-102/publish-all-check-delivery"
      }

      with_fake_gh_and_git(fn log_path ->
        System.put_env("GH_VIEW_ALL_CHECKS", "1")
        System.put_env("GH_VIEW_COUNTER", counter_path)

        assert {:ok, evidence} = DeliveryPublisher.publish(issue, workspace)
        assert evidence.deployment_url == "https://github.com/Subconscious-ai/example/actions/runs/99/job/100"

        log = File.read!(log_path)
        assert length(Regex.scan(~r/gh pr view https:\/\/github\.com\/Subconscious-ai\/example\/pull\/99/, log)) >= 3
      end)
    after
      restore_app_env(:delivery_publisher_poll_timeout_ms, old_timeout)
      restore_app_env(:delivery_publisher_poll_interval_ms, old_interval)
      System.delete_env("GH_VIEW_ALL_CHECKS")
      System.delete_env("GH_VIEW_COUNTER")
      File.rm_rf(test_root)
    end
  end

  test "publisher keeps polling when a transient failed status appears while checks are pending" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-publisher-transient-failure-#{System.unique_integer([:positive])}"
      )

    counter_path = Path.join(test_root, "gh-view-count")

    old_timeout = Application.get_env(:symphony_elixir, :delivery_publisher_poll_timeout_ms)
    old_interval = Application.get_env(:symphony_elixir, :delivery_publisher_poll_interval_ms)

    try do
      Application.put_env(:symphony_elixir, :delivery_publisher_poll_timeout_ms, 250)
      Application.put_env(:symphony_elixir, :delivery_publisher_poll_interval_ms, 1)

      workspace = Path.join(test_root, "workspace")
      File.mkdir_p!(workspace)
      File.write!(Path.join(workspace, "README.md"), "# publisher\n")
      System.cmd("git", ["-C", workspace, "init", "-b", "codex/BEC-103-marker"])
      System.cmd("git", ["-C", workspace, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", workspace, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", workspace, "add", "README.md"])
      System.cmd("git", ["-C", workspace, "commit", "-m", "publisher transient check evidence"])
      System.cmd("git", ["-C", workspace, "remote", "add", "origin", "https://github.com/Subconscious-ai/example.git"])

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        repo_github_repo: "Subconscious-ai/example",
        repo_default_branch: "main",
        validation_fast: "printf 'fast validation passed\\n'",
        validation_deploy_evidence: "github_checks",
        validation_evidence_required: true,
        evidence_gate_github_required_checks: ["symphony-gate"],
        evidence_gate_require_all_checks: true
      )

      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      issue = %Issue{
        id: "issue-publish",
        identifier: "BEC-103",
        title: "Publish transient check delivery",
        state: "In Progress",
        url: "https://linear.app/example/issue/BEC-103/publish-transient-check-delivery"
      }

      with_fake_gh_and_git(fn log_path ->
        System.put_env("GH_VIEW_TRANSIENT_FAILURE", "1")
        System.put_env("GH_VIEW_COUNTER", counter_path)

        assert {:ok, evidence} = DeliveryPublisher.publish(issue, workspace)
        assert evidence.deployment_url == "https://github.com/Subconscious-ai/example/actions/runs/99/job/100"

        log = File.read!(log_path)
        assert length(Regex.scan(~r/gh pr view https:\/\/github\.com\/Subconscious-ai\/example\/pull\/99/, log)) >= 3
      end)
    after
      restore_app_env(:delivery_publisher_poll_timeout_ms, old_timeout)
      restore_app_env(:delivery_publisher_poll_interval_ms, old_interval)
      System.delete_env("GH_VIEW_TRANSIENT_FAILURE")
      System.delete_env("GH_VIEW_COUNTER")
      File.rm_rf(test_root)
    end
  end

  test "publisher does not duplicate an existing Codex workpad on resume" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-publisher-resume-#{System.unique_integer([:positive])}"
      )

    try do
      workspace = Path.join(test_root, "workspace")
      File.mkdir_p!(workspace)
      File.write!(Path.join(workspace, "README.md"), "# publisher\n")
      System.cmd("git", ["-C", workspace, "init", "-b", "codex/BEC-101-marker"])
      System.cmd("git", ["-C", workspace, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", workspace, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", workspace, "add", "README.md"])
      System.cmd("git", ["-C", workspace, "commit", "-m", "publisher resume evidence"])
      System.cmd("git", ["-C", workspace, "remote", "add", "origin", "https://github.com/Subconscious-ai/example.git"])

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        repo_github_repo: "Subconscious-ai/example",
        repo_default_branch: "main",
        validation_fast: "printf 'fast validation passed\\n'",
        validation_deploy_evidence: "none",
        validation_evidence_required: true,
        evidence_gate_github_required_checks: ["symphony-gate"]
      )

      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())
      Application.put_env(:symphony_elixir, :memory_tracker_comments, %{"issue-publish" => ["## Codex Workpad\n\nExisting evidence"]})

      issue = %Issue{
        id: "issue-publish",
        identifier: "BEC-101",
        title: "Resume publishing",
        state: "In Progress",
        url: "https://linear.app/example/issue/BEC-101/resume-publishing"
      }

      with_fake_gh_and_git(fn _log_path ->
        System.put_env("GH_VIEW_REQUIRED_GATE", "1")

        assert {:ok, _evidence} = DeliveryPublisher.publish(issue, workspace)
        refute_receive {:memory_tracker_comment, "issue-publish", _body}, 100
      end)
    after
      System.delete_env("GH_VIEW_REQUIRED_GATE")
      Application.delete_env(:symphony_elixir, :memory_tracker_comments)
      File.rm_rf(test_root)
    end
  end

  test "publisher waits for configured required check when deploy evidence is none" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-delivery-publisher-ci-only-#{System.unique_integer([:positive])}"
      )

    try do
      workspace = Path.join(test_root, "workspace")
      File.mkdir_p!(workspace)
      File.write!(Path.join(workspace, "README.md"), "# publisher\n")
      System.cmd("git", ["-C", workspace, "init", "-b", "codex/BEC-100-marker"])
      System.cmd("git", ["-C", workspace, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", workspace, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", workspace, "add", "README.md"])
      System.cmd("git", ["-C", workspace, "commit", "-m", "publisher ci evidence"])
      System.cmd("git", ["-C", workspace, "remote", "add", "origin", "https://github.com/Subconscious-ai/example.git"])

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        repo_github_repo: "Subconscious-ai/example",
        repo_default_branch: "main",
        validation_fast: "printf 'fast validation passed\\n'",
        validation_deploy_evidence: "none",
        validation_evidence_required: true,
        evidence_gate_github_required_checks: ["symphony-gate"]
      )

      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      issue = %Issue{
        id: "issue-publish",
        identifier: "BEC-100",
        title: "Publish CI-only delivery",
        state: "In Progress",
        url: "https://linear.app/example/issue/BEC-100/publish-ci-delivery"
      }

      with_fake_gh_and_git(fn _log_path ->
        System.put_env("GH_VIEW_REQUIRED_GATE", "1")

        assert {:ok, evidence} = DeliveryPublisher.publish(issue, workspace)
        assert evidence.deployment_url == "https://github.com/Subconscious-ai/example/actions/runs/99/job/100"

        assert_receive {:memory_tracker_comment, "issue-publish", body}, 500
        assert body =~ "Deployment/Check: https://github.com/Subconscious-ai/example/actions/runs/99/job/100"
      end)
    after
      System.delete_env("GH_VIEW_REQUIRED_GATE")
      File.rm_rf(test_root)
    end
  end

  defp with_fake_gh_and_git(fun) do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "delivery-publisher-test-#{unique}")
    bin_dir = Path.join(root, "bin")
    log_path = Path.join(root, "commands.log")
    real_git = System.find_executable("git")

    try do
      File.mkdir_p!(bin_dir)
      File.write!(log_path, "")

      File.write!(Path.join(bin_dir, "git"), fake_git_script())
      File.chmod!(Path.join(bin_dir, "git"), 0o755)
      File.write!(Path.join(bin_dir, "gh"), fake_gh_script())
      File.chmod!(Path.join(bin_dir, "gh"), 0o755)

      original_path = System.get_env("PATH") || ""

      with_env(
        %{
          "PATH" => Enum.join([bin_dir, original_path], ":"),
          "COMMAND_LOG" => log_path,
          "REAL_GIT" => real_git
        },
        fn -> fun.(log_path) end
      )
    after
      File.rm_rf!(root)
    end
  end

  defp with_env(env, fun) do
    old = Map.new(env, fn {key, _value} -> {key, System.get_env(key)} end)

    try do
      Enum.each(env, fn {key, value} -> System.put_env(key, value) end)
      fun.()
    after
      Enum.each(old, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end

  defp fake_git_script do
    """
    #!/bin/sh
    printf 'git %s\\n' "$*" >> "$COMMAND_LOG"

    if [ "$1" = "-C" ]; then
      shift
      workspace="$1"
      shift

      if [ "$1" = "push" ]; then
        exit 0
      fi

      exec "$REAL_GIT" -C "$workspace" "$@"
    fi

    exec "$REAL_GIT" "$@"
    """
  end

  defp fake_gh_script do
    """
    #!/bin/sh
    printf 'gh %s\\n' "$*" >> "$COMMAND_LOG"

    if [ "$1" = "label" ] && [ "$2" = "create" ]; then
      exit 0
    fi

    if [ "$1" = "pr" ] && [ "$2" = "create" ]; then
      printf 'https://github.com/Subconscious-ai/example/pull/99\\n'
      exit 0
    fi

    if [ "$1" = "api" ]; then
      exit 0
    fi

    if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
      if [ -n "$GH_VIEW_TRANSIENT_FAILURE" ]; then
        count=0
        if [ -f "$GH_VIEW_COUNTER" ]; then
          count="$(cat "$GH_VIEW_COUNTER")"
        fi
        count=$((count + 1))
        printf '%s' "$count" > "$GH_VIEW_COUNTER"

        if [ "$count" -lt 3 ]; then
          cat <<'JSON'
    {"url":"https://github.com/Subconscious-ai/example/pull/99","isDraft":true,"headRefOid":"ignored","labels":[{"name":"symphony"}],"statusCheckRollup":[{"__typename":"CheckRun","name":"symphony-gate","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":"https://github.com/Subconscious-ai/example/actions/runs/99/job/100"},{"__typename":"CheckRun","name":"Analyze (actions)","status":"IN_PROGRESS","detailsUrl":"https://github.com/Subconscious-ai/example/actions/runs/99/job/101"},{"__typename":"StatusContext","context":"CodeQL","state":"FAILURE"}]}
    JSON
          exit 0
        fi

        cat <<'JSON'
    {"url":"https://github.com/Subconscious-ai/example/pull/99","isDraft":true,"headRefOid":"ignored","labels":[{"name":"symphony"}],"statusCheckRollup":[{"__typename":"CheckRun","name":"symphony-gate","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":"https://github.com/Subconscious-ai/example/actions/runs/99/job/100"},{"__typename":"CheckRun","name":"Analyze (actions)","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":"https://github.com/Subconscious-ai/example/actions/runs/99/job/101"},{"__typename":"StatusContext","context":"CodeQL","state":"SUCCESS"}]}
    JSON
        exit 0
      fi

      if [ -n "$GH_VIEW_ALL_CHECKS" ]; then
        count=0
        if [ -f "$GH_VIEW_COUNTER" ]; then
          count="$(cat "$GH_VIEW_COUNTER")"
        fi
        count=$((count + 1))
        printf '%s' "$count" > "$GH_VIEW_COUNTER"

        if [ "$count" -lt 3 ]; then
          cat <<'JSON'
    {"url":"https://github.com/Subconscious-ai/example/pull/99","isDraft":true,"headRefOid":"ignored","labels":[{"name":"symphony"}],"statusCheckRollup":[{"__typename":"CheckRun","name":"symphony-gate","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":"https://github.com/Subconscious-ai/example/actions/runs/99/job/100"},{"__typename":"CheckRun","name":"Analyze (python)","status":"IN_PROGRESS","detailsUrl":"https://github.com/Subconscious-ai/example/actions/runs/99/job/101"},{"__typename":"StatusContext","context":"CodeRabbit","state":"PENDING"}]}
    JSON
          exit 0
        fi

        cat <<'JSON'
    {"url":"https://github.com/Subconscious-ai/example/pull/99","isDraft":true,"headRefOid":"ignored","labels":[{"name":"symphony"}],"statusCheckRollup":[{"__typename":"CheckRun","name":"symphony-gate","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":"https://github.com/Subconscious-ai/example/actions/runs/99/job/100"},{"__typename":"CheckRun","name":"Analyze (python)","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":"https://github.com/Subconscious-ai/example/actions/runs/99/job/101"},{"__typename":"StatusContext","context":"CodeRabbit","state":"PENDING"}]}
    JSON
        exit 0
      fi

      if [ -n "$GH_VIEW_REQUIRED_GATE" ]; then
        cat <<'JSON'
    {"url":"https://github.com/Subconscious-ai/example/pull/99","isDraft":true,"headRefOid":"ignored","labels":[{"name":"symphony"}],"statusCheckRollup":[{"__typename":"CheckRun","name":"symphony-gate","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":"https://github.com/Subconscious-ai/example/actions/runs/99/job/100"},{"__typename":"CheckRun","name":"legacy-e2e","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://github.com/Subconscious-ai/example/actions/runs/99/job/101"}]}
    JSON
        exit 0
      fi

      if [ -n "$GH_VIEW_COUNTER" ]; then
        count=0
        if [ -f "$GH_VIEW_COUNTER" ]; then
          count="$(cat "$GH_VIEW_COUNTER")"
        fi
        count=$((count + 1))
        printf '%s' "$count" > "$GH_VIEW_COUNTER"

        if [ "$count" -eq 1 ]; then
          cat <<'JSON'
    {"url":"https://github.com/Subconscious-ai/example/pull/99","isDraft":true,"headRefOid":"ignored","labels":[{"name":"symphony"}],"statusCheckRollup":[]}
    JSON
          exit 0
        fi

        if [ "$count" -eq 2 ]; then
          cat <<'JSON'
    {"url":"https://github.com/Subconscious-ai/example/pull/99","isDraft":true,"headRefOid":"ignored","labels":[{"name":"symphony"}],"statusCheckRollup":[{"__typename":"CheckRun","status":"IN_PROGRESS","detailsUrl":"https://github.com/Subconscious-ai/example/actions/runs/99/job/100"}]}
    JSON
          exit 0
        fi

        cat <<'JSON'
    {"url":"https://github.com/Subconscious-ai/example/pull/99","isDraft":true,"headRefOid":"ignored","labels":[{"name":"symphony"}],"statusCheckRollup":[{"__typename":"CheckRun","name":"Run static checks","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":"https://github.com/Subconscious-ai/example/actions/runs/99/job/100"}]}
    JSON
        exit 0
      fi

      cat <<'JSON'
    {"url":"https://github.com/Subconscious-ai/example/pull/99","isDraft":true,"headRefOid":"ignored","labels":[{"name":"symphony"}],"statusCheckRollup":[{"__typename":"StatusContext","context":"Vercel","state":"SUCCESS","targetUrl":"https://vercel.com/example/preview"}]}
    JSON
      exit 0
    fi

    exit 99
    """
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:symphony_elixir, key)
  defp restore_app_env(key, value), do: Application.put_env(:symphony_elixir, key, value)
end
