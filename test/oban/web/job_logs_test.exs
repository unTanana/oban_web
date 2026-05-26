defmodule Oban.Web.JobLogsTest do
  use Oban.Web.Case, async: false

  alias Oban.Web.JobLogs
  alias Oban.Web.JobLogs.LogEntry

  @moduletag :sqlite

  defmodule Endpoint do
    def config(:pubsub_server, _default), do: Oban.Web.JobLogsPubSub
  end

  setup do
    previous = Application.get_env(:oban_web, JobLogs)

    JobLogs.clear_runtime_config()

    start_supervised!({Phoenix.PubSub, name: Oban.Web.JobLogsPubSub})

    Application.put_env(:oban_web, JobLogs,
      repo: Oban.Web.SQLiteRepo,
      pubsub: Oban.Web.JobLogsPubSub,
      levels: [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency]
    )

    Oban.Web.SQLiteRepo.delete_all(LogEntry)

    on_exit(fn ->
      Oban.Web.SQLiteRepo.delete_all(LogEntry)
      JobLogs.clear_runtime_config()

      if previous do
        Application.put_env(:oban_web, JobLogs, previous)
      else
        Application.delete_env(:oban_web, JobLogs)
      end
    end)
  end

  test "records and broadcasts job-scoped log entries" do
    job = insert_sqlite_job!()

    Phoenix.PubSub.subscribe(Oban.Web.JobLogsPubSub, JobLogs.topic(job.id))

    assert {:ok, %LogEntry{} = entry} =
             JobLogs.record(%{
               job_id: job.id,
               level: :info,
               source: :logger,
               message: "parsed first page",
               logger_metadata: %{worker: "MyApp.Worker"}
             })

    assert_receive {JobLogs, :entry, ^entry}

    assert [stored] = JobLogs.list(job.id)
    assert stored.message == "parsed first page"
    assert stored.logger_metadata["worker"] == "MyApp.Worker"
  end

  test "infers repo from Oban config and pubsub from the dashboard socket" do
    Application.delete_env(:oban_web, JobLogs)

    job = insert_sqlite_job!()
    socket = %{assigns: %{conf: %{repo: Oban.Web.SQLiteRepo, prefix: false}}, endpoint: Endpoint}

    JobLogs.subscribe(job, socket)

    assert JobLogs.repo() == Oban.Web.SQLiteRepo
    assert JobLogs.pubsub() == Oban.Web.JobLogsPubSub

    assert {:ok, %LogEntry{} = entry} =
             JobLogs.record(%{
               job_id: job.id,
               level: :info,
               source: :logger,
               message: "runtime inferred",
               logger_metadata: %{}
             })

    assert_receive {JobLogs, :entry, ^entry}
  end

  test "telemetry start event adds job metadata to the worker process" do
    Logger.metadata([])
    Application.delete_env(:oban_web, JobLogs)

    job =
      insert_sqlite_job!(
        queue: :documents,
        worker: "MyApp.Worker",
        attempt: 2,
        max_attempts: 6
      )

    Oban.Web.JobLogs.Telemetry.handle_event(
      [:oban, :job, :start],
      %{},
      %{job: job, conf: %{repo: Oban.Web.SQLiteRepo, prefix: false}},
      []
    )

    assert Logger.metadata()[:oban_job_id] == job.id
    assert Logger.metadata()[:oban_queue] == "documents"
    assert Logger.metadata()[:oban_worker] == "MyApp.Worker"
    assert Logger.metadata()[:oban_attempt] == 2
    assert [%LogEntry{message: message}] = JobLogs.list(job.id)
    assert message == "Oban job started MyApp.Worker attempt 2/6"
  end

  test "logger handler stores events that include oban job metadata" do
    ensure_job_logs_started()
    job = insert_sqlite_job!()

    Phoenix.PubSub.subscribe(Oban.Web.JobLogsPubSub, JobLogs.topic(job.id))

    event = %{
      level: :warning,
      msg: {"slow OCR page ~p", [3]},
      meta: %{
        oban_job_id: job.id,
        oban_queue: "documents",
        oban_worker: "MyApp.Worker",
        document_run_id: 1036,
        extraction_stage: :ocr,
        file: ~c"lib/my_app/worker.ex",
        mfa: {MyApp.Pipeline, :process_document, 2},
        line: 17
      }
    }

    formatter = Logger.default_formatter(format: "$message", colors: [enabled: false])

    JobLogs.LoggerHandler.log(event, %{formatter: formatter})

    assert_receive {JobLogs, :entry, %LogEntry{}}

    assert [entry] = JobLogs.list(job.id)
    assert entry.level == :warning
    assert entry.source == :logger
    assert entry.message =~ "slow OCR page 3"
    assert entry.logger_metadata["oban_queue"] == "documents"
    assert entry.logger_metadata["document_run_id"] == 1036
    assert entry.logger_metadata["extraction_stage"] == ":ocr"
    assert entry.logger_metadata["mfa"] == "{MyApp.Pipeline, :process_document, 2}"
  end

  test "logger handler ignores Ecto SQL debug noise from job processes" do
    ensure_job_logs_started()
    job = insert_sqlite_job!()

    Phoenix.PubSub.subscribe(Oban.Web.JobLogsPubSub, JobLogs.topic(job.id))

    event = %{
      level: :debug,
      msg:
        {:string, "QUERY OK source=\"oban_job_logs\" db=0.4ms\nINSERT INTO \"oban_job_logs\" ..."},
      meta: %{
        oban_job_id: job.id,
        oban_queue: "documents",
        oban_worker: "MyApp.Worker",
        mfa: {Ecto.Adapters.SQL, :log, 5}
      }
    }

    formatter = Logger.default_formatter(format: "$message", colors: [enabled: false])

    assert :ok = JobLogs.LoggerHandler.log(event, %{formatter: formatter})

    refute_receive {JobLogs, :entry, %LogEntry{}}
    assert [] = JobLogs.list(job.id)
  end

  test "deletes job logs when the owning job is deleted" do
    job = insert_sqlite_job!()

    assert {:ok, %LogEntry{}} =
             JobLogs.record(%{
               job_id: job.id,
               level: :info,
               source: :logger,
               message: "will cascade",
               logger_metadata: %{}
             })

    assert [_entry] = JobLogs.list(job.id)

    Oban.Web.SQLiteRepo.delete!(job)

    assert [] = JobLogs.list(job.id)
  end

  defp ensure_job_logs_started do
    case Process.whereis(JobLogs) do
      nil -> start_supervised!(JobLogs)
      _pid -> :ok
    end
  end

  defp insert_sqlite_job!(opts \\ []) do
    opts = Keyword.put(opts, :conf, %{repo: Oban.Web.SQLiteRepo})

    insert_job!(%{}, opts)
  end
end
