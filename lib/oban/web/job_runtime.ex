defmodule Oban.Web.JobRuntime do
  @moduledoc false

  use GenServer

  defstruct [:job_id, :pid, :registered_at, :info]

  @info_keys [
    :status,
    :memory,
    :message_queue_len,
    :reductions,
    :heap_size,
    :stack_size,
    :current_stacktrace
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts), do: {:ok, %{}}

  def register(job, pid \\ self())

  def register(%Oban.Job{id: job_id}, pid) when is_integer(job_id) and is_pid(pid) do
    call({:register, job_id, pid})
  end

  def register(_job, _pid), do: :ok

  def unregister(%Oban.Job{id: job_id}) when is_integer(job_id) do
    call({:unregister, job_id})
  end

  def unregister(_job), do: :ok

  def lookup(job_id) when is_integer(job_id) do
    call({:lookup, job_id}, :not_running)
  end

  def lookup(_job_id), do: :not_running

  def clear do
    call(:clear)
  end

  @impl GenServer
  def handle_call({:register, job_id, pid}, _from, state) do
    runtime = %__MODULE__{
      job_id: job_id,
      pid: pid,
      registered_at: System.os_time(:second)
    }

    {:reply, :ok, Map.put(state, job_id, runtime)}
  end

  def handle_call({:unregister, job_id}, _from, state) do
    {:reply, :ok, Map.delete(state, job_id)}
  end

  def handle_call({:lookup, job_id}, _from, state) do
    case Map.fetch(state, job_id) do
      {:ok, runtime} ->
        case refresh_runtime(runtime) do
          {:ok, runtime} -> {:reply, {:running, runtime}, Map.put(state, job_id, runtime)}
          :gone -> {:reply, :not_running, Map.delete(state, job_id)}
        end

      :error ->
        {:reply, :not_running, state}
    end
  end

  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{}}
  end

  defp refresh_runtime(%__MODULE__{pid: pid} = runtime) do
    case Process.info(pid, @info_keys) do
      nil -> :gone
      info -> {:ok, %{runtime | info: Map.new(info)}}
    end
  end

  defp call(message, fallback \\ :ok) do
    case Process.whereis(__MODULE__) do
      nil -> fallback
      pid -> GenServer.call(pid, message)
    end
  end
end
