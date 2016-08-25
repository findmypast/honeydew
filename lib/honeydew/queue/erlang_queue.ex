defmodule Honeydew.Queue.ErlangQueue do
  alias Honeydew.Job

  @behaviour Honeydew.Queue

  def init([]) do
    # {pending, in_progress}
    {:queue.new, Map.new}
  end

  def enqueue({pending, in_progress}, job) do
    {:queue.in(job, pending), in_progress}
  end

  def reserve(queue, num), do: do_reserve([], queue, num)

  def do_reserve(jobs, queue, 0), do: {queue, jobs}

  def do_reserve(jobs, {pending, in_progress} = queue, num) do
    case :queue.out(pending) do
      {:empty, _pending} -> {queue, jobs}
      {{:value, job}, pending} ->
        do_reserve([job | jobs], {pending, Map.put(in_progress, job.id, job)}, num - 1)
    end
  end

  def ack({pending, in_progress}, %Job{id: id}) do
    {pending, Map.delete(in_progress, id)}
  end

  def nack({pending, in_progress}, %Job{id: id}) do
    {pending, Map.delete(in_progress, id)}
  end
end
