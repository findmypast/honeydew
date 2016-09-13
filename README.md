Honeydew 💪🏻🍈
========

Honeydew (["Honey, do!"](http://en.wiktionary.org/wiki/honey_do_list)) is a pluggable job queue + worker pool for Elixir, powered by [GenStage](https://github.com/elixir-lang/gen_stage). 

- Workers are permanent and hold immutable state.
- Workers pull jobs from the queue in a demand-driven fashion.
- Queues can exist locally, on another node in the cluster, or on a remote queue server (rabbitmq, redis, etc...).
- Jobs are executed using `async/2` and you can receive replies with `yield/1`, somewhat like [Task](http://elixir-lang.org/docs/stable/elixir/Task.html).
- If a worker crashes while processing a job, the job is recovered and a "failure mode" (abandon, requeue, etc) is executed.
- Queues, workers, dispatch strategies and failure modes are all plugable with user modules.

Honeydew attempts to provide "at least once" job execution, it's possible that circumstances could conspire to execute a job, and prevent Honeydew from reporting that success back to the queue. I encourage you to write your jobs idepotently.

Honeydew isn't intended as a simple resource pool, the user's code isn't executed in the requesting process. Though you may use it as such, there are likely other alternatives that would fit your situation better.


### tl;dr
- Check out the [examples](https://github.com/koudelka/honeydew/tree/gen_stage/examples).
- Enqueue and receive responses with `async/2` and `yield/1`.
- Suspend and resume with `Honeydew.suspend/1` and `Honeydew.resume/1`
- Queue status with `Honeydew.status/1`
- List jobs with `Honeydew.filter/2`
- Cancel jobs with `Honeydew.cancel/2`

### Queue Feature Support
|             | yield              | suspend/resume | filter | status | cancel |
|-------------|--------------------|----------------|--------|:------:|:-------:
| ErlangQueue | ✅                 | ✅             | ✅     | ✅    | ✅     |
| RabbitMQ    | if-nodes-connected | per-node       | ❌     | ✅    | ❌     |


## Getting Started

In your mix.exs file:

```elixir
defp deps do
  [{:honeydew, " ~> 0.0.11"}]
end
```

### Local Queue Example

There's an uncaring firehose of data pointed at us, we need to store it all in our database, Riak.

Let's create a worker module and `use Honeydew`. Honeydew will call our worker's `init/1` and keep the `state` from an `{:ok, state}` return.

Our workers are going to call functions from our module, the last argument will be the worker's state.

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
    :ok = :riakc_pb_socket.put(riak, :riakc_obj.new(bucket, key, obj, content_type))
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

Then we'll start the queue and workers in our supervision tree with `Honeydew.child_spec/4`.

```elixir
def start(_type, _args) do

  children = [
    Honeydew.child_spec(:my_pool, Riak, ['127.0.0.1', 8087], num_workers: 5, init_retry_secs: 10)
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

A job is simply a tuple with the name of a function and arguments, or a `fn`.

We'll add jobs to the queue using `async/2` and wait for responses with `yield/1`, like so:

```elixir
iex(1)> Riak.async(:up?, :my_pool) |> Riak.yield
{:ok, true}
iex(2)> {:put, ["bucket", "key", "value", "text/plain"]} |> Riak.async(:my_pool, reply: false)
:ok
iex(3)> {:get, ["bucket", "key"]} |> Riak.async(:my_pool) |> Riak.yield
{:ok, "value"}
iex(4)> fn riak -> :sys.get_state(riak) end |> Riak.async(:my_pool) |> Riak.yield  
{:ok,
 {:state, '127.0.0.1', 8087, false, false, #Port<0.6195>, false, :gen_tcp,
  :undefined, {[], []}, 1, [], :infinity, :undefined, :undefined, :undefined,
  :undefined, [], 100}}
```

If the queue supports it, Honeydew will send your process the result of the job unless you pass `reply: false` to `async/2`. If you don't pass it, and you never call `yield/1` to read the result, your process' mailbox will fill up.

(Ignoring the response of the `:put` above is just used as an exmaple, you probably want to check the return value of a database insert unless you have good reason to ignore it)

### Remote Queue Example

Say we've got some pretty heavy tasks that we want to distrbute over a farm of background job processing nodes, they're too heavy to process on our client-facing nodes. Let's enqueue them on a remote queue broker, we'll use RabbitMQ, so we're going to need to add some dependencies to our mix.exs:

```elixir
{:amqp, ">= 0.1.4"},
# this should go away once the otp-19 issues are fixed
{:amqp_client, git: "https://github.com/dsrosario/amqp_client.git", branch: "erlang_otp_19", override: true}
```

We'll leave out the `init/1` call from our worker module, as our tasks don't require an initial immutable state.

Here's our worker module:

```elixir
defmodule HeavyTask do
  use Honeydew

  # Note that since we didn't define an init/1 function,
  # task functions no longer take a state argument.
  def work_really_hard(secs) do
    :timer.sleep(1_000 * secs)
    IO.puts "I worked really hard for #{secs} secs!"
  end
end
```

To enqueue our jobs, we'll send them to a queue process on our client-facing node, then dequeue and work them on a separate node. Here's how to start their respective supervisors:

```elixir
#
# Our client-facing node.
# Note, "num_workers: 0"
#
def start(_type, _args) do
  children = [Honeydew.child_spec(:heavy_pool, HeavyTask, [],
                 queue: Honeydew.Queue.RabbitMQ,
                 queue_args: ["amqp://guest:guest@localhost", "heavy_pool", [prefetch: 10]],
                 num_workers: 10)]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

```elixir
#
# One of our background nodes.
#
def start(_type, _args) do
  children = [Honeydew.child_spec(:heavy_pool, HeavyTask, [],
                 queue: Honeydew.Queue.RabbitMQ,
                 queue_args: ["amqp://guest:guest@localhost", "heavy_pool", []],
                 num_workers: 0)]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

Then we can enqueue jobs just as with the local example:

```elixir
iex(1)> {:work_really_hard, [2]} |> HeavyTask.async(:heavy_pool, reply: false)
:ok
```
and on our background node, after two seconds, we'll see "I worked really hard for 2 secs!"

At present, the RabbitMQ Queue doesn't support job replies. (that is, unless the requesting and processing nodes are in the same cluster)

### Distributed Components

In a distributed Erlang scenario, you have the option of distributing Honeydew's various components around different nodes in a cluster. At its heart, Honeydew is simply a collection of queue processes and worker processes (and enqueuing processes, those that call `async/2`). For example:

- Node A runs the queue process(es), nodes B and C run worker groups, nodes D and F simply enqueue jobs.
- Each node runs its own queue and worker processes, and mutually send each other jobs to execute locally.

To start a global queue, pass a `{:global, name}` tuple when you start your supervision tree, and when enqueuing jobs:

`Honeydew.child_spec({:global, :my_pool}, MyWorker, [:some, :args])`

`fn _ -> IO.puts("hi!") end |> MyWorker.async({:global, :my_pool})`

There's one important caveat that you should note, Honeydew doesn't yet support OTP failover/takeover, so please don't use global queues in production yet. I'll send you three emoji of your choice if you submit a PR. :)

### Suspend and Resume

You can suspend a queue (halt the distribution of new jobs to workers), by calling `Honeydew.suspend(:your_pool)`, then resume with `Honeydew.resume(:your_pool)`. Note that this only instructs queues on the local node to stop distributing new jobs, if you're running a `:global` queue, it will suspend the queue on all nodes.

### Cancelling Jobs
To cancel a job that hasn't yet run, use `Honeydew.cancel/2`. If the job was successfully cancelled before execution, `:ok` will be returned. If the job wasn't present in the queue, `nil`. If the job is currently being executed (and the queue module supports this return type), `{:error, :in_progress}`.

Note that this feature may not be supported by the queue module you're using. It's best to write your jobs idepotently, regardless.

### Pool Options

`Honeydew.child_spec/4`'s last argument is a keyword list of pool options.

See the [Honeydew](https://github.com/koudelka/honeydew/blob/master/lib/honeydew.ex) module for the possible options.


## The Dungeon

### Job Lifecycle

In general, a job goes through the following stages:

- The requesting process calls `async/2`, which packages the task tuple/fn up into a "job" and sends it to a single member of the queue group.
- The queue process will enqueue the job, then, depending on its current "demand", take one of the following actions:
  - If there is outstanding demand (> 0), the queue will dispatch the job immediately to a waiting worker according to the selected dispatch strategy.
  - If there is no outstanding demand, the job will remain in the queue until demand arrives. (On nodes with zero workers (enqueue-only), demand will never arrive)
- The queue "reserves" the job (marks it as in-progress), and it's sent to the worker. The worker asks its Worker Monitor to remember the job, then executes the task.
- If the worker crashes, the worker monitor executes the selected "Failure Mode" and terminates.
  - The failure mode most likely sends a "negative acknowledgement (nack)" to the queue, which may allow another worker to try the job, or move it to a "failed" queue.
- If the job succeeds, the worker sends acknowledgement ("ack") messages to both the queue and the worker monitor.
  - If the job was enqueued without `reply: false`, and the requesting process is connected to the worker's node, the result is sent.
  - The queue process, upon receiving the "ack", will remove the job from the queue.


### Queues

Queues are the most critical location of state in Honeydew, a job will not be removed from the queue unless it has either been successfully executed, or been dealt with by the configured failure mode.

Honeydew includes a few basic queue modules:
 - A simple local/global FIFO queue implemented with the `:queue` and `Map` modules, this is the default.
 - A stateless RabbitMQ connector. Please note that `call/2` is not supported yet, only fire-and-forget `cast/2`.

If you want to implement your own queue, check out the included queues as a guide. Try to keep in mind where exactly your queue state lives, is your queue process(es) where jobs live, or is it a completely stateless connector for some external broker? Or a hybrid? I'm excited to see what you come up with, please open a PR! <3


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
        └── Honeydew.Worker
```

### TODO:
- failover/takeover for global queues
- `call/2` responses for RabbitMQ?
- durable local queues using dets?
- statistics?
- before/after job callbacks in worker module
- fix failure modes
- `await/2` and job cancellation support?
- `yield_many/2` support?
- using a global queue, control which node executes a job on-the-fly with a [ParitionDispatcher](https://hexdocs.pm/gen_stage/Experimental.GenStage.PartitionDispatcher.html)?

### Acknowledgements

Thanks to @marcelog, for his [failing worker restart strategy](http://inaka.net/blog/2012/11/29/every-day-erlang/).
