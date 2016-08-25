defmodule Honeydew.FailureMode do
  alias Honeydew.Job

  @type job :: %Job{}
  @type queue :: any

  @callback handle_failure(atom, job) :: queue
end
