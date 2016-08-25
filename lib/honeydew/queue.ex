alias Experimental.GenStage

defmodule Honeydew.Queue do
  use GenStage
  alias Honeydew.Job

  # a job is an MFA or a function + metadata
  @type job :: %Job{}
  @type queue :: any

  @callback init([...] | []) :: queue
  @callback enqueue(queue, job) :: queue
  # reserving jobs should not remove them from the queue
  # the queue should only remove jobs once they are successful
  @callback reserve(queue, integer) :: {queue, [job] | []}
  # it's ok to remove the job from the queue
  @callback ack(queue, job) :: queue
  # it's not ok to remove the job from the queue
  @callback nack(queue, job) :: queue

  defmodule State do
    defstruct pool: nil, queue: nil, module: nil, outstanding: 0
  end

  def start_link(pool, module, args, dispatcher) do
    GenStage.start_link(__MODULE__, [pool, module, args, dispatcher])
  end

  def init([pool, module, args, dispatcher]) do
    pool |> Honeydew.queue_group |> :pg2.join(self)
    GenStage.cast(self, :subscribe_workers)
    {:producer, %State{pool: pool, queue: module.init(args), module: module}, dispatcher: dispatcher}
  end

  # GenStage Callbacks

  def handle_demand(demand, %State{queue: queue, module: module, outstanding: 0} = state) when demand > 0 do
    {queue, jobs} = reserve(queue, demand, module)

    {:noreply, jobs, %{state | queue: queue, outstanding: demand - Enum.count(jobs)}}
  end

  # demand arrived, but we still have unsatisfied demand
  def handle_demand(demand, %State{outstanding: outstanding} = state) when demand > 0 do
    {:noreply, [], %{state | outstanding: outstanding + demand}}
  end

  # Enqueuing

  def handle_cast({:enqueue, task}, %State{queue: queue, module: module, outstanding: 0} = state) do
    {:noreply, [], %{state | queue: enqueue(queue, task, module)}}
  end

  def handle_cast({:enqueue, task}, %State{queue: queue, module: module, outstanding: outstanding} = state) do
    {queue, jobs} =
      queue
      |> enqueue(task, module)
      |> reserve(outstanding, module)

    {:noreply, jobs, %{state | queue: queue, outstanding: outstanding - Enum.count(jobs)}}
  end

  def handle_cast({:ack, job}, %State{queue: queue, module: module} = state) do
    {:noreply, [], %{state | queue: module.ack(queue, job)}}
  end

  def handle_cast({:nack, job}, %State{queue: queue, module: module} = state) do
    {:noreply, [], %{state | queue: module.nack(queue, job)}}
  end

  def handle_cast(:subscribe_workers, %State{pool: pool} = state) do
    pool
    |> Honeydew.worker_group
    |> :pg2.get_local_members
    |> Enum.each(&GenStage.async_subscribe(&1, to: self, max_demand: 1, min_demand: 0, cancel: :temporary))

    {:noreply, [], state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, [], state}
  end

  defp enqueue(queue, task, module) do
    enqueue(queue, task, module, nil)
  end

  defp enqueue(queue, task, module, from) do
    queue
    |> module.enqueue( %Job{task: task, id: :erlang.unique_integer, from: from} )
  end

  defp reserve(queue, num, module) do
    {queue, jobs} = module.reserve(queue, num)
    {queue, Enum.map(jobs, & %{&1 | by: node})}
  end

end
