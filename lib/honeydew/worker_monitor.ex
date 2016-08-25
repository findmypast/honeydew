alias Experimental.GenStage

defmodule Honeydew.WorkerMonitor do
  use GenStage
  require Logger
  alias Honeydew.Worker

  defmodule State do
    defstruct [:pool, :worker, :job, :failure_mode]
  end

  def start_link(pool, module, args, init_retry_secs, failure_mode) do
    GenStage.start_link(__MODULE__, [pool, module, args, init_retry_secs, failure_mode])
  end

  def init([pool, module, args, init_retry_secs, failure_mode]) do
    GenStage.start(Worker, [pool, module, args])
    |> case do
         {:ok, worker} ->
           Process.monitor(worker)
           pool |> Honeydew.worker_group |> :pg2.join(self)
           GenStage.cast(self, :subscribe_to_queues)
           {:producer_consumer, %State{pool: pool, worker: worker, failure_mode: failure_mode}}
         {:error, error} ->
           :timer.apply_after(init_retry_secs * 1000, Supervisor, :start_child, [Honeydew.worker_supervisor(pool), []])
           Logger.warn("#{module}.init/1 must return {:ok, state}, got: #{inspect(error)}, retrying in #{init_retry_secs}s")
           :ignore
        end
  end

  def handle_events([job], _from, state) do
    {:noreply, [job], %{state | job: job}}
  end

  def handle_cast(:subscribe_to_queues, %State{pool: pool, worker: worker} = state) do
    GenStage.sync_subscribe(worker, to: self, max_demand: 1, min_demand: 0)

    pool
    |> Honeydew.queue_group
    |> :pg2.get_local_members
    |> Enum.each(&GenStage.async_subscribe(self, to: &1, max_demand: 1, min_demand: 0, cancel: :temporary))

    {:noreply, [], state}
  end

  def handle_info({:DOWN, _ref, _type, worker, _reason}, %State{pool: pool, worker: worker, job: job, failure_mode: failure_mode} = state) do
    Logger.debug "Worker #{inspect worker} from pool #{pool} died while working on #{inspect job}"

    Task.start(fn -> failure_mode.handle_failure(pool, job) end)

    {:stop, :worker_died, state}
  end
end
