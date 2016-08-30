defmodule HoneydewTest do
  use ExUnit.Case

  # def child_pids(supervisor) do
  #   supervisor
  #   |> Supervisor.which_children
  #   |> Enum.into(HashSet.new, fn {_, pid, _, _} -> pid end)
  # end

  test "child_spec/4" do
    pool = :erlang.unique_integer
    spec =  Honeydew.child_spec(pool, :my_worker_module, [w: 1], pool_opt: 1, pool_opt_2: 2)
    assert spec == {:root_supervisor,
                    {Honeydew.Supervisor, :start_link,
                     [pool, :my_worker_module, [w: 1], [pool_opt: 1, pool_opt_2: 2]]},
                    :permanent, :infinity, :supervisor, [Honeydew.Supervisor]}
  end

  test "worker_group/1" do
    assert Honeydew.worker_group(:my_pool) == :"honeydew.workers.my_pool"
  end

  test "queue_group/1" do
    assert Honeydew.queue_group(:my_pool) == :"honeydew.queues.my_pool"
  end

  test "worker_supervisor/1" do
    assert Honeydew.worker_supervisor(:my_pool) == :"honeydew.worker_supervisor.my_pool"
  end

  test "queue_supervisor/1" do
    assert Honeydew.queue_supervisor(:my_pool) == :"honeydew.queue_supervisor.my_pool"
  end


  # test "workers restart after crashing" do
  #   {:ok, supervisor} = Honeydew.Supervisor.start_link(:poolname_2, Sender, :state_here, workers: 10)

  #   [{:worker_supervisor, worker_supervisor, :supervisor, _}, _] = Supervisor.which_children(supervisor)

  #   before_crash = child_pids(worker_supervisor)
  #   assert Enum.count(before_crash) == 10

  #   Sender.cast(:poolname_2, fn _state -> :this_is_an = :intentional_crash end)

  #   # # let the pool restart the worker
  #   :timer.sleep 100

  #   after_crash = child_pids(worker_supervisor)
  #   assert Enum.count(after_crash) == 10

  #   # one workers crashed, so there should still be nine with the same pids before and after
  #   assert Set.intersection(before_crash, after_crash) |> Enum.count == 9
  # end

end
