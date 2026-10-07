alias Demo.Tracker.{Project, Task}
require Ash.Query
Logger.configure(level: :error)
for who <- [:admin, :member, :viewer] do
  actor = Demo.Actors.fetch(Demo.Actors.id(who))
  opts = [actor: actor, tenant: actor.organization_id]
  [project | _] = Ash.read!(Project, opts ++ [page: false]) |> Enum.filter(&(&1.name == "Mobile app"))

  try_it = fn label, build ->
    q = Task |> Ash.Query.new() |> build.() |> Ash.Query.for_read(:read, %{}, opts) |> Ash.Query.page(limit: 5, offset: 0, count: true)
    res =
      try do
        case Ash.get(Project, project.id, [load: [tasks: q], not_found_error?: false] ++ opts) do
          {:ok, %{tasks: %{results: r, count: c}}} ->
            r2 = case Ash.load(r, [:comment_count, :overdue?, :headline], opts) do
              {:ok, l} -> "then Ash.load ok: " <> inspect(Enum.map(l, & &1.comment_count))
              {:error, e} -> "then Ash.load ERROR " <> String.slice(Exception.message(e), 0, 80)
            end
            "page of #{length(r)}, count #{inspect(c)}; est=#{inspect(Enum.map(r, &(case &1.estimate_hours do %Ash.ForbiddenField{} -> :f; v -> v && Decimal.to_string(v) end)))} #{r2}"
          {:error, e} -> "ERROR " <> (Exception.message(e) |> String.split("\n") |> Enum.find("", &(&1 =~ "**")) |> String.slice(0, 110))
        end
      rescue
        e -> "RAISED " <> String.slice(Exception.message(e), 0, 150)
      end
    IO.puts("#{who} #{String.pad_trailing(label, 44)} #{res}")
  end

  try_it.("plain", & &1)
  try_it.("load aggregate", &Ash.Query.load(&1, [:comment_count]))
  try_it.("sort_input by aggregate, not loaded", &Ash.Query.sort_input(&1, ["-comment_count"]))
  try_it.("filter_input by aggregate, not loaded", &Ash.Query.filter_input(&1, %{comment_count: %{greater_than: 0}}))
  try_it.("sort_input by expr calc, not loaded", &Ash.Query.sort_input(&1, ["overdue?"]))
  try_it.("filter estimate > 10", &Ash.Query.filter_input(&1, %{estimate_hours: %{greater_than: 10}}))
end
