alias Experimental.GenStage

defmodule Honeydew.Worker do
  use GenStage
  alias Honeydew.Job

  defmodule State do
    defstruct [:pool, :module, :user_state, :monitor]
  end

  def init([pool, module, args, monitor]) do
    try do
      {:ok, user_state} = apply(module, :init, [args])
      {:consumer, %State{pool: pool, module: module, user_state: user_state, monitor: monitor}}
    rescue e ->
      {:error, e}
    end
  end

  def handle_events([%Job{task: task, from: from} = job], _from, %State{pool: pool, module: module, user_state: user_state, monitor: monitor} = state) do
    IO.puts "worker got #{inspect task}"
    result =
      case task do
        f when is_function(f) -> f.(user_state)
        f when is_atom(f)     -> apply(module, f, [user_state])
        {f, a}                -> apply(module, f, a ++ [user_state])
      end

    pool
    |> Honeydew.get_queue
    |> GenStage.cast({:ack, %{job | result: result}})

    GenStage.cast(monitor, :ack)

    # reply if we're connected to the calling node
    with {pid, _ref} <- from,
         nodes = [node | :erlang.nodes],
         node(pid) in nodes,
         true = Process.alive?(pid),
      do: GenStage.reply(from, result)

    {:noreply, [], state}
  end

end
