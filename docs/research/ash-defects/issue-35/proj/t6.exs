Logger.configure(level: :error)
require Ash.Query
import Ash.Expr
for ns <- [Pg, Ets], do: H.seed(ns)
# :agg_count_calc is left out of the comparison: together with two aggregates it makes the TOP-LEVEL comparator read fail (section P/Q)
all_fields = H.fields() ++ [:agg_count_pol, :agg_count_calc]
fields = H.fields() ++ [:agg_count_pol]
show = fn v -> case v do %Ash.ForbiddenField{} -> :FORBIDDEN; %Ash.NotLoaded{} -> :NOT_LOADED; v -> v end end
proj = fn recs, fs -> Enum.map(recs, fn r -> {r.points, Map.new([:secret | fs], &{&1, show.(Map.get(r, &1))})} end) end
IO.puts("## L. the workaround: bare paged relationship load, then Ash.load(records, loads, actor:) -- compared with ONE top-level read as the same actor")
for ns <- [Pg, Ets], v <- ["Rec", "RecAgg", "Act", "None"], {an, a} <- [member: H.member(), admin: H.admin()], {pl, pg} <- [offset: [limit: 3, offset: 2, count: true], keyset: [limit: 3]] do
  dest = H.m(ns, "Task#{v}"); rel = :"tasks_#{String.downcase(v)}"
  p1 = Ash.read_first!(Ash.Query.filter(H.m(ns, Project), name == "P1"), authorize?: false)
  q = dest |> Ash.Query.for_read(:read, %{}, actor: a) |> Ash.Query.sort(agg_max: :desc_nils_last, points: :desc)
  # sort by an aggregate kept in the query only where it works
  q = if ns == Pg and an == :member and v in ["Rec", "RecAgg"], do: dest |> Ash.Query.for_read(:read, %{}, actor: a) |> Ash.Query.sort(points: :desc), else: q
  # a real keyset page needs a cursor when the default page type is offset
  pg = if pl == :keyset do
    %{results: [first | _]} = Ash.read!(Ash.Query.filter(q, project_id == ^p1.id), actor: a, page: [limit: 1])
    [limit: 3, after: first.__metadata__.keyset]
  else pg end
  sort = q.sort
  res =
    try do
      page = Ash.get!(H.m(ns, Project), p1.id, load: [{rel, Ash.Query.page(q, pg)}], actor: a) |> Map.get(rel)
      loaded = Ash.load!(page.results, fields, actor: a)
      top = dest |> Ash.Query.for_read(:read, %{}, actor: a) |> Ash.Query.filter(project_id == ^p1.id) |> Ash.Query.sort(sort) |> Ash.Query.load(fields) |> Ash.read!(actor: a, page: pg)
      same_order = Enum.map(loaded, & &1.id) == Enum.map(page.results, & &1.id)
      same_as_top = proj.(loaded, fields) == proj.(top.results, fields)
      keysets = Enum.map(loaded, & &1.__metadata__[:keyset]) == Enum.map(page.results, & &1.__metadata__[:keyset])
      extra = if same_as_top, do: "", else: "\n   workaround: #{inspect(proj.(loaded, fields), limit: :infinity)}\n   top-level:  #{inspect(proj.(top.results, fields), limit: :infinity)}"
      "#{inspect page.__struct__} n=#{length(loaded)} count=#{inspect page.count}/top #{inspect top.count} order_kept=#{same_order} keyset_metadata_kept=#{keysets} (present: #{Enum.all?(loaded, & &1.__metadata__[:keyset])}) EQUAL_TO_TOP_LEVEL_READ=#{same_as_top}" <> extra
    rescue e -> "RAISED " <> H.short(e) end
  IO.puts("#{inspect ns} #{String.pad_trailing(v, 7)} #{String.pad_trailing(to_string(an), 7)} #{String.pad_trailing(to_string(pl), 7)}| #{res}")
end
IO.puts("\n## L2. what the member gets, Pg, variant Rec and RecAgg (values, to read by eye)")
for v <- ["Rec", "RecAgg"] do
  a = H.member(); dest = H.m(Pg, "Task#{v}"); rel = :"tasks_#{String.downcase(v)}"
  p1 = Ash.read_first!(Ash.Query.filter(Pg.Project, name == "P1"), authorize?: false)
  page = Ash.get!(Pg.Project, p1.id, load: [{rel, dest |> Ash.Query.for_read(:read, %{}, actor: a) |> Ash.Query.sort(points: :asc) |> Ash.Query.page(limit: 7, count: true)}], actor: a) |> Map.get(rel)
  for {pts, m} <- proj.(Ash.load!(page.results, all_fields, actor: a), [:agg_count, :agg_count_pol, :agg_max_protected, :agg_count_calc, :secret_calc, :double_points]), do: IO.puts("  #{v} t#{pts}: #{inspect m}")
  base = dest |> Ash.Query.filter(project_id == ^p1.id) |> Ash.Query.sort(points: :asc) |> Ash.Query.load(all_fields) |> Ash.read!(authorize?: false)
  IO.puts("  (unauthorized baseline agg_count=#{inspect Enum.map(base, & &1.agg_count)} agg_count_pol=#{inspect Enum.map(base, & &1.agg_count_pol)} agg_max_protected=#{inspect Enum.map(base, & &1.agg_max_protected)})")
end
IO.puts("\n## M. single-statement alternatives inside the paged relationship load (Pg, member)")
row = fn label, o ->
  {res, s} = H.run(Map.merge(%{ns: Pg, variant: "Rec", rel: :has_many, actor: H.member(), loads: [], page: [limit: 7, offset: 0, count: true]}, Map.new(o)))
  vals = case res do {:ok, %{results: r}} -> " values=" <> inspect(Enum.map(r, &{show.(Map.get(&1, :agg_count_calc)), show.(&1.calculations[:c])})); _ -> "" end
  IO.puts("#{String.pad_trailing(label, 78)}| #{String.slice(s, 0, 110)}#{vals}")
end
row.("Rec: load resource calc agg_count_calc = expr(agg_count)", %{loads: [:agg_count_calc]})
row.("Rec: Ash.Query.calculate(:c, :integer, expr(agg_count))", %{extra: &Ash.Query.calculate(&1, :c, :integer, expr(agg_count))})
row.("RecAgg (agg_count itself protected): load agg_count_calc", %{variant: "RecAgg", loads: [:agg_count_calc]})
row.("RecAgg: Ash.Query.calculate(:c, :integer, expr(agg_count))", %{variant: "RecAgg", extra: &Ash.Query.calculate(&1, :c, :integer, expr(agg_count))})
row.("Rec: select without the protected field + load agg_count", %{loads: [:agg_count], extra: &Ash.Query.select(&1, [:id, :title, :points, :assignee_id, :project_id])})
row.("Rec: Ash.Query.aggregate(:x, :count, :comments) only", %{extra: &Ash.Query.aggregate(&1, :x, :count, :comments)})
