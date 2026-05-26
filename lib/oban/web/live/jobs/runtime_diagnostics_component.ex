defmodule Oban.Web.Jobs.RuntimeDiagnosticsComponent do
  @moduledoc false

  use Oban.Web, :live_component

  @log_limit 500

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    entries = Oban.Web.JobLogs.list(assigns.job.id, limit: @log_limit)
    runtime = runtime(assigns.job)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       entries: entries,
       error_count: level_count(entries, :error),
       latest_error: latest_error(assigns.job),
       latest_entry: List.last(entries),
       runtime: runtime,
       stacktrace: stacktrace(runtime),
       warning_count: level_count(entries, :warning)
     )}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div
      id={"oban-runtime-diagnostics-#{@job.id}"}
      class="px-3 py-6 border-t border-gray-200 dark:border-gray-700"
    >
      <div class="flex items-center justify-between px-2 py-1.5">
        <div class="flex items-center space-x-2 text-gray-600 dark:text-gray-300">
          <span class="font-semibold">Runtime</span>
          <span class={status_badge_class(@job, @runtime)}>
            {runtime_label(@job, @runtime)}
          </span>
        </div>
      </div>

      <div class="mt-3 grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div class="bg-gray-50 dark:bg-gray-800 rounded-md p-4">
          <h4 class="font-medium text-xs uppercase text-gray-500 dark:text-gray-400 mb-3">
            Execution
          </h4>

          <div class="grid grid-cols-2 gap-3">
            <.metric label="State" value={format_state(@job.state)} />
            <.metric label="Attempt" value={"#{@job.attempt} of #{@job.max_attempts}"} />
            <.metric label="Log Entries" value={length(@entries)} />
            <.metric label="Warnings" value={@warning_count} />
            <.metric label="Errors" value={@error_count + length(@job.errors || [])} />
            <.metric label="Started" value={format_datetime(@job.attempted_at)} />
          </div>
        </div>

        <div :if={@runtime} class="bg-gray-50 dark:bg-gray-800 rounded-md p-4">
          <h4 class="font-medium text-xs uppercase text-gray-500 dark:text-gray-400 mb-3">
            Process Info
          </h4>

          <div class="grid grid-cols-2 gap-3">
            <.metric label="Status" value={format_status(@runtime.info[:status])} />
            <.metric label="Memory" value={format_bytes(@runtime.info[:memory])} />
            <.metric label="Message Queue" value={format_number(@runtime.info[:message_queue_len])} />
            <.metric label="Reductions" value={format_number(@runtime.info[:reductions])} />
            <.metric label="Heap Size" value={format_number(@runtime.info[:heap_size])} />
            <.metric label="Stack Size" value={format_number(@runtime.info[:stack_size])} />
          </div>
        </div>

        <div :if={!@runtime} class="bg-gray-50 dark:bg-gray-800 rounded-md p-4">
          <h4 class="font-medium text-xs uppercase text-gray-500 dark:text-gray-400 mb-3">
            Last Activity
          </h4>

          <%= if @latest_entry do %>
            <div class="space-y-2">
              <div class="text-xs uppercase font-medium text-gray-500 dark:text-gray-400">
                {format_log_level(@latest_entry.level)}
              </div>
              <pre class="font-mono text-sm text-gray-600 dark:text-gray-300 whitespace-pre-wrap break-words">{@latest_entry.message}</pre>
            </div>
          <% else %>
            <span class="text-sm text-gray-400 dark:text-gray-500">
              {last_activity_empty_label(@job)}
            </span>
          <% end %>
        </div>

        <div :if={@latest_error} class="bg-gray-50 dark:bg-gray-800 rounded-md p-4">
          <h4 class="font-medium text-xs uppercase text-gray-500 dark:text-gray-400 mb-3">
            Latest Error
          </h4>

          <pre class="font-mono text-sm text-red-700 dark:text-red-300 whitespace-pre-wrap break-words">{@latest_error}</pre>
        </div>

        <div
          :if={Enum.any?(@stacktrace)}
          class="lg:col-span-2 bg-gray-50 dark:bg-gray-800 rounded-md p-4"
        >
          <h4 class="font-medium text-xs uppercase text-gray-500 dark:text-gray-400 mb-3">
            Current Stacktrace
          </h4>

          <div class="space-y-1 max-h-64 overflow-y-auto">
            <div
              :for={frame <- @stacktrace}
              class="font-mono text-xs text-gray-600 dark:text-gray-400 py-1.5 px-2 bg-white dark:bg-gray-900 rounded border-l-2 border-gray-300 dark:border-gray-600"
            >
              {frame}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp metric(assigns) do
    ~H"""
    <div class="flex flex-col">
      <span class="text-xs font-medium text-gray-600 dark:text-gray-300">{@label}</span>
      <span class="text-sm tabular-nums text-gray-800 dark:text-gray-200">
        {format_metric(@value)}
      </span>
    </div>
    """
  end

  defp runtime(job) do
    case Oban.Web.JobRuntime.lookup(job.id) do
      {:running, runtime} -> runtime
      :not_running -> nil
    end
  end

  defp level_count(entries, level) do
    Enum.count(entries, &(&1.level == level))
  end

  defp latest_error(%{errors: [_ | _] = errors}) do
    errors
    |> List.first()
    |> error_message()
  end

  defp latest_error(_job), do: nil

  defp error_message(%{"error" => error}) when is_binary(error), do: error
  defp error_message(%{error: error}) when is_binary(error), do: error
  defp error_message(error), do: inspect(error)

  defp stacktrace(%{info: %{current_stacktrace: stacktrace}}) when is_list(stacktrace) do
    stacktrace
    |> Enum.map(&Exception.format_stacktrace_entry/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp stacktrace(_runtime), do: []

  defp runtime_label(_job, %{}), do: "Running"
  defp runtime_label(%{state: "executing"}, _runtime), do: "Orphaned"
  defp runtime_label(job, _runtime), do: format_state(job.state)

  defp status_badge_class(_job, %{}) do
    "inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-emerald-100 text-emerald-700 dark:bg-emerald-900/50 dark:text-emerald-300"
  end

  defp status_badge_class(%{state: "executing"}, _runtime) do
    "inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-amber-100 text-amber-800 dark:bg-amber-900/50 dark:text-amber-300"
  end

  defp status_badge_class(_job, _runtime) do
    "inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-300"
  end

  defp last_activity_empty_label(%{state: "executing"}),
    do: "No live worker process is registered."

  defp last_activity_empty_label(_job), do: "No runtime activity captured yet."

  defp format_state(nil), do: "Unknown"
  defp format_state(state) when is_binary(state), do: String.capitalize(state)
  defp format_state(state), do: state |> to_string() |> String.capitalize()

  defp format_status(nil), do: "unknown"
  defp format_status(status), do: status |> to_string() |> String.capitalize()

  defp format_bytes(nil), do: "none"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"

  defp format_datetime(nil), do: "none"

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(value), do: to_string(value)

  defp format_number(nil), do: "none"
  defp format_number(number) when is_integer(number), do: integer_to_delimited(number)
  defp format_number(value), do: to_string(value)

  defp format_log_level(level), do: level |> to_string() |> String.upcase()

  defp format_metric(value) when is_binary(value), do: value
  defp format_metric(value) when is_integer(value), do: integer_to_delimited(value)
  defp format_metric(value), do: to_string(value)
end
