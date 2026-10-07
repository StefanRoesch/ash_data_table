# The claim, verbatim shape, on both data layers.
require Ash.Query
for ns <- [Pg, Ets] do
  p1 = H.seed(ns)
  IO.puts("== #{inspect ns}")
  for {an, a} <- [admin: H.admin(), member: H.member()] do
    dest = H.m(ns, TaskRec)
    related_query = Ash.Query.for_read(dest, :read, %{}, actor: a) |> Ash.Query.load(:agg_count) |> Ash.Query.page(limit: 3, count: true)
    r = try do Ash.get(H.m(ns, Project), p1.id, load: [{:tasks_rec, related_query}], actor: a) rescue e -> {:raised, e} end
    case r do
      {:ok, p} -> IO.puts("#{an}: OK #{inspect(p.tasks_rec.__struct__)} count=#{inspect(p.tasks_rec.count)} #{inspect(Enum.map(p.tasks_rec.results, &{&1.title, &1.agg_count, &1.secret}))}")
      {:error, e} -> IO.puts("#{an}: ERROR\n" <> Exception.message(e))
      {:raised, e} -> IO.puts("#{an}: RAISED\n" <> Exception.message(e))
    end
  end
end
