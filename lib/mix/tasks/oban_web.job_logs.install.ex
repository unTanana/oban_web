defmodule Mix.Tasks.ObanWeb.JobLogs.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs Oban Web job-log capture"
  end

  def example do
    "mix oban_web.job_logs.install --repo MyApp.Repo"
  end

  def long_doc do
    """
    #{short_doc()}.

    This task configures the host application to capture and display logs on
    Oban Web job detail pages:

    * Adds `config :oban_web, Oban.Web.JobLogs`
    * Disables the collector in `test.exs`
    * Adds `{Oban.Web.JobLogs, []}` to the application supervision tree
    * Generates a migration that delegates to `Oban.Web.JobLogs.Migration`

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

    * `--repo` or `-r` — Specify the Ecto repo used by Oban
    * `--pubsub` — Specify the Phoenix PubSub server for live dashboard updates
    * `--prefix` — Store job logs in an Ecto prefix/schema
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.ObanWeb.JobLogs.Install do
    @shortdoc __MODULE__.Docs.short_doc()
    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @levels [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency]

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :oban,
        example: __MODULE__.Docs.example(),
        schema: [repo: :string, pubsub: :string, prefix: :string],
        aliases: [r: :repo]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      opts = igniter.args.options

      case extract_repo(igniter, opts[:repo]) do
        {:ok, igniter, repo} ->
          pubsub = parse_pubsub(igniter, opts[:pubsub])
          prefix = opts[:prefix]

          igniter
          |> configure_job_logs(repo, pubsub, prefix)
          |> configure_test()
          |> add_supervisor_child(repo)
          |> Igniter.Libs.Ecto.gen_migration(
            repo,
            "create_oban_job_logs",
            body: migration_body(prefix),
            on_exists: :skip
          )

        {:error, igniter} ->
          igniter
      end
    end

    defp extract_repo(igniter, nil) do
      case Igniter.Libs.Ecto.list_repos(igniter) do
        {igniter, [repo | _]} ->
          {:ok, igniter, repo}

        {igniter, []} ->
          {:error,
           Igniter.add_issue(igniter, """
           No Ecto repo found.

           Specify a repo explicitly with: mix oban_web.job_logs.install --repo MyApp.Repo
           """)}
      end
    end

    defp extract_repo(igniter, module) do
      repo = Igniter.Project.Module.parse(module)

      case Igniter.Project.Module.module_exists(igniter, repo) do
        {true, igniter} ->
          {:ok, igniter, repo}

        {false, igniter} ->
          {:error, Igniter.add_issue(igniter, "Provided repo (#{inspect(repo)}) doesn't exist")}
      end
    end

    defp parse_pubsub(igniter, nil), do: Igniter.Project.Module.module_name(igniter, "PubSub")
    defp parse_pubsub(_igniter, module), do: Igniter.Project.Module.parse(module)

    defp configure_job_logs(igniter, repo, pubsub, nil) do
      configure_job_logs(igniter, repo, pubsub, [])
    end

    defp configure_job_logs(igniter, repo, pubsub, prefix) when is_binary(prefix) do
      configure_job_logs(igniter, repo, pubsub, prefix: prefix)
    end

    defp configure_job_logs(igniter, repo, pubsub, prefix_opts) do
      config = [repo: repo, pubsub: pubsub, levels: @levels] ++ prefix_opts

      Igniter.Project.Config.configure_new(
        igniter,
        "config.exs",
        :oban_web,
        [Oban.Web.JobLogs],
        {:code, config}
      )
    end

    defp configure_test(igniter) do
      Igniter.Project.Config.configure_new(
        igniter,
        "test.exs",
        :oban_web,
        [Oban.Web.JobLogs],
        {:code, [enabled: false]}
      )
    end

    defp add_supervisor_child(igniter, repo) do
      {igniter, present?} = job_logs_child_present?(igniter)

      if present? do
        igniter
      else
        Igniter.Project.Application.add_new_child(
          igniter,
          {Oban.Web.JobLogs, []},
          after: [repo]
        )
      end
    end

    defp job_logs_child_present?(igniter) do
      with app when is_atom(app) <- Igniter.Project.Application.app_module(igniter),
           path <- Igniter.Project.Module.proper_location(igniter, app),
           igniter <- Igniter.include_existing_file(igniter, path),
           %{from: _from} = source <- Map.get(igniter.rewrite.sources, path),
           content when is_binary(content) <- Rewrite.Source.get(source, :content) do
        {igniter, String.contains?(content, "Oban.Web.JobLogs")}
      else
        _ -> {igniter, false}
      end
    end

    defp migration_body(nil) do
      """
      def up, do: Oban.Web.JobLogs.Migration.up()

      def down, do: Oban.Web.JobLogs.Migration.down()
      """
    end

    defp migration_body(prefix) when is_binary(prefix) do
      """
      def up, do: Oban.Web.JobLogs.Migration.up(prefix: #{inspect(prefix)})

      def down, do: Oban.Web.JobLogs.Migration.down(prefix: #{inspect(prefix)})
      """
    end
  end
else
  defmodule Mix.Tasks.ObanWeb.JobLogs.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"
    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'oban_web.job_logs.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
