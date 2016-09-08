alias Experimental.GenStage

defmodule Honeydew.Queue do
  alias Honeydew.Job

  defmodule State do
    defstruct pool: nil,
      private: nil,
      outstanding: 0,
      suspended: false
  end

  # @callback handle_demand(demand :: pos_integer, state :: %State{outstanding: 0}) :: {:noreply, [%Job{}] | [], %State{}}
  # @callback handle_cast({:enqueue, job :: %Job{}}, state :: %State{outstanding: 0})            :: {:noreply, [], %State{}}
  # @callback handle_cast({:enqueue, job :: %Job{}}, state :: %State{outstanding: pos_integer})  :: {:noreply, [%Job{}] | [], %State{}}
  # @callback handle_call({:enqueue, job :: %Job{}}, from :: {pid, reference}, state :: %State{}) :: {:noreply, [%Job{}] | [], %State{}}
  # @callback handle_cast({:ack,  job :: %Job{}}, state :: %State{})                     :: {:noreply, [], %State{}}
  # @callback handle_cast({:nack, job :: %Job{}, requeue :: boolean}, state :: %State{}) :: {:noreply, [], %State{}}
  # @optional_callbacks handle_call: 3


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

        pool
        |> Honeydew.get_all_workers
        |> Enum.each(&GenStage.async_subscribe(&1, to: self, max_demand: 1, min_demand: 0, cancel: :temporary))

        {:ok, state} = module.init(args)

        {:producer, %State{pool: pool, private: state}, dispatcher: dispatcher}
      end

      # ignore
      def handle_cast(:"$honeydew.resume", %State{suspended: false} = state), do: {:noreply, [], state}
      def handle_cast(:"$honeydew.resume", %State{pool: pool} = state) do
        # handle_resume function instead?
        GenStage.cast(self, :resume)

        {:noreply, [], %{state | suspended: false}}
      end

      # ignore
      def handle_cast(:"$honeydew.suspend", %State{suspended: true} = state), do: {:noreply, [], state}
      def handle_cast(:"$honeydew.suspend", state) do
        {:noreply, [], %{state | suspended: true}}
      end

      def handle_demand(demand, %State{suspended: true, outstanding: outstanding} = state) do
        {:noreply, [], %{state | outstanding: outstanding + demand}}
      end

      # demand arrived, but we still have unsatisfied demand
      def handle_demand(demand, %State{outstanding: outstanding} = state) when demand > 0 and outstanding > 0 do
        {:noreply, [], %{state | outstanding: outstanding + demand}}
      end

      # debugging
      def handle_call(:"$honeydew.state", _from, state) do
        {:reply, state, [], state}
      end
    end
  end

end
