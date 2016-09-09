alias Experimental.GenStage

defmodule Honeydew.WorkerMonitor do
  use GenServer
  alias Honeydew.Job
  require Logger

  defmodule State do
    defstruct [:pool, :worker, :job, :failure_mode, :failure_mode_args]
  end

  def start_link(pool, module, args, init_retry_secs, failure_mode, failure_mode_args) do
    GenServer.start_link(__MODULE__, [pool, module, args, init_retry_secs, failure_mode, failure_mode_args])
  end

  def init([pool, module, args, init_retry_secs, failure_mode, failure_mode_args]) do
    Process.flag(:trap_exit, true)

    has_init = module.__info__(:functions) |> Enum.member?({:init, 1})
    GenStage.start(Honeydew.Worker, [pool, module, args, self, has_init])
    |> case do
         {:ok, worker} ->
           Process.link(worker)

           pool
           |> Honeydew.group(:workers)
           |> :pg2.join(worker)

           pool
           |> Honeydew.group(:worker_monitors)
           |> :pg2.join(self)

           GenStage.cast(worker, :subscribe_to_queues)
           {:ok, %State{pool: pool, worker: worker, failure_mode: failure_mode, failure_mode_args: failure_mode_args}}
         {:error, _} ->
           :timer.apply_after(init_retry_secs * 1000, Supervisor, :start_child, [Honeydew.worker_supervisor(pool), []])
           :ignore
        end
  end

  def handle_call({:working_on, job}, _from, state) do
    job = %{job | by: node}
    {:reply, :ok, %{state | job: job}}
  end

  def handle_call(:current_job, _from, %State{job: nil} = state) do
    {:reply, nil, state}
  end

  def handle_call(:current_job, _from, %State{job: job} = state) do
    {:reply, job, state}
  end

  # when a job is successful, the worker sends us a message to clear our job state (if we were to die while holding
  # that state, but the job had since been successfully processed, we'd run the failure mode's callback. that's bad.)
  def handle_call(:ack, _from, state) do
    {:reply, :ok, %{state | job: nil}}
  end

  def handle_info({:EXIT, worker, reason}, %State{pool: pool, worker: worker, job: %Job{} = job} = state)do
    Logger.info "Worker #{inspect worker} from pool #{pool} died while working on #{inspect job}"

    {:stop, {:worker_died, reason}, state}
  end

  def terminate(_reason, %State{job: nil}) do
    :ok
  end

  def terminate(reason, %State{pool: pool, job: job, failure_mode: failure_mode, failure_mode_args: failure_mode_args}) do
    failure_mode.handle_failure(pool, job, reason, failure_mode_args)
  end
end
