Honeydew
========

Honeydew (["Honey, do!"](http://en.wiktionary.org/wiki/honey_do_list)) is a pluggable job queue + worker pool for Elixir, powered by GenStage.

- Workers are permanent and hold immutable state.
- Workers pull jobs from the queue in a demand-driven fashion.
- Queues can exist locally or on a remote queue server (rabbitmq, redis, distributed erlang, etc...)
- Tasks are executed using `cast/2` and `call/2`, somewhat like a `GenServer`.
- If a worker crashes while processing a job, the job is recovered and a "failure mode" (abandon, requeue, etc) is executed.
- Queues, Workers, Dispatch Strategies and Failure Modes are plugable with user modules.

Honeydew provides "at least once" job execution, it's possible that circumstances could conspire to execute a job, and prevent Honeydew from reporting that success back to the queue. I encourage you to write your jobs idepotently.

Honeydew isn't intended as an RPC system, nor a simple resource pool. You can use it for those purposes, but it's underequipped for an RPC system and overkill for a resource pool.

## Getting Started

In your mix.exs file:

```elixir
defp deps do
  [{:honeydew, " ~> 0.0.11"}]
end
```

### Basic Local Queue Example

Create a worker module and `use Honeydew`.

Honeydew will call your worker's `init/1` and will keep the `state` from an `{:ok, state}` return.

```elixir
defmodule Riak do
  use Honeydew

  @moduledoc """
    This is an example Worker to interface with Riak.
    You'll need to add the erlang riak driver to your mix.exs:
      `{:riakc, ">= 2.4.1"}`
  """

  def init([ip, port]) do
    :riakc_pb_socket.start_link(ip, port) # returns {:ok, riak}
  end

  def up?(riak) do
    :riakc_pb_socket.ping(riak) == :pong
  end

  def put(bucket, key, obj, content_type, riak) do
    :riakc_pb_socket.put(riak, :riakc_obj.new(bucket, key, obj, content_type))
  end

  def get(bucket, key, riak) do
    case :riakc_pb_socket.get(riak, bucket, key) do
      {:ok, obj} -> :riakc_obj.get_value(obj)
      {:error, :notfound} -> nil
      error -> error
    end
  end
end

```

Then start the pool in your supervision tree with `Honeydew.child_spec/4`.

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
    Honeydew.child_spec(:my_pool, Riak, ['127.0.0.1', 8087], num_workers: 5, init_retry_secs: 10)
  ]

  Supervisor.start_link(children, strategy: :one_for_one))
end
```

You can add now tasks to the queue using `cast/2` or `call/2`, like so:

```elixir
iex(1)> Riak.call(:my_pool, :up?)
true
iex(2)> Riak.cast(:my_pool, {:put, ["bucket", "key", "value", "text/plain"]})
:ok
iex(3)> Riak.call(:my_pool, {:get, ["bucket", "key"]})                       
"value"
```

### Local vs Global Queues

In a distributed Erlang scenario, you have the option of having Honeydew's various components run on different nodes. At its heart, Honeydew is simply a collection of queue processes, worker processes and requesting processes (those that call `cast/2` and `call/2`). For example:

- One node runs only the queue processes, while all other nodes run workers, and yet others simply send tasks.
- Each node runs its own queue and worker processes, and mutually send eachother tasks to execute locally.

To start a global queue, pass a `{:global, name}` tuple when you start your supervision tree, and when enqueuing jobs:

`Honeydew.child_spec({:global, :my_pool}, MyWorker, [:some, :args])`

`MyWorker.cast({:global, :my_pool}, fn _ -> IO.puts("hi!") end)`

There's one important caveat that you should note, Honeydew doesn't yet support OTP failover/takeover, so please don't use global queues in production yet. I'll send you three emoji of your choice if you submit a PR. :)

### Pool Options

`Honeydew.child_spec/4`'s last argument is a keyword list of pool options.

See the [Honeydew](https://github.com/koudelka/honeydew/blob/master/lib/honeydew.ex) module for the possible options.


## The Dungeon

### Job Lifecycle

In general, a job goes through the following steps from inception to completion:

- The requesting process calls `cast/2` or `call/2`, which packages the task up into a "job" and sends it to a single member of the queue group.
- The queue process will enqueue the job, then, depending on its current "demand", take one of the following actions:
  - If there is outstanding demand (> 0), the queue will dispatch the job immediately to a waiting worker according to the selected dispatch strategy.
  - If there is no outstanding demand, the job will remain in the queue until demand arrives. (On nodes with zero workers (enqueue-only), demand will never arrive)
- The queue "reserves" the job (marks it as in-progress), and it's sent to the worker. The worker asks its Worker Monitor to remember the job, then executes the task.
- If the worker crashes, the worker monitor executes the selected "Failure Mode" and terminates.
  - The failure mode most likely sends a "negative acknowledgement (nack)" to the queue, which may allow another worker to try the job, or move it to a "failed" queue.
- If the job succeeds, the worker sends acknowledgement ("ack") messages to both the queue and the worker monitor.
  - If the job was enqueued with `call/2`, and the requesting process is connected to the worker's node, the result is sent.
  - The queue process, upon receiving the "ack", will remove the job from the queue.


### Queues

Queues are the most critical location of state in Honeydew, a job will not be removed from the queue unless it has either been successfully executed, or been dealt with by the configured failure mode.

Honeydew includes a few basic queue modules:
 - A simple local LIFO queue implemented with the `:queue` and `Map` modules, this is the default queue.
 - A stateless RabbitMQ connector.

If you want to implement your own queue, check out the included queues as a guide. Try to keep in mind where exactly your queue state lives, is your queue process(es) where jobs live, or is it a completely stateless connector for some external broker? Or a hybrid? I'm excited to see what folks come up with, please open a PR! <3


### Dispatchers

By default, Honeydew uses GenStage's [DemandDispatcher](https://hexdocs.pm/gen_stage/Experimental.GenStage.DemandDispatcher.html), but you can use any module that implements the [GenStage.Dispatcher](https://hexdocs.pm/gen_stage/Experimental.GenStage.Dispatcher.html) behaviour. Simply pass the module as the `:dispatcher` option to `Honeydew.child_spec/4`. I haven't experimented with any other dispatchers aside from the default, if you do, please let me know how it goes.


### Worker State
Worker state is immutable, the only way to change it is to cause the worker to crash and let the supervisor restart it.

Your worker module's `init/1` function must return `{:ok, state}`. If anything else is returned or the function raises an error, the worker will die and restart after a given time interval (by default, five seconds).


### Process Tree

```
Honeydew.Supervisor
├── Honeydew.QueueSupervisor
|   └── Honeydew.Queue (x N, configurable)
└── Honeydew.WorkerSupervisor
    └── Honeydew.WorkerMonitor (x M, configurable)
        └── Honeydew.Worker (x M, one per WorkerMonitor)
```

### TODO:
- failover/takeover for global queues

### Acknowledgements

Thanks to @marcelog, for his [failing worker restart strategy](http://inaka.net/blog/2012/11/29/every-day-erlang/).
