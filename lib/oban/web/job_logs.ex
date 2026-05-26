defmodule Oban.Web.JobLogs do
  @moduledoc """
  Stores and streams log lines associated with Oban jobs.

  Job logs are captured from Oban lifecycle telemetry and from `Logger` events
  emitted while an Oban job is executing. The repo is inferred from Oban's
  runtime config and the PubSub server is inferred from the dashboard endpoint.
  """

  use GenServer

  import Ecto.Query

  alias Oban.Web.JobLogs.LogEntry

  @handler_id Oban.Web.JobLogs.LoggerHandler
  @runtime_config_key {__MODULE__, :runtime_config}
  @levels [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency]

  def start_link(opts) do
    if enabled?() do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    else
      :ignore
    end
  end

  @impl GenServer
  def init(_opts) do
    Process.flag(:trap_exit, true)

    Oban.Web.JobLogs.Telemetry.attach()
    Oban.Web.JobLogs.LoggerHandler.attach()

    {:ok, %{}}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Oban.Web.JobLogs.Telemetry.detach()
    :logger.remove_handler(@handler_id)

    state
  end

  @impl GenServer
  def handle_cast({:record, attrs}, state) do
    try do
      _result = record(attrs)
    rescue
      _error -> :ok
    end

    {:noreply, state}
  end

  def topic(job_id) when is_integer(job_id), do: "oban_web_job_logs:#{job_id}"

  def subscribe(%{id: job_id}, socket) when is_integer(job_id) do
    configure_from_socket(socket)

    if pubsub = pubsub() do
      Phoenix.PubSub.subscribe(pubsub, topic(job_id))
    end

    socket
  end

  def unsubscribe(%{id: job_id}, socket) when is_integer(job_id) do
    configure_from_socket(socket)

    if pubsub = pubsub() do
      Phoenix.PubSub.unsubscribe(pubsub, topic(job_id))
    end

    socket
  end

  def unsubscribe(_job, socket), do: socket

  def list(job_id, opts \\ []) when is_integer(job_id) do
    limit = Keyword.get(opts, :limit, 500)

    if repo = repo() do
      LogEntry
      |> where([entry], entry.job_id == ^job_id)
      |> order_by([entry], desc: entry.logged_at, desc: entry.id)
      |> limit(^limit)
      |> repo.all(repo_opts())
      |> Enum.reverse()
    else
      []
    end
  rescue
    _error -> []
  end

  def record(attrs) when is_map(attrs) do
    if repo = repo() do
      %LogEntry{}
      |> LogEntry.changeset(attrs)
      |> repo.insert(repo_opts())
      |> case do
        {:ok, entry} ->
          broadcast(entry)
          {:ok, entry}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :not_configured}
    end
  end

  def record_async(attrs) when is_map(attrs) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:record, attrs})
    end
  end

  def record_lifecycle(event, %Oban.Job{} = job, meta \\ %{}) do
    attrs = %{
      job_id: job.id,
      level: lifecycle_level(event),
      source: :lifecycle,
      message: lifecycle_message(event, job, meta),
      logger_metadata: %{
        oban_queue: job.queue,
        oban_worker: job.worker,
        oban_attempt: job.attempt,
        oban_max_attempts: job.max_attempts,
        oban_event: to_string(event)
      }
    }

    record(attrs)
  end

  def configured_levels do
    config()
    |> Keyword.get(:levels, @levels)
    |> MapSet.new()
  end

  def repo do
    Keyword.get(config(), :repo)
  end

  def pubsub do
    Keyword.get(config(), :pubsub)
  end

  def config do
    inferred = :persistent_term.get(@runtime_config_key, [])
    configured = Application.get_env(:oban_web, __MODULE__, [])

    Keyword.merge(inferred, configured)
  end

  def enabled? do
    Keyword.get(config(), :enabled, true)
  end

  def configure_from_oban_conf(%{repo: repo} = conf) when is_atom(repo) do
    config =
      [repo: repo]
      |> maybe_put(:prefix, Map.get(conf, :prefix))

    put_runtime_config(config)
  end

  def configure_from_oban_conf(_conf), do: :ok

  def configure_from_socket(%{assigns: assigns} = socket) when is_map(assigns) do
    assigns
    |> Map.get(:conf)
    |> configure_from_oban_conf()

    if pubsub = endpoint_pubsub(socket) do
      put_runtime_config(pubsub: pubsub)
    else
      :ok
    end
  end

  def configure_from_socket(_socket), do: :ok

  def clear_runtime_config do
    :persistent_term.erase(@runtime_config_key)

    :ok
  end

  defp repo_opts do
    config()
    |> Keyword.take([:prefix])
    |> Enum.reject(fn {_key, value} -> empty_option?(value) end)
  end

  defp broadcast(%LogEntry{} = entry) do
    if pubsub = pubsub() do
      Phoenix.PubSub.broadcast(pubsub, topic(entry.job_id), {__MODULE__, :entry, entry})
    end

    :ok
  end

  defp lifecycle_level(:exception), do: :error
  defp lifecycle_level(_event), do: :info

  defp lifecycle_message(:start, job, _meta) do
    "Oban job started #{job.worker} attempt #{job.attempt}/#{job.max_attempts}"
  end

  defp lifecycle_message(:stop, job, meta) do
    state = Map.get(meta, :state, :success)
    "Oban job stopped #{job.worker} state=#{state}"
  end

  defp lifecycle_message(:exception, job, meta) do
    reason =
      meta
      |> Map.get(:reason)
      |> format_reason()

    "Oban job failed #{job.worker}: #{reason}"
  end

  defp format_reason(nil), do: "unknown reason"
  defp format_reason(%_{} = exception), do: Exception.message(exception)
  defp format_reason(reason), do: inspect(reason)

  defp endpoint_pubsub(%{endpoint: endpoint}) when is_atom(endpoint) do
    cond do
      function_exported?(endpoint, :config, 2) -> endpoint.config(:pubsub_server, nil)
      function_exported?(endpoint, :config, 1) -> endpoint.config(:pubsub_server)
      true -> nil
    end
  rescue
    _error -> nil
  end

  defp endpoint_pubsub(_socket), do: nil

  defp put_runtime_config(config) do
    config =
      config
      |> Enum.reject(fn {_key, value} -> empty_option?(value) end)

    current = :persistent_term.get(@runtime_config_key, [])

    :persistent_term.put(@runtime_config_key, Keyword.merge(current, config))

    :ok
  end

  defp maybe_put(config, _key, value) when value in [nil, false], do: config
  defp maybe_put(config, key, value), do: Keyword.put(config, key, value)

  defp empty_option?(value), do: value in [nil, false]
end
