alias Experimental.GenStage

defmodule Honeydew.Supervisor do

  def start_link(pool, worker, args, pool_opts) do
    import Supervisor.Spec

    queue      = pool_opts[:queue] || Honeydew.Queue.ErlangQueue
    queue_args = Keyword.get(pool_opts, :queue_args, [])
    dispatcher = pool_opts[:dispatcher] || GenStage.DemandDispatcher

    failure_mode = pool_opts[:failure_mode] || Honeydew.FailureMode.Abandon

    num_queues  = pool_opts[:num_queues] || 1
    num_workers = pool_opts[:num_workers] || 10

    init_retry_secs = pool_opts[:init_retry_secs] || 5

    pool |> Honeydew.queue_group  |> :pg2.create
    pool |> Honeydew.worker_group |> :pg2.create

    children = [
      supervisor(Honeydew.WorkerSupervisor, [pool, worker, args, num_workers, init_retry_secs, failure_mode], id: :worker_supervisor),
      supervisor(Honeydew.QueueSupervisor,  [pool, queue, queue_args, num_queues, dispatcher], id: :queue_supervisor)
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

end
