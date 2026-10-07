Logger.configure(level: :error)
require Ash.Query
for ns <- [Pg, Ets], do: H.seed(ns)
IO.puts("## K. config: #{inspect(Application.get_all_env(:ash) |> Keyword.take([:show_keysets_for_all_actions?, :default_page_type]))}")
row = fn label, o ->
  for ns <- [Pg] do
    {_, s} = H.run(Map.put(Map.new(o), :ns, ns))
    IO.puts("#{String.pad_trailing(inspect(ns), 4)}| #{String.pad_trailing(label, 70)}| #{String.slice(s, 0, 200)}")
  end
end
rec = %{variant: "Rec", rel: :has_many, actor: H.member(), loads: [], page: [limit: 3, offset: 0, count: true], sort: [agg_count: :desc, points: :asc]}
row.("offset page, sort by agg_count, not loaded", rec)
row.("page(limit: 3) no offset, sort by agg_count, not loaded", %{rec | page: [limit: 3]})
row.("offset page, sort by points, load agg_count", %{rec | loads: [:agg_count], sort: [points: :asc]})
cur = fn actor, sort ->
  %{results: [_, second | _]} = Ash.read!(Ash.Query.sort(Pg.TaskRec, sort), actor: actor, page: [limit: 3])
  second.__metadata__.keyset
end
row.("keyset page AFTER cursor, sort by agg_count, not loaded", %{rec | page: [limit: 3, after: cur.(H.member(), rec.sort)]})
row.("keyset page AFTER cursor, sort by points, nothing loaded", %{rec | sort: [points: :asc], page: [limit: 3, after: cur.(H.member(), [points: :asc])]})
row.("keyset AFTER cursor, sort by agg_count, ADMIN", %{rec | actor: H.admin(), page: [limit: 3, after: cur.(H.admin(), rec.sort)]})
