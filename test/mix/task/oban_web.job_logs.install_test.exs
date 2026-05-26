defmodule Mix.Tasks.ObanWeb.JobLogs.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  test "installation configures job logs, supervisor, and migration" do
    igniter =
      test_project(files: project_files())
      |> Igniter.compose_task("oban_web.job_logs.install")

    assert_has_patch(igniter, "config/config.exs", """
       1  1   |import Config
       2  2   |
          3 + |config :oban_web, Oban.Web.JobLogs,
          4 + |  repo: Test.Repo,
          5 + |  pubsub: Test.PubSub,
          6 + |  levels: [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency]
          7 + |
       3  8   |config :test,
          ...|
    """)

    assert_has_patch(igniter, "config/test.exs", """
       1  1   |import Config
       2  2   |
          3 + |config :oban_web, Oban.Web.JobLogs, enabled: false
       3  4   |config :test, dev_routes: true
          ...|
    """)

    assert_has_patch(igniter, "lib/test/application.ex", """
         ...|
          |      Test.Repo,
          |      {Phoenix.PubSub, name: Test.PubSub},
        + |      {Oban.Web.JobLogs, []},
          |      {Oban, Application.fetch_env!(:test, Oban)}
          |    ]
         ...|
    """)

    {path, content} = created_migration(igniter)

    assert path =~ ~r|priv/repo/migrations/\d{14}_create_oban_job_logs\.exs|
    assert content =~ "def up, do: Oban.Web.JobLogs.Migration.up()"
    assert content =~ "def down, do: Oban.Web.JobLogs.Migration.down()"
  end

  test "installation supports explicit pubsub and prefix" do
    igniter =
      test_project(files: project_files())
      |> Igniter.compose_task("oban_web.job_logs.install", [
        "--repo",
        "Test.Repo",
        "--pubsub",
        "Test.CustomPubSub",
        "--prefix",
        "private"
      ])

    assert_has_patch(igniter, "config/config.exs", """
       1  1   |import Config
       2  2   |
          3 + |config :oban_web, Oban.Web.JobLogs,
          4 + |  repo: Test.Repo,
          5 + |  pubsub: Test.CustomPubSub,
          6 + |  levels: [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency],
          7 + |  prefix: "private"
          8 + |
       3  9   |config :test,
          ...|
    """)

    {_path, content} = created_migration(igniter)

    assert content =~ "def up, do: Oban.Web.JobLogs.Migration.up(prefix: \"private\")"
    assert content =~ "def down, do: Oban.Web.JobLogs.Migration.down(prefix: \"private\")"
  end

  test "installation skips supervisor update when the child already exists" do
    files =
      update_in(project_files()["lib/test/application.ex"], fn application ->
        String.replace(
          application,
          "{Oban, Application.fetch_env!(:test, Oban)}",
          "{Oban.Web.JobLogs, []},\n      {Oban, Application.fetch_env!(:test, Oban)}"
        )
      end)

    igniter =
      test_project(files: files)
      |> Igniter.compose_task("oban_web.job_logs.install")

    assert igniter.warnings == []
  end

  defp project_files do
    %{
      "config/config.exs" => """
      import Config

      config :test,
        ecto_repos: [Test.Repo]
      """,
      "config/test.exs" => """
      import Config

      config :test, dev_routes: true
      """,
      "lib/test/repo.ex" => """
      defmodule Test.Repo do
        use Ecto.Repo,
          otp_app: :test,
          adapter: Ecto.Adapters.SQLite3
      end
      """,
      "lib/test/application.ex" => """
      defmodule Test.Application do
        use Application

        def start(_type, _args) do
          children = [
            Test.Repo,
            {Phoenix.PubSub, name: Test.PubSub},
            {Oban, Application.fetch_env!(:test, Oban)}
          ]

          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end
      """,
      "mix.exs" => """
      defmodule Test.MixProject do
        use Mix.Project

        def project do
          [
            app: :test,
            version: "0.1.0",
            elixir: "~> 1.17",
            start_permanent: Mix.env() == :prod,
            deps: deps()
          ]
        end

        def application do
          [
            mod: {Test.Application, []},
            extra_applications: [:logger]
          ]
        end

        defp deps do
          []
        end
      end
      """
    }
  end

  defp created_migration(igniter) do
    igniter.rewrite.sources
    |> Enum.find(fn {path, source} ->
      source.from == :string and String.ends_with?(path, "_create_oban_job_logs.exs")
    end)
    |> then(fn {path, source} -> {path, Rewrite.Source.get(source, :content)} end)
  end
end
