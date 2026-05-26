defmodule Mix.Tasks.ObanWeb.JobLogs.Install do
  @shortdoc "Installs the Oban Web job logs migration"

  @moduledoc """
  Installs the migration required by `Oban.Web.JobLogs`.

      mix oban_web.job_logs.install
      mix oban_web.job_logs.install --repo MyApp.Repo

  The task writes a timestamped migration under `priv/repo/migrations`.
  """

  use Mix.Task

  import Mix.Generator

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    {opts, _argv, _errors} = OptionParser.parse(args, strict: [repo: :string])
    repo = Keyword.get(opts, :repo, default_repo())

    if path = existing_migration_path() do
      Mix.shell().info([:yellow, "* existing ", :reset, path])
    else
      path = migration_path()

      create_file(path, migration_template(repo))
    end
  end

  defp default_repo do
    app =
      Mix.Project.config()
      |> Keyword.fetch!(:app)
      |> Atom.to_string()
      |> Macro.camelize()

    "#{app}.Repo"
  end

  defp migration_path do
    Path.join([
      "priv",
      "repo",
      "migrations",
      "#{timestamp()}_create_oban_job_logs.exs"
    ])
  end

  defp existing_migration_path do
    "priv/repo/migrations/*_create_oban_job_logs.exs"
    |> Path.wildcard()
    |> List.first()
  end

  defp timestamp do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%d%H%M%S")
  end

  defp migration_template(repo) do
    """
    defmodule #{repo}.Migrations.CreateObanJobLogs do
      use Ecto.Migration

      def change do
        create table(:oban_job_logs) do
          add :job_id, :integer, null: false
          add :level, :text, null: false
          add :source, :text, null: false
          add :message, :text, null: false
          add :logger_metadata, :map, null: false, default: %{}
          add :logged_at, :utc_datetime_usec, null: false

          timestamps(type: :utc_datetime)
        end

        create index(:oban_job_logs, [:job_id, :logged_at])
        create index(:oban_job_logs, [:job_id, :id])
      end
    end
    """
  end
end
