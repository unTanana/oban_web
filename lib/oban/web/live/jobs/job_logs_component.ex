defmodule Oban.Web.Jobs.JobLogsComponent do
  @moduledoc false

  use Oban.Web, :live_component

  @limit 500

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    entries = Oban.Web.JobLogs.list(assigns.job.id, limit: @limit)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(entries: entries)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div
      id={"oban-job-logs-#{@job.id}"}
      class="px-3 py-6 border-t border-gray-200 dark:border-gray-700"
    >
      <div class="flex items-center justify-between px-2 py-1.5">
        <div class="flex items-center space-x-2 text-gray-600 dark:text-gray-300">
          <span class="font-semibold">Logs</span>
          <span class="text-xs tabular-nums text-gray-400 dark:text-gray-500">
            {length(@entries)}
          </span>
        </div>
      </div>

      <div class="mt-3 rounded-md bg-gray-950 text-gray-100 overflow-hidden">
        <div :if={Enum.empty?(@entries)} class="px-4 py-5 text-sm text-gray-400">
          No logs captured for this job.
        </div>

        <div :if={Enum.any?(@entries)} class="max-h-96 overflow-y-auto divide-y divide-gray-800">
          <div
            :for={entry <- @entries}
            class="grid grid-cols-[9rem_5rem_1fr] gap-3 px-4 py-2 text-xs"
          >
            <time class="tabular-nums text-gray-500">
              {Calendar.strftime(entry.logged_at, "%H:%M:%S.%f") |> String.slice(0, 12)}
            </time>
            <span class={level_class(entry.level)}>
              {entry.level}
            </span>
            <pre class="whitespace-pre-wrap break-words font-mono text-gray-200">{entry.message}</pre>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp level_class(:error), do: "font-semibold text-red-300"
  defp level_class(:critical), do: "font-semibold text-red-300"
  defp level_class(:alert), do: "font-semibold text-red-300"
  defp level_class(:emergency), do: "font-semibold text-red-300"
  defp level_class(:warning), do: "font-semibold text-yellow-300"
  defp level_class(_level), do: "font-semibold text-blue-300"
end
