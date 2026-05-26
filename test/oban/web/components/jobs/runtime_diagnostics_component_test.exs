defmodule Oban.Web.Components.Jobs.RuntimeDiagnosticsComponentTest do
  use Oban.Web.Case, async: false

  import Phoenix.LiveViewTest

  alias Oban.Web.JobLogs
  alias Oban.Web.JobLogs.LogEntry
  alias Oban.Web.JobRuntime
  alias Oban.Web.Jobs.RuntimeDiagnosticsComponent

  @moduletag :sqlite

  setup do
    previous = Application.get_env(:oban_web, JobLogs)

    if is_nil(Process.whereis(JobRuntime)) do
      start_supervised!(JobRuntime)
    end

    JobRuntime.clear()
    Application.put_env(:oban_web, JobLogs, repo: Oban.Web.SQLiteRepo)
    Oban.Web.SQLiteRepo.delete_all(LogEntry)

    on_exit(fn ->
      JobRuntime.clear()
      Oban.Web.SQLiteRepo.delete_all(LogEntry)

      if previous do
        Application.put_env(:oban_web, JobLogs, previous)
      else
        Application.delete_env(:oban_web, JobLogs)
      end
    end)
  end

  test "renders live process diagnostics for an executing job" do
    job =
      insert_job!(%{},
        conf: %{repo: Oban.Web.SQLiteRepo},
        state: "executing",
        attempt: 1,
        max_attempts: 3
      )

    JobRuntime.register(job, self())

    html =
      render_component(RuntimeDiagnosticsComponent, id: "runtime-diagnostics-#{job.id}", job: job)

    assert html =~ "Runtime"
    assert html =~ "Running"
    assert html =~ "Process Info"
    assert html =~ "Message Queue"
    refute html =~ ">Pro<"
  end

  test "renders persisted execution summary for a completed job" do
    job =
      insert_job!(%{},
        conf: %{repo: Oban.Web.SQLiteRepo},
        state: "completed",
        attempt: 2,
        max_attempts: 6
      )

    {:ok, _entry} =
      JobLogs.record(%{
        job_id: job.id,
        level: :warning,
        source: :logger,
        message: "OCR retry recovered",
        logger_metadata: %{}
      })

    html =
      render_component(RuntimeDiagnosticsComponent, id: "runtime-diagnostics-#{job.id}", job: job)

    assert html =~ "Completed"
    assert html =~ "Log Entries"
    assert html =~ "Warnings"
    assert html =~ "OCR retry recovered"
  end

  test "renders the latest job error when present" do
    job =
      insert_job!(%{},
        conf: %{repo: Oban.Web.SQLiteRepo},
        state: "discarded",
        attempt: 6,
        max_attempts: 6,
        errors: [%{"error" => "OCR failed: database busy"}]
      )

    html =
      render_component(RuntimeDiagnosticsComponent, id: "runtime-diagnostics-#{job.id}", job: job)

    assert html =~ "Discarded"
    assert html =~ "Latest Error"
    assert html =~ "OCR failed: database busy"
  end
end
