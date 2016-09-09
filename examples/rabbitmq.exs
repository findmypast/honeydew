defmodule HeavyTask do
  use Honeydew

  def work_really_hard(secs) do
    :timer.sleep(1_000 * secs)
    IO.puts "I worked really hard for #{secs} secs!"
  end
end

defmodule App do
  def start do
    children = [Honeydew.child_spec(:heavy_pool, HeavyTask, [],
                   queue: Honeydew.Queue.RabbitMQ,
                   queue_args: ["amqp://guest:guest@localhost", "heavy_pool", [prefetch: 10]],
                   num_workers: 10)]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end


defmodule EnqueueApp do
  def start do
    children = [Honeydew.child_spec(:heavy_pool, HeavyTask, [],
                   queue: Honeydew.Queue.RabbitMQ,
                   queue_args: ["amqp://guest:guest@localhost", "heavy_pool", []],
                   num_workers: 0)]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
