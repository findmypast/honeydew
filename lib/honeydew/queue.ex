alias Experimental.GenStage

defmodule Honeydew.Queue do

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
        GenStage.start_link(__MODULE__, {pool, __MODULE__, args, dispatcher})
      end

      #
      # the worker module also has an init/1 that's called with a list, so we use a tuple
      # to ensure we match this one.
      #
      def init({pool, module, args, dispatcher}) do
        pool
        |> Honeydew.group(:queues)
        |> :pg2.join(self)

        pool
        |> Honeydew.get_all_members(:workers)
        |> Enum.each(&GenStage.async_subscribe(&1, to: self, max_demand: 1, min_demand: 0, cancel: :temporary))

        {:ok, state} = module.init(args)

        {:producer, %State{pool: pool, private: state}, dispatcher: dispatcher}
      end

      def handle_cast(:"$honeydew.resume", %State{suspended: false} = state), do: {:noreply, [], state}
      def handle_cast(:"$honeydew.resume", %State{pool: pool} = state) do
        # handle_resume function instead?
        GenStage.cast(self, :resume)

        {:noreply, [], %{state | suspended: false}}
      end

      def handle_cast(:"$honeydew.suspend", %State{suspended: true} = state), do: {:noreply, [], state}
      def handle_cast(:"$honeydew.suspend", state) do
        # handle_suspend function instead?
        GenStage.cast(self, :suspend)

        {:noreply, [], %{state | suspended: true}}
      end

      # demand arrived while queue is suspended
      def handle_demand(demand, %State{suspended: true, outstanding: outstanding} = state) do
        {:noreply, [], %{state | outstanding: outstanding + demand}}
      end

      # demand arrived, but we still have unsatisfied demand
      def handle_demand(demand, %State{outstanding: outstanding} = state) when demand > 0 and outstanding > 0 do
        {:noreply, [], %{state | outstanding: outstanding + demand}}
      end

      def handle_call(:status, _from, %State{private: queue, suspended: suspended} = state) do
        status =
          queue
          |> status
          |> Map.put(:suspended, suspended)

        {:reply, status, [], state}
      end

      # debugging
      def handle_call(:"$honeydew.state", _from, state) do
        {:reply, state, [], state}
      end
    end
  end

end
