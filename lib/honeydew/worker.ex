alias Experimental.GenStage

defmodule Honeydew.Worker do
  use GenStage
  alias Honeydew.Job

  defmodule State do
    defstruct [:pool, :module, :user_state, :monitor]
  end

  def init([pool, module, args, monitor]) do
    {:ok, user_state} =
      if module.__info__(:functions) |> Enum.member?({:init, 1}) do
        try do
          {:state, apply(module, :init, [args])}
        rescue e ->
            {:error, e}
        end
      else
        {:ok, :no_state}
      end
    {:consumer, %State{pool: pool, module: module, user_state: user_state, monitor: monitor}}
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

    pool
    |> Honeydew.get_queue
    |> GenStage.cast({:ack, %{job | result: result}})

    :ok = GenServer.call(monitor, :ack)

    # reply if we're connected to the calling node
    with {pid, _ref} <- from,
         nodes = [node | :erlang.nodes],
         node(pid) in nodes,
         true = Process.alive?(pid),
      do: GenStage.reply(from, result)

    {:noreply, [], state}
  end

  def handle_cast(:subscribe_to_queues, %State{pool: pool} = state) do
    pool
    |> Honeydew.get_all_queues
    |> Enum.each(&GenStage.async_subscribe(self, to: &1, max_demand: 1, min_demand: 0, cancel: :temporary))

    {:noreply, [], state}
  end

end
