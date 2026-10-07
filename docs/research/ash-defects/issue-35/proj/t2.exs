Logger.configure(level: :error)
for ns <- [Pg, Ets], do: H.seed(ns)
nss = case System.get_env("NS") do nil -> [Pg, Ets]; s -> [Module.concat([s])] end
row = fn label, o ->
  for ns <- nss do
    {_, s} = H.run(Map.put(Map.new(o), :ns, ns))
    IO.puts("#{String.pad_trailing(inspect(ns), 4)}| #{String.pad_trailing(label, 62)}| #{String.slice(s, 0, 230)}")
  end
end
pc = [limit: 3, offset: 0, count: true]
base = %{variant: "Rec", rel: :has_many, actor: H.member(), loads: [:agg_count], page: pc}
IO.puts("\n## A. baseline claim and actor"); 
row.("member Rec has_many agg_count offset+count", base)
row.("admin  Rec has_many agg_count offset+count", %{base | actor: H.admin()})
row.("nil actor Rec has_many agg_count offset+count", %{base | actor: nil})
IO.puts("\n## B. what is loaded (member, Rec, has_many, offset+count)")
for f <- [[]] ++ Enum.map(H.fields(), &[&1]), do: row.("loads #{inspect f}", %{base | loads: f})
IO.puts("\n## C. page shape (member, Rec, has_many, agg_count)")
for {l, pg, lim} <- [{"no page, no limit", nil, nil}, {"no page, Ash.Query.limit(3)", nil, 3}, {"offset limit only", [limit: 3, offset: 0], nil}, {"offset 2 + count", [limit: 3, offset: 2, count: true], nil},
                     {"page(limit: 3) (default type)", [limit: 3], nil}, {"page(limit: 3, count: true)", [limit: 3, count: true], nil}, {"count only page(count: true)", [count: true], nil}] do
  row.(l, base |> Map.put(:page, pg) |> Map.put(:limit, lim))
end
IO.puts("\n## C2. same page shapes with NOTHING loaded")
for {l, pg, lim} <- [{"no page, Ash.Query.limit(3)", nil, 3}, {"page(limit: 3)", [limit: 3], nil}], do: row.(l, base |> Map.put(:page, pg) |> Map.put(:limit, lim) |> Map.put(:loads, []))
IO.puts("\n## C3. keyset via `after` cursor")
for ns <- nss do
  dest = H.m(ns, TaskRec)
  for {an, a} <- [admin: H.admin(), member: H.member()], loads <- [[], [:agg_count]] do
    r = try do
      %{results: [_, second | _]} = Ash.read!(Ash.Query.sort(dest, points: :asc), actor: a, page: [limit: 3])
      cur = second.__metadata__.keyset
      q = dest |> Ash.Query.for_read(:read, %{}, actor: a) |> Ash.Query.sort(points: :asc) |> Ash.Query.load(loads) |> Ash.Query.page(limit: 3, after: cur)
      p1 = Ash.read_first!(Ash.Query.do_filter(H.m(ns, Project), name: "P1"), authorize?: false)
      case Ash.get(H.m(ns, Project), p1.id, load: [tasks_rec: q], actor: a) do
        {:ok, p} -> "OK #{inspect p.tasks_rec.__struct__} points=#{inspect Enum.map(p.tasks_rec.results, & &1.points)} more?=#{p.tasks_rec.more?}"
        {:error, e} -> "ERROR " <> H.short(e)
      end
    rescue e -> "RAISED " <> H.short(e) end
    IO.puts("#{String.pad_trailing(inspect(ns), 4)}| #{String.pad_trailing("#{an} keyset after-cursor loads #{inspect loads}", 62)}| #{r}")
  end
end
IO.puts("\n## D. field policy shape on destination (member, has_many, agg_count, offset+count)")
for v <- ~w(None Rec RecOnly Act RecAgg Filt), do: row.("variant #{v}", %{base | variant: v})
row.("variant RecOnly, admin (record-dependent for admin too)", %{base | variant: "RecOnly", actor: H.admin()})
row.("variant RecAgg, member, loads double_points", %{base | variant: "RecAgg", loads: [:double_points]})
row.("variant RecAgg, member, loads agg_max", %{base | variant: "RecAgg", loads: [:agg_max]})
row.("variant RecAgg, member, no loads", %{base | variant: "RecAgg", loads: []})
IO.puts("\n## E. relationship kind / top-level (member, Rec, agg_count)")
row.("many_to_many offset+count", %{base | rel: :m2m})
row.("many_to_many no page", %{base | rel: :m2m, page: nil})
row.("many_to_many paged, no loads", %{base | rel: :m2m, loads: []})
row.("many_to_many admin offset+count", %{base | rel: :m2m, actor: H.admin()})
row.("top-level read offset+count", %{base | rel: :top})
row.("top-level read keyset", %{base | rel: :top, page: [limit: 3]})
row.("top-level read all fields", %{base | rel: :top, loads: H.fields()})
IO.puts("\n## F. how the related query is built (member, Rec, has_many, agg_count, offset+count)")
for b <- [:for_read_first, :load_first, :no_actor_in_query], do: row.("build #{b}", Map.put(base, :build, b))
row.("no sort on related query", Map.put(base, :sort, nil))
row.("action :sorted (sort from preparation)", base |> Map.put(:action, :sorted) |> Map.put(:sort, nil))
row.("select [:id, :title, :points] (secret not selected)", Map.put(base, :extra, &Ash.Query.select(&1, [:id, :title, :points])))
row.("select [:id, :points], nothing loaded", base |> Map.put(:loads, []) |> Map.put(:extra, &Ash.Query.select(&1, [:id, :points])))
row.("sort by agg_count, not loaded", %{base | loads: []} |> Map.put(:sort, [agg_count: :desc, points: :asc]))
row.("sort by agg_count AND load it", base |> Map.put(:sort, [agg_count: :desc, points: :asc]))
row.("filter agg_count > 0, not loaded", %{base | loads: []} |> Map.put(:extra, fn q -> require Ash.Query; Ash.Query.filter(q, agg_count >= 0) end))
row.("all fields at once", %{base | loads: H.fields()})
row.("all fields, admin", %{base | loads: H.fields(), actor: H.admin()})
row.("all fields, no page", %{base | loads: H.fields(), page: nil})
