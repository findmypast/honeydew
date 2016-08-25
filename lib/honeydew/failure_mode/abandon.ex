alias Experimental.GenStage

defmodule Honeydew.FailureMode.Abandon do
  require Logger

  def handle_failure(pool, job) do
    Logger.warn "Job failed: #{inspect job}"

    pool
    |> Honeydew.queue_group
    |> :pg2.get_closest_pid
    |> GenStage.cast({:ack, job})
  end

end
