defmodule Mix.Tasks.ObanWeb.JobLogs.InstallTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.ObanWeb.JobLogs.Install

  defmodule Repo do
    def config do
      [
        otp_app: :oban_web,
        priv: "priv/repo"
      ]
    end
  end

  setup do
    tmp = Path.join(System.tmp_dir!(), "oban-web-job-logs-install-#{System.unique_integer()}")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)
      Mix.Task.reenable("oban_web.job_logs.install")
    end)

    %{tmp: tmp}
  end

  test "installation creates job logs migration", %{tmp: tmp} do
    File.cd!(tmp, fn ->
      output =
        capture_io(fn ->
          Install.run(["--repo", inspect(Repo)])
        end)

      {path, content} = created_migration!()

      assert output =~ "creating"
      assert path =~ ~r|priv/repo/migrations/\d{14}_create_oban_job_logs\.exs|
      assert content =~ "def up, do: Oban.Web.JobLogs.Migration.up()"
      assert content =~ "def down, do: Oban.Web.JobLogs.Migration.down()"
    end)
  end

  test "installation supports explicit prefix", %{tmp: tmp} do
    File.cd!(tmp, fn ->
      capture_io(fn ->
        Install.run(["--repo", inspect(Repo), "--prefix", "private"])
      end)

      {_path, content} = created_migration!()

      assert content =~ "def up, do: Oban.Web.JobLogs.Migration.up(prefix: \"private\")"
      assert content =~ "def down, do: Oban.Web.JobLogs.Migration.down(prefix: \"private\")"
    end)
  end

  defp created_migration! do
    [path] = Path.wildcard("priv/repo/migrations/*_create_oban_job_logs.exs")

    {path, File.read!(path)}
  end
end
