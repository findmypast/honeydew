alias Experimental.GenStage

defmodule Honeydew.Queue do
  alias Honeydew.Job

  defmodule State do
    defstruct pool: nil, private: nil, outstanding: 0
  end

  @callback handle_demand(demand :: pos_integer, state :: %State{outstanding: 0}) :: {:noreply, [%Job{}] | [], %State{}}
  @callback handle_cast({:enqueue, job :: %Job{}}, state :: %State{outstanding: 0})            :: {:noreply, [], %State{}}
  @callback handle_cast({:enqueue, job :: %Job{}}, state :: %State{outstanding: pos_integer})  :: {:noreply, [%Job{}] | [], %State{}}
  @callback handle_call({:enqueue, job :: %Job{}}, from :: {pid, reference}, state :: %State{}) :: {:noreply, [%Job{}] | [], %State{}}
  @callback handle_cast({:ack,  job :: %Job{}}, state :: %State{})                     :: {:noreply, [], %State{}}
  @callback handle_cast({:nack, job :: %Job{}, requeue :: boolean}, state :: %State{}) :: {:noreply, [], %State{}}
  @optional_callbacks handle_call: 3


  defmacro __using__(_opts) do
    quote do
      use GenStage

      # @behaviour Honeydew.Queue

      def start_link(pool, args, dispatcher) do
        GenStage.start_link(__MODULE__, [:"$honeydew", pool, __MODULE__, args, dispatcher])
      end

      # the module that `use`s this module also has an init(list) function, the :"$honeydew" argument
      # ensures that our init is what is matched by GenStage.start_link/2
      # is this naughty? the alternative might be a :proc_lib.start_link and a :gen_server.enter_loop
      def init([:"$honeydew", pool, module, args, dispatcher]) do
        pool
        |> Honeydew.queue_group
        |> :pg2.join(self)

        GenStage.cast(self, :subscribe_workers)

        {:ok, state} = module.init(args)

        {:producer, %State{pool: pool, private: state}, dispatcher: dispatcher}
      end


      def handle_cast(:subscribe_workers, %State{pool: pool} = state) do
        pool
        |> Honeydew.get_all_workers
        |> Enum.each(&GenStage.async_subscribe(&1, to: self, max_demand: 1, min_demand: 0, cancel: :temporary))

        {:noreply, [], state}
      end

      # demand arrived, but we still have unsatisfied demand
      def handle_demand(demand, %State{outstanding: outstanding} = state) when demand > 0 and outstanding > 0 do
        IO.puts "got #{demand} demand, outstanding now: #{outstanding + demand}"
        {:noreply, [], %{state | outstanding: outstanding + demand}}
      end

      # debugging
      def handle_call(:"$honeydew.state", _from, state) do
        {:reply, state, [], state}
      end
    end
  end

end
