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
  end
end
