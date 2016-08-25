defmodule Honeydew.WorkerSupervisor do
  alias Honeydew.WorkerMonitor

  def start_link(pool, module, args, num_workers, init_retry_secs, failure_mode) do
    import Supervisor.Spec

    children = [
      worker(WorkerMonitor, [pool, module, args, init_retry_secs, failure_mode], restart: :transient)
    ]

    opts = [strategy: :simple_one_for_one,
            name: Honeydew.worker_supervisor(pool),
            max_restarts: num_workers,
            max_seconds: init_retry_secs]

    {:ok, supervisor} = Supervisor.start_link(children, opts)

    # start up workers
    Enum.each(1..num_workers, fn _ ->
      Supervisor.start_child(supervisor, [])
    end)

    {:ok, supervisor}
  end

end
