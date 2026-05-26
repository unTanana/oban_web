defmodule Oban.Web.Components.Jobs.JobLogsComponentTest do
  use Oban.Web.Case, async: false

  import Phoenix.LiveViewTest

  alias Oban.Web.JobLogs
  alias Oban.Web.JobLogs.LogEntry
  alias Oban.Web.Jobs.JobLogsComponent

  @moduletag :sqlite

  setup do
    previous = Application.get_env(:oban_web, JobLogs)

    Application.put_env(:oban_web, JobLogs, repo: Oban.Web.SQLiteRepo)
    Oban.Web.SQLiteRepo.delete_all(LogEntry)

    on_exit(fn ->
      Oban.Web.SQLiteRepo.delete_all(LogEntry)

      if previous do
        Application.put_env(:oban_web, JobLogs, previous)
      else
        Application.delete_env(:oban_web, JobLogs)
      end
    end)
  end

  test "renders captured logs for the current job" do
    job = insert_job!(%{}, conf: %{repo: Oban.Web.SQLiteRepo})

    {:ok, _entry} =
      JobLogs.record(%{
        job_id: job.id,
        level: :warning,
        source: :logger,
        message: "custom worker progress",
        logger_metadata: %{}
      })

    html =
      render_component(JobLogsComponent,
        id: "job-logs-123",
        job: job,
        entries: JobLogs.list(job.id)
      )

    assert html =~ "Logs"
    assert html =~ "custom worker progress"
    assert html =~ "warning"
  end

  test "renders an empty state when no logs were captured" do
    job = insert_job!(%{}, conf: %{repo: Oban.Web.SQLiteRepo})

    html =
      render_component(JobLogsComponent,
        id: "job-logs-#{job.id}",
        job: job,
        entries: []
      )

    assert html =~ "No logs captured for this job."
  end
end
