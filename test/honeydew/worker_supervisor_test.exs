defmodule Honeydew.WorkerSupervisorTest do
  use ExUnit.Case

  setup do
    pool = :erlang.unique_integer

    Honeydew.create_groups(pool)

    {:ok, supervisor} = Honeydew.WorkerSupervisor.start_link(pool, Sender, [:state_here], 7, 5, Honeydew.FailureMode.Abandon, [])

    # on_exit fn ->
    #   Supervisor.stop(supervisor)
    #   Honeydew.delete_groups(pool)
    # end

    [supervisor: supervisor]
  end

  test "starts the correct number of workers", context do
    assert context[:supervisor]
            |> Supervisor.which_children
            |> Enum.count == 7
  end

  test "starts WorkerMonitors", context do
    assert   {_, _, _, [Honeydew.WorkerMonitor]} = context[:supervisor] |> Supervisor.which_children |> List.first
  end
end
