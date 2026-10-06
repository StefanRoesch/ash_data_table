defmodule Demo.Perf do
  @moduledoc """
  The domain of the performance scripts' one resource, `Demo.Perf.Task`. It
  exists in the perf environment only (`perf/server`).
  """
  use Ash.Domain, otp_app: :demo, extensions: [AshTable.Domain]

  resources do
    resource Demo.Perf.Task
  end
end

defmodule Demo.Perf.TaskSource do
  @moduledoc """
  Defines `Demo.Perf.Task`: the demo's `Demo.Tracker.Task`, word for word,
  with pages of 100 in place of 25.

  A table's page size is its read action's `default_limit`, and the table at
  /tasks has no control for it. To measure the same table at 100 rows, the
  performance scripts need the same resource with another `default_limit`.
  Writing it out a second time would let the two drift apart, so it is made
  from the source of the first: three places are replaced and the rest is
  compiled as it stands, with the same table, columns, actions, policies and
  field policies.
  """
  @path Path.expand("../../lib/demo/tracker/task.ex", __DIR__)
  @external_resource @path

  replace = fn source, from, to ->
    case String.split(source, from, parts: 2) do
      [before, rest] -> before <> to <> rest
      [_all] -> raise "#{@path} no longer contains #{inspect(from)}; see #{__ENV__.file}"
    end
  end

  @path
  |> File.read!()
  |> replace.("defmodule Demo.Tracker.Task do", "defmodule Demo.Perf.Task do")
  |> replace.("domain: Demo.Tracker,", "domain: Demo.Perf,")
  # the first one is the primary read action's, which the table reads with
  |> replace.("default_limit: 25", "default_limit: 100")
  |> Code.compile_string(@path)
end
