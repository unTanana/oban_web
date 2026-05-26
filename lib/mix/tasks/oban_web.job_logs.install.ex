defmodule Mix.Tasks.ObanWeb.JobLogs.Install do
  @moduledoc """
  Installs Oban Web job-log capture.

  This task prepares the host application to store and display logs on Oban Web
  job detail pages by generating a migration that delegates to
  `Oban.Web.JobLogs.Migration`.

  ## Example

      mix oban_web.job_logs.install --repo MyApp.Repo

  ## Options

    * `--repo` or `-r` - Specify the Ecto repo to place the migration under
    * `--prefix` - Store job logs in an Ecto prefix/schema
    * `--migrations-path` - Override the migration directory

  """

  use Mix.Task

  import Macro, only: [camelize: 1]
  import Mix.Ecto
  import Mix.EctoSQL
  import Mix.Generator

  @shortdoc "Installs Oban Web job-log capture"

  @aliases [r: :repo]
  @switches [
    migrations_path: :string,
    prefix: :string,
    repo: [:string, :keep]
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config", args)

    {opts, _parsed, invalid} = OptionParser.parse(args, strict: @switches, aliases: @aliases)

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    case parse_repo(args) do
      [] ->
        Mix.raise("expected --repo or configured :ecto_repos for oban_web.job_logs.install")

      repos ->
        Enum.each(repos, &create_migration(&1, opts))
    end
  end

  defp create_migration(repo, opts) do
    ensure_repo_config!(repo)

    path = opts[:migrations_path] || Path.join(source_repo_priv(repo), "migrations")
    base_name = "create_oban_job_logs.exs"
    fuzzy_path = Path.join(path, "*_#{base_name}")

    case Path.wildcard(fuzzy_path) do
      [existing | _rest] ->
        Mix.shell().info([:yellow, "* skipped ", :reset, Path.relative_to_cwd(existing)])

      [] ->
        File.mkdir_p!(path)

        path
        |> Path.join("#{timestamp()}_#{base_name}")
        |> create_file(migration_template(repo, opts[:prefix]))
    end
  end

  defp ensure_repo_config!(repo) do
    unless Code.ensure_loaded?(repo) and function_exported?(repo, :config, 0) do
      Mix.raise("expected #{inspect(repo)} to be an Ecto repo")
    end
  end

  defp migration_template(repo, prefix) do
    assigns = [
      module: Module.concat([repo, Migrations, camelize("create_oban_job_logs")]),
      up_args: migration_args(prefix),
      down_args: migration_args(prefix)
    ]

    """
    defmodule <%= inspect @module %> do
      use Ecto.Migration

      def up, do: Oban.Web.JobLogs.Migration.up(<%= @up_args %>)

      def down, do: Oban.Web.JobLogs.Migration.down(<%= @down_args %>)
    end
    """
    |> EEx.eval_string(assigns: assigns)
  end

  defp migration_args(nil), do: ""
  defp migration_args(prefix), do: "prefix: #{inspect(prefix)}"

  defp timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.universal_time()

    [
      year,
      pad(month),
      pad(day),
      pad(hour),
      pad(minute),
      pad(second)
    ]
    |> Enum.join()
  end

  defp pad(value) when value < 10, do: "0#{value}"
  defp pad(value), do: to_string(value)
end
