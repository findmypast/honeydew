defmodule Honeydew.Job do
  defstruct private: nil, # queue's private state
            failure_private: nil, # failure mode's private state
            task: nil,
            from: nil, # if the requester wants the result, here's where to send it
            result: nil,
            by: nil # node last processed the job
end
