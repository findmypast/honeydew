alias Experimental.GenStage

defmodule Honeydew.Worker do
  use GenStage
  alias Honeydew.Job
  require Logger

  defmodule State do
    defstruct [:pool, :module, :user_state, :monitor]
  end

  def init([pool, module, _args, monitor, false]) do
    {:consumer, %State{pool: pool, module: module, user_state: :no_state, monitor: monitor}}
  end

  def init([pool, module, args, monitor, true]) do
    try do
      case apply(module, :init, [args]) do
        {:ok, state} ->
          {:consumer, %State{pool: pool, module: module, user_state: {:state, state}, monitor: monitor}}
        bad ->
          Logger.warn("#{module}.init/1 must return {:ok, state}, got: #{inspect(bad)}, retrying...")
          {:error, bad}
      end
    rescue e ->
        {:error, e}
    end
  end

  def handle_events([%Job{task: task, from: from} = job], _from, %State{pool: pool, module: module, user_state: user_state, monitor: monitor} = state) do
    :ok = GenServer.call(monitor, {:working_on, job})

    user_state_args =
      case user_state do
        {:state, s} -> [s]
        :no_state   -> []
      end

    result =
      case task do
        f when is_function(f) -> apply(f, user_state_args)
        f when is_atom(f)     -> apply(module, f, user_state_args)
        {f, a}                -> apply(module, f, a ++ user_state_args)
      end

    job = %{job | result: {:ok, result}}

    pool
    |> Honeydew.get_queue
    |> GenStage.cast({:ack, job})

    :ok = GenServer.call(monitor, :ack)

    # is this bad? if we're in a cluster of nodes and a job comes in via
    # a queue with an owner pid that happens to be alive in the local cluster,
    # sending it a message it's not expecting might crash it.
    with {owner, _ref} <- from,
      do: send(owner, job)

    {:noreply, [], state}
  end

  def handle_cast(:subscribe_to_queues, %State{pool: pool} = state) do
    pool
    |> Honeydew.get_all_members(:queues)
    |> Enum.each(&GenStage.async_subscribe(self, to: &1, max_demand: 1, min_demand: 0, cancel: :temporary))

    {:noreply, [], state}
  end

end
