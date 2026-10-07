Logger.configure(level: :error)
require Ash.Query
import Ash.Expr
for ns <- [Pg, Ets], do: H.seed(ns)
row = fn label, o ->
  for ns <- [Pg, Ets] do
    {_, s} = H.run(Map.put(Map.new(o), :ns, ns))
    IO.puts("#{String.pad_trailing(inspect(ns), 4)}| #{String.pad_trailing(label, 70)}| #{String.slice(s, 0, 200)}")
  end
end
pc = [limit: 3, offset: 0, count: true]
none = %{variant: "None", rel: :has_many, actor: H.member(), loads: [], page: pc}
rec = %{none | variant: "Rec"}
IO.puts("## G. NO field policy at all: anonymous calculation / aggregate on the related query")
calc = &Ash.Query.calculate(&1, :anon, :integer, expr(points * 2))
agg = &Ash.Query.aggregate(&1, :anon_agg, :count, :comments)
row.("None: Ash.Query.calculate only, paged", Map.put(none, :extra, calc))
row.("None: Ash.Query.calculate + load agg_count, paged", none |> Map.put(:extra, calc) |> Map.put(:loads, [:agg_count]))
row.("None: Ash.Query.calculate + load agg_count, ADMIN, paged", none |> Map.put(:extra, calc) |> Map.put(:loads, [:agg_count]) |> Map.put(:actor, H.admin()))
row.("None: Ash.Query.calculate + load agg_count, authorize off-ish nil actor", none |> Map.put(:extra, calc) |> Map.put(:loads, [:agg_count]) |> Map.put(:actor, nil))
row.("None: Ash.Query.calculate + load agg_count, NOT paged", none |> Map.put(:extra, calc) |> Map.put(:loads, [:agg_count]) |> Map.put(:page, nil))
row.("None: Ash.Query.calculate + load agg_count, m2m paged", none |> Map.put(:extra, calc) |> Map.put(:loads, [:agg_count]) |> Map.put(:rel, :m2m))
row.("None: Ash.Query.calculate + load agg_count, top-level paged", none |> Map.put(:extra, calc) |> Map.put(:loads, [:agg_count]) |> Map.put(:rel, :top))
row.("None: Ash.Query.calculate + load double_points, paged", none |> Map.put(:extra, calc) |> Map.put(:loads, [:double_points]))
row.("None: Ash.Query.aggregate only, paged", Map.put(none, :extra, agg))
row.("None: Ash.Query.aggregate + load agg_count, paged", none |> Map.put(:extra, agg) |> Map.put(:loads, [:agg_count]))
row.("None: Ash.Query.aggregate + Ash.Query.calculate, paged", none |> Map.put(:extra, &(&1 |> calc.() |> agg.())))
row.("None: load double_points + agg_count, paged", %{none | loads: [:double_points, :agg_count]})
IO.puts("## H. sorting/filtering by an aggregate (Rec, member, paged)")
row.("sort [agg_count: :desc, points: :asc], not loaded", Map.put(rec, :sort, [agg_count: :desc, points: :asc]))
row.("sort_input [-agg_count, points], not loaded", rec |> Map.put(:sort, nil) |> Map.put(:extra, &Ash.Query.sort_input(&1, ["-agg_count", "points"])))
row.("action :sorted + sort_input -agg_count", rec |> Map.put(:sort, nil) |> Map.put(:action, :sorted) |> Map.put(:extra, &Ash.Query.sort_input(&1, ["-agg_count"])))
row.("sort [agg_count: :desc, points: :asc], ADMIN", rec |> Map.put(:sort, [agg_count: :desc, points: :asc]) |> Map.put(:actor, H.admin()))
row.("sort [agg_max: :desc, points: :asc], not loaded", Map.put(rec, :sort, [agg_max: :desc, points: :asc]))
row.("sort [agg_first: :desc, points: :asc], not loaded", Map.put(rec, :sort, [agg_first: :desc, points: :asc]))
row.("sort [double_points: :desc], not loaded", Map.put(rec, :sort, [double_points: :desc]))
row.("filter agg_count > 1", Map.put(rec, :extra, &Ash.Query.filter(&1, agg_count > 1)))
row.("filter_input agg_count greater_than 1", Map.put(rec, :extra, &Ash.Query.filter_input(&1, %{agg_count: %{greater_than: 1}})))
row.("filter secret == \"s2\" (protected field)", Map.put(rec, :extra, &Ash.Query.filter_input(&1, %{secret: %{in: ["s1", "s2", "s3"]}})))
row.("top-level: filter_input secret in [s1,s2,s3]", rec |> Map.put(:rel, :top) |> Map.put(:extra, &Ash.Query.filter_input(&1, %{secret: %{in: ["s1", "s2", "s3"]}})))
