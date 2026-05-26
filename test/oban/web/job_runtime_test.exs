defmodule Oban.Web.JobRuntimeTest do
  use ExUnit.Case, async: false

  alias Oban.Web.JobRuntime

  setup do
    if is_nil(Process.whereis(JobRuntime)) do
      start_supervised!(JobRuntime)
    end

    JobRuntime.clear()

    on_exit(fn -> JobRuntime.clear() end)
  end

  test "registers and unregisters the running job process" do
    job = %Oban.Job{id: 123}

    assert :ok = JobRuntime.register(job, self())

    assert {:running, runtime} = JobRuntime.lookup(job.id)
    assert runtime.job_id == job.id
    assert runtime.pid == self()
    assert runtime.info[:memory] > 0
    assert is_integer(runtime.info[:message_queue_len])

    assert :ok = JobRuntime.unregister(job)
    assert :not_running = JobRuntime.lookup(job.id)
  end

  test "returns not running when the registered process is gone" do
    job = %Oban.Job{id: 456}

    pid =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    assert :ok = JobRuntime.register(job, pid)
    assert {:running, %{pid: ^pid}} = JobRuntime.lookup(job.id)

    ref = Process.monitor(pid)
    send(pid, :stop)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert :not_running = JobRuntime.lookup(job.id)
  end

  test "telemetry start and terminal events update runtime tracking" do
    job = %Oban.Job{id: 789}

    Oban.Web.JobLogs.Telemetry.handle_event([:oban, :job, :start], %{}, %{job: job}, [])

    assert {:running, runtime} = JobRuntime.lookup(job.id)
    assert runtime.pid == self()

    Oban.Web.JobLogs.Telemetry.handle_event([:oban, :job, :stop], %{}, %{job: job}, [])

    assert :not_running = JobRuntime.lookup(job.id)
  end

  test "ignores jobs without persisted ids" do
    assert :ok = JobRuntime.register(%Oban.Job{}, self())
    assert :not_running = JobRuntime.lookup(nil)
  end
end
