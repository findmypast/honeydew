defmodule Honeydew do
  @doc """
  Creates a supervision spec for a pool.

  `pool` is how you'll refer to the queue to add a task.
  `worker` is the module that the workers in your queue will run.
  `args` are arguments handed to your worker module's `init/1`

  You can provide any of the following `pool_opts`:
  - `queue` is the module that the queue in your queue will run, it must implement the `Honeydew.Queue` behaviour.
  - `queue_args` are arguments handed to your queue module's `init/1`
  - `dispatcher` the job dispatching strategy, must implement the `GenStage.Dispatcher` behaviour
  - `failure_mode` is the module that handles job failures, it must implement the `Honeydew.FailureMode` behaviour
  - `num_queues`: the number of queue processes in the pool
  - `num_workers`: the number of workers in the pool
  - `init_retry_secs`: the amount of time, in seconds, to wait before respawning a worker who's `init/1` function failed

  For example:
    `Honeydew.child_spec("my_awesome_pool", MyJobModule, [key: "secret key"], MyQueueModule, [ip: "localhost"], num_workers: 3)`
  """
  def child_spec(pool, worker, args, pool_opts \\ []) do
    Supervisor.Spec.supervisor(Honeydew.Supervisor, [pool, worker, args, pool_opts], id: :root_supervisor)
  end

  @doc false
  def worker_group(pool) do
    name(pool, "workers")
  end

  @doc false
  def queue_group(pool) do
    name(pool, "queues")
  end

  @doc false
  def worker_supervisor(pool) do
    name(pool, "worker_supervisor")
  end

  @doc false
  def queue_supervisor(pool) do
    name(pool, "queue_supervisor")
  end

  defp name(pool, component) do
    ["honeydew", component, pool] |> Enum.join(".") |> String.to_atom
  end
end
