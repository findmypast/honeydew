defmodule Honeydew.WorkerSupervisor do
  alias Honeydew.WorkerMonitor

  def start_link(pool, module, args, num_workers, init_retry_secs, failure_mode, failure_mode_args) do
    import Supervisor.Spec

    children = [
      worker(WorkerMonitor, [pool, module, args, init_retry_secs, failure_mode, failure_mode_args], restart: :transient)
    ]

    opts = [strategy: :simple_one_for_one,
            name: Honeydew.worker_supervisor(pool),
            max_restarts: num_workers,
            max_seconds: init_retry_secs]

    {:ok, supervisor} = Supervisor.start_link(children, opts)

    start_child(supervisor, num_workers)

    {:ok, supervisor}
  end

  defp start_child(_supervisor, 0), do: :noop
  defp start_child(supervisor, num) do
    Supervisor.start_child(supervisor, [])
    start_child(supervisor, num-1)
  end

end
