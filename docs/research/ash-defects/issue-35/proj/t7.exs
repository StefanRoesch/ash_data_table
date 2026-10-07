Logger.configure(level: :error)
require Ash.Query
H.seed(Pg)
a = H.member()
p1 = Ash.read_first!(Ash.Query.filter(Pg.Project, name == "P1"), authorize?: false)
step = fn label, f -> r = try do f.() rescue e -> {:raised, H.short(e)} end
  IO.puts(String.pad_trailing(label, 84) <> "| " <> (case r do {:raised, m} -> "RAISED " <> m; {:error, e} -> "ERROR " <> H.short(e); {:ok, x} -> "OK " <> String.slice(inspect(x), 0, 110); x -> "OK " <> String.slice(inspect(x), 0, 110) end)); r end
q = Pg.TaskRec |> Ash.Query.for_read(:read, %{}, actor: a) |> Ash.Query.sort(points: :desc)
page = Ash.get!(Pg.Project, p1.id, load: [tasks_rec: Ash.Query.page(q, limit: 3, offset: 2, count: true)], actor: a).tasks_rec
IO.puts("bare paged relationship load: ok, n=#{length(page.results)}")
IO.puts("## N. step two of the workaround, field by field (Pg, member, TaskRec)")
for f <- H.fields() ++ [:agg_count_pol, :agg_count_calc], do: step.("Ash.load(records, [#{inspect f}], actor: member)", fn -> with {:ok, l} <- Ash.load(page.results, [f], actor: a), do: {:ok, Enum.map(l, &Map.get(&1, f))} end)
step.("Ash.load(records, all fields)", fn -> with {:ok, l} <- Ash.load(page.results, H.fields() ++ [:agg_count_pol, :agg_count_calc], actor: a), do: {:ok, length(l)} end)
IO.puts("## N2. the top-level read, same actor")
tq = fn fs, pg -> Pg.TaskRec |> Ash.Query.for_read(:read, %{}, actor: a) |> Ash.Query.filter(project_id == ^p1.id) |> Ash.Query.sort(points: :desc) |> Ash.Query.load(fs) |> Ash.read(actor: a, page: pg) end
step.("top-level offset page, H.fields()", fn -> with {:ok, p} <- tq.(H.fields(), [limit: 3, offset: 2, count: true]), do: {:ok, length(p.results)} end)
for f <- [:agg_count_pol, :agg_count_calc, :agg_count], pg <- [[limit: 3, offset: 2, count: true], [limit: 3]], do: step.("top-level #{inspect pg} load [#{inspect f}]", fn -> with {:ok, p} <- tq.([f], pg), do: {:ok, Enum.map(p.results, &Map.get(&1, f))} end)
step.("top-level, NOT paged, load [:agg_count_calc]", fn -> with {:ok, p} <- tq.([:agg_count_calc], false), do: {:ok, length(p)} end)
step.("top-level, NOT paged, load [:agg_count_calc], ADMIN", fn -> Pg.TaskRec |> Ash.Query.load(:agg_count_calc) |> Ash.read(actor: H.admin()) |> then(fn {:ok, l} -> {:ok, length(l)}; e -> e end) end)
step.("top-level, NOT paged, TaskNone load [:agg_count_calc], member", fn -> Pg.TaskNone |> Ash.Query.load(:agg_count_calc) |> Ash.read(actor: a) |> then(fn {:ok, l} -> {:ok, length(l)}; e -> e end) end)
step.("top-level, NOT paged, TaskRec load [:agg_count_calc, :agg_count], member", fn -> Pg.TaskRec |> Ash.Query.load([:agg_count_calc, :agg_count]) |> Ash.read(actor: a) |> then(fn {:ok, l} -> {:ok, length(l)}; e -> e end) end)
