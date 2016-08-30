alias Experimental.GenStage

defmodule Honeydew.Queue do
  # a job is an MFA or a function + metadata
  # @type job :: %Job{}
  # @type private :: any

  # @callback init(list) :: private
  # @callback enqueue(private, job) :: private
  # # reserving jobs should not remove them from the queue
  # # the queue should only remove jobs once they are successful
  # @callback reserve(private, integer) :: {private, [job] | []}
  # # it's ok to remove the job from the queue
  # @callback ack(private, job) :: private
  # # it's not ok to remove the job from the queue
  # @callback nack(private, job) :: private

  defmodule State do
    defstruct pool: nil, private: nil, outstanding: 0
  end

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
        pool |> Honeydew.queue_group |> :pg2.join(self)

        GenStage.cast(self, :subscribe_workers)

        {:ok, state} = module.init(args)

        {:producer, %State{pool: pool, private: state}, dispatcher: dispatcher}
      end


      def handle_cast(:subscribe_workers, %State{pool: pool} = state) do
        pool
        |> Honeydew.worker_group
        |> :pg2.get_local_members
        |> Enum.each(&GenStage.async_subscribe(&1, to: self, max_demand: 1, min_demand: 0, cancel: :temporary))

        {:noreply, [], state}
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
