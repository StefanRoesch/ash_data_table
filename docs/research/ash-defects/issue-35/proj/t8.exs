Logger.configure(level: :error)
require Ash.Query
import Ash.Expr
for ns <- [Pg, Ets], do: H.seed(ns)
IO.puts("## O. TOP-LEVEL reads (no relationship): a calculation that refers to an aggregate, plus other loads")
t = fn label, res, actor, fs, pg, extra ->
  for ns <- [Pg, Ets] do
    res = H.m(ns, res)
    r = try do
      q = res |> Ash.Query.for_read(:read, %{}, actor: actor) |> Ash.Query.sort(points: :desc) |> Ash.Query.load(fs) |> extra.()
      case Ash.read(q, actor: actor, page: pg) do {:ok, %{results: r}} -> "OK n=#{length(r)}"; {:ok, r} -> "OK n=#{length(r)}"; {:error, e} -> "ERROR " <> H.short(e) end
    rescue e -> "RAISED " <> H.short(e) end
    IO.puts("#{String.pad_trailing(inspect(ns), 4)}| #{String.pad_trailing(label, 78)}| #{String.slice(r, 0, 110)}")
  end
end
m = H.member(); pg = [limit: 3, offset: 2, count: true]; id = & &1
for f <- H.fields(), do: t.("TaskRec member paged [#{inspect f}, :agg_count_calc]", TaskRec, m, [f, :agg_count_calc], pg, id)
all = H.fields() ++ [:agg_count_calc]
t.("TaskRec member paged ALL + agg_count_calc", TaskRec, m, all, pg, id)
t.("TaskRec member NOT paged ALL + agg_count_calc", TaskRec, m, all, false, id)
t.("TaskRec ADMIN paged ALL + agg_count_calc", TaskRec, H.admin(), all, pg, id)
t.("TaskNone member paged ALL + agg_count_calc", TaskNone, m, all, pg, id)
t.("TaskAct member paged ALL + agg_count_calc", TaskAct, m, all, pg, id)
t.("TaskNone member paged ALL + agg_count_calc + Ash.Query.calculate(anon)", TaskNone, m, all, pg, &Ash.Query.calculate(&1, :anon, :integer, expr(points * 2)))
t.("TaskNone member paged [:agg_count] + Ash.Query.calculate(anon)", TaskNone, m, [:agg_count], pg, &Ash.Query.calculate(&1, :anon, :integer, expr(points * 2)))
t.("TaskNone member paged [:agg_first] + Ash.Query.calculate(anon)", TaskNone, m, [:agg_first], pg, &Ash.Query.calculate(&1, :anon, :integer, expr(points * 2)))
t.("TaskNone member NOT paged [:agg_first,:agg_count_calc] + Ash.Query.calculate(anon)", TaskNone, m, [:agg_first, :agg_count_calc], false, &Ash.Query.calculate(&1, :anon, :integer, expr(points * 2)))
