alias Experimental.GenStage

defmodule Honeydew.FailureMode.Abandon do
  require Logger
  alias Honeydew.Job

  @behaviour Honeydew.FailureMode

  def handle_failure(pool, %Job{from: from} = job, reason, []) do
    Logger.info "Job failed: #{inspect job}"

    # tell the queue that that job can be removed.
    pool
    |> Honeydew.get_queue
    |> GenStage.cast({:ack, job})

    # send the error to the awaiting process, if necessary
    with {owner, _ref} <- from,
      do: send(owner, %{job | result: {:exit, reason}})
  end
end
