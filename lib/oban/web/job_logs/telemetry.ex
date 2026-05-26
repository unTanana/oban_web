defmodule Oban.Web.JobLogs.Telemetry do
  @moduledoc false

  require Logger

  @handler_id "oban-web-job-logs"
  @events [
    [:oban, :job, :start],
    [:oban, :job, :stop],
    [:oban, :job, :exception]
  ]

  def attach do
    case :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, []) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  def detach do
    :telemetry.detach(@handler_id)
  end

  def handle_event(
        [:oban, :job, :start],
        _measurements,
        %{job: %Oban.Job{} = job} = meta,
        _config
      ) do
    configure_job_logs(meta)

    Logger.metadata(
      oban_job_id: job.id,
      oban_queue: job.queue,
      oban_worker: job.worker,
      oban_attempt: job.attempt,
      oban_max_attempts: job.max_attempts
    )

    record_lifecycle(:start, job)
  end

  def handle_event([:oban, :job, :stop], _measurements, %{job: %Oban.Job{} = job} = meta, _config) do
    configure_job_logs(meta)
    record_lifecycle(:stop, job, meta)
  end

  def handle_event(
        [:oban, :job, :exception],
        _measurements,
        %{job: %Oban.Job{} = job} = meta,
        _config
      ) do
    configure_job_logs(meta)
    record_lifecycle(:exception, job, meta)
  end

  defp configure_job_logs(meta) do
    meta
    |> Map.get(:conf)
    |> Oban.Web.JobLogs.configure_from_oban_conf()
  end

  defp record_lifecycle(event, job, meta \\ %{}) do
    Oban.Web.JobLogs.record_lifecycle(event, job, meta)
  rescue
    _error -> :ok
  end
end
