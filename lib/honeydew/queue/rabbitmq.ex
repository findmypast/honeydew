defmodule Honeydew.Queue.RabbitMQ do
  use Honeydew.Queue
  alias AMQP.{Connection, Channel, Queue, Basic}
  alias Honeydew.Job
  alias Honeydew.Queue.State

  # private state
  defmodule PState do
    defstruct channel: nil,
              exchange: nil,
              name: nil
  end

  def init([conn_args, name, opts]) do
    durable = Keyword.get(opts, :durable, true)
    exchange = opts[:exchange] || ""

    {:ok, conn} = Connection.open(conn_args)
    Process.link(conn.pid)

    {:ok, channel} = Channel.open(conn)
    Queue.declare(channel, name, durable: durable)

    {:ok, %PState{channel: channel, exchange: exchange, name: name}}
  end

  # GenStage Callbacks

  def handle_demand(demand, %State{private: queue, outstanding: 0} = state) when demand > 0 do
    jobs = reserve(queue, demand)

    {:noreply, jobs, %{state | private: queue, outstanding: demand - Enum.count(jobs)}}
  end

  # Enqueuing

  # there's no demand outstanding, queue the task.
  def handle_cast({:enqueue, job}, %State{private: queue, outstanding: 0} = state) do
    enqueue(queue, job)
    {:noreply, [], state}
  end

  # there's demand outstanding, enqueue the job and issue as many jobs as possible
  def handle_cast({:enqueue, job}, %State{private: queue, outstanding: outstanding} = state) do
    enqueue(queue, job)
    jobs = reserve(queue, outstanding)

    {:noreply, jobs, %{state | private: queue, outstanding: outstanding - Enum.count(jobs)}}
  end

  def handle_cast({:ack, job}, %State{private: queue} = state) do
    ack(queue, job)
    {:noreply, [], state}
  end

  def handle_cast({:nack, job}, %State{private: queue} = state) do
    nack(queue, job)
    {:noreply, [], state}
  end


  defp enqueue(state, job) do
    Basic.publish(state.channel, state.exchange, state.name, :erlang.term_to_binary(job), persistent: true)
  end

  defp reserve(state, num) do
    do_reserve([], state, num)
  end

  defp do_reserve(jobs, state, 0), do: jobs

  defp do_reserve(jobs, state, num) do
    case Basic.get(state.channel, state.name) do
      {:empty, _meta} -> jobs
      {:ok, payload, meta} ->
        job = %{:erlang.binary_to_term(payload) | private: meta}
        do_reserve([job | jobs], state, num - 1)
    end
  end

  defp ack(%PState{channel: channel}, %Job{private: %{delivery_tag: tag}}) do
    Basic.ack(channel, tag)
  end

  defp nack(%PState{channel: channel}, %Job{private: %{delivery_tag: tag}}) do
    Basic.reject(channel, tag, redeliver: true)
  end
end
