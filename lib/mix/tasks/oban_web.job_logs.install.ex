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

    This task prepares the host application to store and display logs on Oban
    Web job detail pages:

    * Generates a migration that delegates to `Oban.Web.JobLogs.Migration`

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

    * `--repo` or `-r` — Specify the Ecto repo to place the migration under
    * `--prefix` — Store job logs in an Ecto prefix/schema
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.ObanWeb.JobLogs.Install do
    @shortdoc __MODULE__.Docs.short_doc()
    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :oban,
        example: __MODULE__.Docs.example(),
        schema: [repo: :string, prefix: :string],
        aliases: [r: :repo]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      opts = igniter.args.options

      case extract_repo(igniter, opts[:repo]) do
        {:ok, igniter, repo} ->
          prefix = opts[:prefix]

          Igniter.Libs.Ecto.gen_migration(
            igniter,
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
