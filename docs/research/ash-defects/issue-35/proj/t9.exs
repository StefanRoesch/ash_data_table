Logger.configure(level: :error)
require Ash.Query
H.seed(Pg)
m = H.member()
fails? = fn res, actor, fs, pg, sort ->
  q = res |> Ash.Query.for_read(:read, %{}, actor: actor) |> Ash.Query.load(fs)
  q = if sort, do: Ash.Query.sort(q, sort), else: q
  r = try do Ash.read(q, actor: actor, page: pg) rescue e -> {:error, e} end
  match?({:error, _}, r)
end
all = H.fields() ++ [:agg_count_calc]
min = Enum.reduce(all, all, fn f, acc -> if fails?.(Pg.TaskRec, m, acc -- [f], [limit: 3, offset: 0], [points: :desc]), do: acc -- [f], else: acc end)
IO.puts("## P. minimal failing load set for a TOP-LEVEL paged read (Pg.TaskRec, member): #{inspect min}")
for {l, res, a, pg, sort} <- [
  {"TaskRec member page(limit 3, offset 0), sort points", Pg.TaskRec, m, [limit: 3, offset: 0], [points: :desc]},
  {"TaskRec member page(limit 3, offset 0, count), sort points", Pg.TaskRec, m, [limit: 3, offset: 0, count: true], [points: :desc]},
  {"TaskRec member page(limit 3) no sort", Pg.TaskRec, m, [limit: 3], nil},
  {"TaskRec member NOT paged", Pg.TaskRec, m, false, [points: :desc]},
  {"TaskRec ADMIN paged", Pg.TaskRec, H.admin(), [limit: 3, offset: 0], [points: :desc]},
  {"TaskRecOnly ADMIN paged", Pg.TaskRecOnly, H.admin(), [limit: 3, offset: 0], [points: :desc]},
  {"TaskNone member paged", Pg.TaskNone, m, [limit: 3, offset: 0], [points: :desc]},
  {"TaskAct member paged", Pg.TaskAct, m, [limit: 3, offset: 0], [points: :desc]},
  {"Ets.TaskRec member paged", Ets.TaskRec, m, [limit: 3, offset: 0], [points: :desc]}] do
  IO.puts("#{String.pad_trailing(l, 64)}| load #{inspect min} => #{if fails?.(res, a, min, pg, sort), do: "ERROR", else: "OK"}")
end
q = Pg.TaskRec |> Ash.Query.for_read(:read, %{}, actor: m) |> Ash.Query.load(min) |> Ash.Query.sort(points: :desc)
{:error, e} = Ash.read(q, actor: m, page: [limit: 3, offset: 0])
IO.puts(Exception.message(e) |> String.slice(0, 5000))
