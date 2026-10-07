Logger.configure(level: :error)
require Ash.Query
H.seed(Pg)
p1 = Ash.read_first!(Ash.Query.filter(Pg.Project, name == "P1"), authorize?: false)
IO.puts("## O. TOP-LEVEL reads (no relationship) on Postgres")
t = fn label, res, actor, fs, pg, sort ->
  r = try do
    q = res |> Ash.Query.for_read(:read, %{}, actor: actor) |> Ash.Query.filter(project_id == ^p1.id) |> Ash.Query.load(fs)
    q = if sort, do: Ash.Query.sort(q, sort), else: q
    case Ash.read(q, actor: actor, page: pg) do {:ok, %{results: r}} -> "OK n=#{length(r)}"; {:ok, r} -> "OK n=#{length(r)}"; {:error, e} -> "ERROR " <> H.short(e) end
  rescue e -> "RAISED " <> H.short(e) end
  IO.puts("=> #{String.pad_trailing(label, 88)}| #{String.slice(r, 0, 120)}")
end
m = H.member(); pg = [limit: 3, offset: 2, count: true]
t.("TaskRec member paged [:agg_count, :agg_count_calc]", Pg.TaskRec, m, [:agg_count, :agg_count_calc], pg, [points: :desc])
t.("TaskRec member paged [:agg_count_calc]", Pg.TaskRec, m, [:agg_count_calc], pg, [points: :desc])
t.("TaskRec member paged [:agg_max, :agg_count_calc]", Pg.TaskRec, m, [:agg_max, :agg_count_calc], pg, [points: :desc])
t.("TaskRec member paged [:agg_count, :double_points]", Pg.TaskRec, m, [:agg_count, :double_points], pg, [points: :desc])
t.("TaskRec member NOT paged [:agg_max, :agg_count_calc]", Pg.TaskRec, m, [:agg_max, :agg_count_calc], false, [points: :desc])
t.("TaskRec member NOT paged, no sort [:agg_max, :agg_count_calc]", Pg.TaskRec, m, [:agg_max, :agg_count_calc], false, nil)
t.("TaskRec ADMIN paged [:agg_max, :agg_count_calc]", Pg.TaskRec, H.admin(), [:agg_max, :agg_count_calc], pg, [points: :desc])
t.("TaskNone member paged [:agg_max, :agg_count_calc]", Pg.TaskNone, m, [:agg_max, :agg_count_calc], pg, [points: :desc])
t.("TaskAct member paged [:agg_max, :agg_count_calc]", Pg.TaskAct, m, [:agg_max, :agg_count_calc], pg, [points: :desc])
t.("TaskRec member paged all H.fields()", Pg.TaskRec, m, H.fields(), pg, [points: :desc])
t.("TaskRec member paged H.fields() ++ [:agg_count_calc]", Pg.TaskRec, m, H.fields() ++ [:agg_count_calc], pg, [points: :desc])
t.("TaskRec member paged H.fields() ++ [:agg_count_pol]", Pg.TaskRec, m, H.fields() ++ [:agg_count_pol], pg, [points: :desc])
if System.get_env("BUG_DIAG") do
  Process.put(:bug_trace, true)
  t.("TRACE: TaskRec member NOT paged [:agg_max, :agg_count_calc]", Pg.TaskRec, m, [:agg_max, :agg_count_calc], false, nil)
end
