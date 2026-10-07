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
rec = %{variant: "Rec", rel: :m2mu, actor: H.member(), loads: [:agg_count], page: pc}
IO.puts("## I. many_to_many through a join resource with a composite primary key (lateral join)")
row.("m2m(unique join) member paged agg_count", rec)
row.("m2m(unique join) member paged no loads", %{rec | loads: []})
row.("m2m(unique join) member NOT paged agg_count", %{rec | page: nil})
row.("m2m(unique join) member NOT paged, sorted none, agg_count", %{rec | page: nil} |> Map.put(:sort, nil))
row.("m2m(unique join) admin paged agg_count", %{rec | actor: H.admin()})
row.("m2m(unique join) member paged double_points", %{rec | loads: [:double_points]})
row.("m2m(unique join) variant None member paged agg_count", %{rec | variant: "None"})
row.("m2m(unique join) variant Act member paged agg_count", %{rec | variant: "Act"})
IO.puts("## J. has_one from_many? (always a lateral join; no paging involved)")
ho = %{rec | rel: :has_one, page: nil}
row.("has_one from_many member, agg_count", ho)
row.("has_one from_many member, no loads", %{ho | loads: []})
row.("has_one from_many admin, agg_count", %{ho | actor: H.admin()})
row.("has_one from_many member, double_points", %{ho | loads: [:double_points]})
row.("has_one from_many member, variant None, agg_count", %{ho | variant: "None"})
row.("has_one from_many member, variant Act, agg_count", %{ho | variant: "Act"})
