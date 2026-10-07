defmodule Bug.Repo do
  use AshPostgres.Repo, otp_app: :bug
  def installed_extensions, do: ["ash-functions"]
  def prefer_transaction?, do: false
  # diagnostic only: prints the caller's stack and the query before Ecto plans it
  def prepare_query(_op, query, opts) do
    if Process.get(:bug_trace) do
      {:current_stacktrace, st} = Process.info(self(), :current_stacktrace)
      IO.puts("--- prepare_query called from:\n" <> Exception.format_stacktrace(Enum.slice(st, 2, 12)))
      IO.puts("--- select expr: " <> inspect(query.select && query.select.expr, limit: :infinity, printable_limit: :infinity) |> String.slice(0, 1500))
    end
    {query, opts}
  end
  def min_pg_version, do: %Version{major: 16, minor: 0, patch: 0}
end
defmodule Bug.Application do
  use Application
  def start(_, _), do: Supervisor.start_link([Bug.Repo], strategy: :one_for_one)
end
