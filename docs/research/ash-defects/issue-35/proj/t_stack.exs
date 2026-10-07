p1 = H.seed(Pg); a = H.member()
q = Ash.Query.for_read(Pg.TaskRec, :read, %{}, actor: a) |> Ash.Query.load(:agg_count) |> Ash.Query.sort(points: :asc) |> Ash.Query.page(limit: 3, count: true)
Process.put(:bug_trace, true)
# async?: false-ish: run the load in this process so that the process flag is seen
{:error, e} = Ash.get(Pg.Project, p1.id, load: [tasks_rec: q], actor: a)
IO.puts(H.short(e))
