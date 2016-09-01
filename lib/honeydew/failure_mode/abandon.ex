alias Experimental.GenStage

defmodule Honeydew.FailureMode.Abandon do
  require Logger

  @behaviour Honeydew.FailureMode

  def handle_failure(pool, job, []) do
    Logger.info "Job failed: #{inspect job}"

    pool
    |> Honeydew.get_queue
    |> GenStage.cast({:ack, job})
  end
end
