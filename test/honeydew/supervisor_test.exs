defmodule Honeydew.SupervisorTest do
  use ExUnit.Case, async: false
  # pools register processes globally, so async: false

  test "starts a correct supervision tree" do
    {:ok, supervisor} = Honeydew.Supervisor.start_link(:my_pool, Sender, [:state_here], [])

    assert [{:queue_supervisor,  _q_sup_pid, :supervisor, [Honeydew.QueueSupervisor]},
            {:worker_supervisor, _w_sup_pid, :supervisor, [Honeydew.WorkerSupervisor]}] = Supervisor.which_children(supervisor)

    Supervisor.stop(supervisor)
  end

  test "creates worker and queue process groups" do
    {:ok, supervisor} = Honeydew.Supervisor.start_link(:my_pool, Sender, [:state_here], [])

    assert Enum.member?(:pg2.which_groups, Honeydew.worker_group(:my_pool))
    assert Enum.member?(:pg2.which_groups, Honeydew.queue_group(:my_pool))

    Supervisor.stop(supervisor)
  end
end
