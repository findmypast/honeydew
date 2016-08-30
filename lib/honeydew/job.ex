defmodule Honeydew.Job do
  defstruct private: nil, # queue implementation's private metadata
            task: nil,
            from: nil, # if the requester wants the result, here's where to send it
            result: nil,
            by: nil # who last processed the job
end
