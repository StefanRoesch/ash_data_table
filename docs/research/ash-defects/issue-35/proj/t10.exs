Logger.configure(level: :error)
require Ash.Query
H.seed(Pg); m = H.member()
IO.puts("## Q. top-level paged read, Pg.TaskRec, member: which third load triggers it (with [:agg_count, :agg_count_calc])")
for f <- (H.fields() -- [:agg_count]) ++ [:agg_count_pol] do
  fs = [:agg_count, f, :agg_count_calc]
  q = Pg.TaskRec |> Ash.Query.for_read(:read, %{}, actor: m) |> Ash.Query.load(fs) |> Ash.Query.sort(points: :asc)
  r = case (try do Ash.read(q, actor: m, page: [limit: 7, offset: 0, count: true]) rescue e -> {:error, e} end) do
    {:ok, p} ->
      base = Pg.TaskRec |> Ash.Query.load(fs) |> Ash.Query.sort(points: :asc) |> Ash.read!(authorize?: false, page: [limit: 7])
      "OK n=#{length(p.results)} count=#{p.count} values_equal_unauthorized_baseline=#{Enum.map(p.results, &Map.take(&1, [:id | fs])) == Enum.map(base.results, &Map.take(&1, [:id | fs]))}"
    {:error, e} -> "ERROR " <> String.slice(H.short(e), 0, 60)
  end
  IO.puts("#{String.pad_trailing(inspect(fs), 60)}| #{r}")
end
