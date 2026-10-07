alias Demo.Tracker.{Project, Task}
require Ash.Query
Logger.configure(level: :error)
member = Demo.Actors.fetch(Demo.Actors.id(:member))
opts = [actor: member, tenant: member.organization_id]
[project | _] = Ash.read!(Project, opts ++ [page: false]) |> Enum.filter(&(&1.name == "Mobile app"))

try_it = fn label, loads, page ->
  q = Task |> Ash.Query.new() |> Ash.Query.load(loads) |> Ash.Query.for_read(:read, %{}, opts)
  q = if page, do: Ash.Query.page(q, page), else: q
  res =
    try do
      case Ash.get(Project, project.id, [load: [tasks: q], not_found_error?: false] ++ opts) do
        {:ok, %{tasks: %{results: r, count: c}}} -> "page of #{length(r)}, count #{inspect(c)}"
        {:ok, %{tasks: r}} when is_list(r) -> "list of #{length(r)}"
        {:error, e} -> "ERROR " <> (Exception.message(e) |> String.split("\n") |> Enum.find("", &(&1 =~ "Ecto.QueryError" or &1 =~ "**")) |> String.slice(0, 150))
      end
    rescue
      e -> "RAISED " <> String.slice(Exception.message(e), 0, 150)
    end
  IO.puts("#{String.pad_trailing(label, 60)} #{res}")
end

for {l, loads} <- [{"no loads", []}, {"overdue? (expr calc)", [:overdue?]}, {"comment_count (aggregate)", [:comment_count]}, {"headline (module calc)", [:headline]}, {"all three", [:overdue?, :comment_count, :headline]}] do
  try_it.("member, offset page+count, " <> l, loads, [limit: 25, offset: 0, count: true])
  try_it.("member, offset page no count, " <> l, loads, [limit: 25, offset: 0])
  try_it.("member, keyset page, " <> l, loads, [limit: 25])
  try_it.("member, no page, " <> l, loads, nil)
end
