Logger.configure(level: :error)
H.seed(Pg)
pc = [limit: 3, offset: 0, count: true]
for {l, o} <- [
  {"has_many, member, Rec, NO loads (works)", %{loads: []}},
  {"has_many, member, Rec, agg_count (fails)", %{}},
  {"has_many, ADMIN, Rec, agg_count (works)", %{actor: H.admin()}},
  {"has_many, member, Rec, double_points (works)", %{loads: [:double_points]}},
  {"m2m, member, Rec, agg_count (works)", %{rel: :m2m}}] do
  IO.puts("\n### " <> l)
  {_, s} = H.run(Map.merge(%{ns: Pg, variant: "Rec", rel: :has_many, actor: H.member(), loads: [:agg_count], page: pc}, o))
  IO.puts("=> " <> String.slice(s, 0, 150))
end
