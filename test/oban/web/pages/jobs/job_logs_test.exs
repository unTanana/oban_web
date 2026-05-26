defmodule Oban.Web.Pages.Jobs.JobLogsTest do
  use Oban.Web.Case, async: false

  alias Oban.Web.JobLogs
  alias Oban.Web.JobLogs.LogEntry

  @moduletag :sqlite

  setup do
    previous = Application.get_env(:oban_web, JobLogs)
    previous_routing = Process.get(:routing)

    Process.put(:routing, :nowhere)
    start_supervised!({Phoenix.PubSub, name: Oban.Web.JobLogsPubSub})

    Application.put_env(:oban_web, JobLogs,
      repo: Oban.Web.SQLiteRepo,
      pubsub: Oban.Web.JobLogsPubSub
    )

    start_supervised_oban!(repo: Oban.Web.SQLiteRepo, engine: Oban.Engines.Lite)

    Oban.Web.SQLiteRepo.delete_all(LogEntry)

    on_exit(fn ->
      Oban.Web.SQLiteRepo.delete_all(LogEntry)

      if previous_routing do
        Process.put(:routing, previous_routing)
      else
        Process.delete(:routing)
      end

      if previous do
        Application.put_env(:oban_web, JobLogs, previous)
      else
        Application.delete_env(:oban_web, JobLogs)
      end
    end)
  end

  test "opening job details subscribes to job logs without crashing" do
    conf = Oban.Config.new(repo: Oban.Web.SQLiteRepo, engine: Oban.Engines.Lite)
    job = insert_job!(%{}, conf: conf, state: "completed", worker: __MODULE__.Worker)

    {:ok, _entry} =
      JobLogs.record(%{
        job_id: job.id,
        level: :info,
        source: :logger,
        message: "already captured",
        logger_metadata: %{}
      })

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        conf: conf,
        default_params: %{limit: 20, sort_by: "time", sort_dir: "asc", state: "executing"},
        detailed: nil,
        queues: [],
        resolver: Oban.Web.Resolver,
        states: []
      }
    }

    assert {:noreply, socket} =
             Oban.Web.JobsPage.handle_params(%{"id" => to_string(job.id)}, "", socket)

    assert socket.assigns.detailed.id == job.id
    assert [%LogEntry{message: "already captured"}] = socket.assigns.job_log_entries
  end

  test "job log notifications append current detail entries without a reload query" do
    conf = Oban.Config.new(repo: Oban.Web.SQLiteRepo, engine: Oban.Engines.Lite)
    job = insert_job!(%{}, conf: conf, state: "executing", worker: __MODULE__.Worker)

    entry = %LogEntry{
      id: 100,
      job_id: job.id,
      level: :info,
      source: :logger,
      message: "streamed progress",
      logger_metadata: %{},
      logged_at: DateTime.utc_now(:microsecond)
    }

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        conf: conf,
        default_params: %{limit: 20, sort_by: "time", sort_dir: "asc", state: "executing"},
        detailed: job,
        job_log_entries: [],
        queues: [],
        resolver: Oban.Web.Resolver,
        states: []
      }
    }

    assert {:noreply, socket} = Oban.Web.JobsPage.handle_info({JobLogs, :entry, entry}, socket)

    assert socket.assigns.job_log_entries == [entry]
  end
end
