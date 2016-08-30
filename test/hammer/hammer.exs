defmodule Honeydew.Hammer do
  use Honeydew

  def init(args) do
    {:ok, args}
  end

  def echo(arg, _state) do
    arg
  end

end

defmodule Honeydew.Hammer do

  @num_jobs 50_000

  def run(sync) do
    {microsecs, :ok} = :timer.tc(__MODULE__, sync, [])
    IO.puts("processed #{@num_jobs} in #{microsecs/:math.pow(10, 6)}s")
  end

  def async do
    Enum.map(0..@num_jobs, fn _ ->
      Task.async(fn ->
        :hi = Honeydew.HammerHoney.call({:echo, [:hi]})
      end)
    end)
    |> Enum.each(fn task -> Task.await(task, :infinity) end)
  end

  def send_sync do
    Enum.each(0..@num_jobs, fn _ ->
      Riemann.send(@event)
    end)
  end

end

Honeydew.Hammer.run(:async)
