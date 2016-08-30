alias Experimental.GenStage

defmodule Honeydew.QueueSupervisorTest do
  use ExUnit.Case

  defmodule TestQueue do
    use Honeydew.Queue

    def init([1, 2]) do
      {:ok, :state_here}
    end
  end

  setup do
    pool = :erlang.unique_integer

    Honeydew.create_groups(pool)

    {:ok, supervisor} = Honeydew.QueueSupervisor.start_link(pool, TestQueue, [1, 2], 3, GenStage.DemandDispatcher)

    # on_exit fn ->
    #   Supervisor.stop(supervisor)
    #   Honeydew.delete_groups(pool)
    # end

    [supervisor: supervisor]
  end

  test "starts the correct number of queues", context do
    assert context[:supervisor]
    |> Supervisor.which_children
    |> Enum.count == 3
  end

  test "starts the given queue module", context do
    assert   {_, _, _, [TestQueue]} = context[:supervisor] |> Supervisor.which_children |> List.first
  end
end
