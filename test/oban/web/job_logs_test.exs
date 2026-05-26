defmodule Oban.Web.JobLogsTest do
  use Oban.Web.Case, async: false

  alias Oban.Web.JobLogs
  alias Oban.Web.JobLogs.LogEntry

  @moduletag :sqlite

  setup do
    previous = Application.get_env(:oban_web, JobLogs)

    start_supervised!({Phoenix.PubSub, name: Oban.Web.JobLogsPubSub})

    Application.put_env(:oban_web, JobLogs,
      repo: Oban.Web.SQLiteRepo,
      pubsub: Oban.Web.JobLogsPubSub,
      levels: [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency]
    )

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

  test "records and broadcasts job-scoped log entries" do
    Phoenix.PubSub.subscribe(Oban.Web.JobLogsPubSub, JobLogs.topic(123))

    assert {:ok, %LogEntry{} = entry} =
             JobLogs.record(%{
               job_id: 123,
               level: :info,
               source: :logger,
               message: "parsed first page",
               logger_metadata: %{worker: "MyApp.Worker"}
             })

    assert_receive {JobLogs, :entry, ^entry}

    assert [stored] = JobLogs.list(123)
    assert stored.message == "parsed first page"
    assert stored.logger_metadata["worker"] == "MyApp.Worker"
  end

  test "telemetry start event adds job metadata to the worker process" do
    Logger.metadata([])

    job = %Oban.Job{
      id: 456,
      queue: "documents",
      worker: "MyApp.Worker",
      attempt: 2,
      max_attempts: 6
    }

    Oban.Web.JobLogs.Telemetry.handle_event([:oban, :job, :start], %{}, %{job: job}, [])

    assert Logger.metadata()[:oban_job_id] == 456
    assert Logger.metadata()[:oban_queue] == "documents"
    assert Logger.metadata()[:oban_worker] == "MyApp.Worker"
    assert Logger.metadata()[:oban_attempt] == 2
  end

  test "logger handler stores events that include oban job metadata" do
    start_supervised!(JobLogs)
    Phoenix.PubSub.subscribe(Oban.Web.JobLogsPubSub, JobLogs.topic(789))

    event = %{
      level: :warning,
      msg: {"slow OCR page ~p", [3]},
      meta: %{
        oban_job_id: 789,
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

    assert [entry] = JobLogs.list(789)
    assert entry.level == :warning
    assert entry.source == :logger
    assert entry.message =~ "slow OCR page 3"
    assert entry.logger_metadata["oban_queue"] == "documents"
    assert entry.logger_metadata["document_run_id"] == 1036
    assert entry.logger_metadata["extraction_stage"] == ":ocr"
    assert entry.logger_metadata["mfa"] == "{MyApp.Pipeline, :process_document, 2}"
  end

  test "logger handler ignores Ecto SQL debug noise from job processes" do
    start_supervised!(JobLogs)
    Phoenix.PubSub.subscribe(Oban.Web.JobLogsPubSub, JobLogs.topic(791))

    event = %{
      level: :debug,
      msg:
        {:string, "QUERY OK source=\"oban_job_logs\" db=0.4ms\nINSERT INTO \"oban_job_logs\" ..."},
      meta: %{
        oban_job_id: 791,
        oban_queue: "documents",
        oban_worker: "MyApp.Worker",
        mfa: {Ecto.Adapters.SQL, :log, 5}
      }
    }

    formatter = Logger.default_formatter(format: "$message", colors: [enabled: false])

    assert :ok = JobLogs.LoggerHandler.log(event, %{formatter: formatter})

    refute_receive {JobLogs, :entry, %LogEntry{}}
    assert [] = JobLogs.list(791)
  end
end
