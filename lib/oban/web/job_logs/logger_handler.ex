defmodule Oban.Web.JobLogs.LoggerHandler do
  @moduledoc false

  @handler_id __MODULE__
  @skip_key {__MODULE__, :capturing}

  def attach do
    if function_exported?(Logger, :default_formatter, 1) do
      config = %{
        formatter: Logger.default_formatter(format: "$message", colors: [enabled: false])
      }

      case :logger.add_handler(@handler_id, __MODULE__, config) do
        :ok -> :ok
        {:error, {:already_exist, _handler_id}} -> :ok
        {:error, :already_exists} -> :ok
      end
    end
  end

  def log(%{meta: meta, level: level} = event, config) do
    with false <- Process.get(@skip_key, false),
         job_id when is_integer(job_id) <- meta[:oban_job_id],
         false <- ignored_log?(level, meta),
         true <- MapSet.member?(Oban.Web.JobLogs.configured_levels(), level) do
      capture(event, config, job_id, level, meta)
    else
      _ignored -> :ok
    end
  end

  defp capture(event, config, job_id, level, meta) do
    Process.put(@skip_key, true)

    try do
      %{formatter: {formatter_mod, formatter_config}} = config
      message = event |> formatter_mod.format(formatter_config) |> IO.chardata_to_string()

      Oban.Web.JobLogs.record_async(%{
        job_id: job_id,
        level: level,
        source: :logger,
        message: String.trim_trailing(message),
        logger_metadata: stringify_metadata(meta)
      })
    rescue
      _error -> :ok
    after
      Process.delete(@skip_key)
    end

    :ok
  end

  defp ignored_log?(:debug, %{mfa: {Ecto.Adapters.SQL, :log, _arity}}), do: true
  defp ignored_log?(_level, _meta), do: false

  defp stringify_metadata(meta) do
    meta
    |> Map.take([
      :oban_queue,
      :oban_worker,
      :oban_attempt,
      :oban_max_attempts,
      :document_run_id,
      :extraction_stage,
      :segment_id,
      :segment_kind,
      :grid_code,
      :candidate_count,
      :file,
      :line,
      :mfa,
      :module,
      :function
    ])
    |> Map.new(fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_binary(value), do: value
  defp stringify_value(value) when is_integer(value), do: value
  defp stringify_value(value) when is_float(value), do: value
  defp stringify_value(value) when is_boolean(value), do: value
  defp stringify_value(nil), do: nil

  defp stringify_value(value) when is_list(value) do
    if List.ascii_printable?(value), do: to_string(value), else: inspect(value)
  end

  defp stringify_value(value) when is_atom(value), do: inspect(value)
  defp stringify_value(value), do: inspect(value)
end
