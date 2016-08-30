defmodule Honeydew.Queue.ErlangQueue do
  use Honeydew.Queue
  alias Honeydew.Job
  alias Honeydew.Queue.State

  def init([]) do
    # {pending, in_progress}
    {:ok, {:queue.new, Map.new}}
  end

  # GenStage Callbacks

  def handle_demand(demand, %State{private: queue, outstanding: 0} = state) when demand > 0 do
    {queue, jobs} = reserve(queue, demand)

    {:noreply, jobs, %{state | private: queue, outstanding: demand - Enum.count(jobs)}}
  end

  # Enqueuing

  # there's no demand outstanding, queue the task.
  def handle_cast({:enqueue, job}, %State{private: queue, outstanding: 0} = state) do
    {:noreply, [], %{state | private: enqueue(queue, job)}}
  end

  # there's demand outstanding, enqueue the job and issue as many jobs as possible
  def handle_cast({:enqueue, job}, %State{private: queue, outstanding: outstanding} = state) do
    {queue, jobs} =
      queue
      |> enqueue(job)
      |> reserve(outstanding)

    {:noreply, jobs, %{state | private: queue, outstanding: outstanding - Enum.count(jobs)}}
  end

  def handle_call({:enqueue, job}, from, state) do
    handle_cast({:enqueue, %{job | from: from}}, state)
  end


  def handle_cast({:ack, %Job{private: {id, _}}}, %State{private: {pending, in_progress}} = state) do
    {:noreply, [], %{state | private: {pending, Map.delete(in_progress, id)}}}
  end

  # don't requeue
  def handle_cast({:nack, job, false}, state) do
    handle_cast({:ack, job}, state)
  end

  # requeue
  def handle_cast({:nack, %Job{private: {id, nacks}} = job, true}, %State{private: {pending, in_progress}}) do
    job = %{job | private: {id, nacks + 1}}

    handle_cast({:enqueue, job}, %State{private: {pending, Map.delete(in_progress, id)}})
  end


  # Helpers

  defp enqueue({pending, in_progress}, job) do
    {:queue.in(job, pending), in_progress}
  end

  defp reserve(queue, num), do: do_reserve([], queue, num)

  defp do_reserve(jobs, queue, 0), do: {queue, jobs}

  defp do_reserve(jobs, {pending, in_progress} = queue, num) do
    case :queue.out(pending) do
      {:empty, _pending} -> {queue, jobs}
      {{:value, job}, pending} ->
        job = %{job | private: {:erlang.unique_integer, 0}}
        do_reserve([job | jobs], {pending, Map.put(in_progress, job.private, job)}, num - 1)
    end
  end

end
