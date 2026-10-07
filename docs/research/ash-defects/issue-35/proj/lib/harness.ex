defmodule H do
  require Ash.Query
  @admin %{id: "00000000-0000-0000-0000-0000000000a1", role: :admin}
  @member %{id: "00000000-0000-0000-0000-0000000000b2", role: :member}
  @other "00000000-0000-0000-0000-0000000000c3"
  def admin, do: @admin
  def member, do: @member
  def m(ns, name), do: Module.concat([ns, name])

  def seed(ns) do
    if ns == Pg, do: Bug.Repo.query!("truncate projects, tasks, comments, links, ulinks")
    if ns == Ets do
      for r <- [m(ns, Project), m(ns, Comment), m(ns, TaskNone), m(ns, LinkNone), m(ns, ULinkNone)], x <- Ash.read!(r, authorize?: false), do: Ash.destroy!(x, authorize?: false)
    end
    p1 = Ash.Seed.seed!(m(ns, Project), %{name: "P1"})
    p2 = Ash.Seed.seed!(m(ns, Project), %{name: "P2"})
    for {p, range} <- [{p1, 1..7}, {p2, 8..9}], i <- range do
      t = Ash.Seed.seed!(m(ns, TaskNone), %{title: "t#{i}", secret: "s#{i}", points: i, project_id: p.id,
            assignee_id: if(i in [2, 5, 8], do: @member.id, else: @other)})
      Ash.Seed.seed!(m(ns, LinkNone), %{project_id: p.id, task_id: t.id})
      Ash.Seed.seed!(m(ns, ULinkNone), %{project_id: p.id, task_id: t.id})
      for j <- 1..rem(i, 4)//1 do
        Ash.Seed.seed!(m(ns, Comment), %{body: "c#{i}.#{j}", score: i * 10 + j, task_id: t.id,
          author_id: if(rem(j, 2) == 1, do: @member.id, else: @other)})
      end
    end
    p1
  end

  @fields [:agg_count, :agg_first, :agg_list, :agg_max, :agg_sum, :agg_exists, :agg_count_filtered,
           :agg_max_protected, :agg_count_fp, :double_points, :secret_calc, :elixir_calc]
  def fields, do: @fields

  # opts: ns, variant ("Rec"), rel (:has_many | :m2m | :top), actor, loads, page (kw | nil), limit, sort (default points asc),
  #       action, build (:load_first | :for_read_first | :no_actor_in_query)
  def run(o) do
    o = Map.new(o)
    ns = o.ns; v = o.variant; dest = m(ns, "Task#{v}"); actor = o.actor
    loads = o[:loads] || []; page = o[:page]; action = o[:action] || :read
    sort = Map.get(o, :sort, [points: :asc])
    p1 = Ash.read_first!(Ash.Query.filter(m(ns, Project), name == "P1"), authorize?: false)
    q =
      case o[:build] || :for_read_first do
        :for_read_first -> dest |> Ash.Query.for_read(action, %{}, actor: actor) |> Ash.Query.load(loads)
        :load_first -> dest |> Ash.Query.new() |> Ash.Query.load(loads) |> Ash.Query.for_read(action, %{}, actor: actor)
        :no_actor_in_query -> dest |> Ash.Query.new() |> Ash.Query.load(loads)
      end
    q = if sort, do: Ash.Query.sort(q, sort), else: q
    q = if o[:limit], do: Ash.Query.limit(q, o[:limit]), else: q
    q = if o[:extra], do: o[:extra].(q), else: q
    rel = case o.rel do :has_many -> :"tasks_#{String.downcase(v)}"; :m2m -> :"m2m_#{String.downcase(v)}"; :m2mu -> :"m2mu_#{String.downcase(v)}"; :has_one -> :"first_#{String.downcase(v)}"; :top -> nil end
    res =
      try do
        case o.rel do
          :top ->
            q = Ash.Query.filter(q, project_id == ^p1.id)
            if page, do: Ash.read(q, actor: actor, page: page), else: Ash.read(q, actor: actor)
          _ ->
            q = if page, do: Ash.Query.page(q, page), else: q
            with {:ok, p} <- Ash.get(m(ns, Project), p1.id, load: [{rel, q}], actor: actor), do: {:ok, Map.get(p, rel)}
        end
      rescue
        e -> {:raised, e, __STACKTRACE__}
      end
    {res, check(res, o, dest, p1, loads, sort)}
  end

  defp check({:ok, got}, o, dest, p1, loads, sort) do
    {recs, count, shape} =
      case got do
        %Ash.Page.Offset{results: r, count: c} -> {r, c, "offset"}
        %Ash.Page.Keyset{results: r, count: c} -> {r, c, "keyset"}
        r when is_list(r) -> {r, nil, "list"}
        %{} = one -> {[one], nil, "one"}
        nil -> {[], nil, "nil"}
      end
    base = dest |> Ash.Query.filter(project_id == ^p1.id) |> Ash.Query.sort(sort || [points: :asc]) |> Ash.Query.load(@fields) |> Ash.read!(authorize?: false, page: false)
    page = o[:page] || []
    lim = if o.rel == :has_one, do: 1, else: page[:limit] || o[:limit]
    exp = base |> Enum.drop(page[:offset] || 0) |> then(&(if lim, do: Enum.take(&1, lim), else: &1))
    problems = []
    problems = if sort && Enum.map(recs, & &1.id) != Enum.map(exp, & &1.id), do: ["rows/order differ: got #{inspect(Enum.map(recs, & &1.points))} want #{inspect(Enum.map(exp, & &1.points))}" | problems], else: problems
    problems = if !sort && Enum.sort(Enum.map(recs, & &1.id)) -- Enum.map(base, & &1.id) != [], do: ["unknown rows" | problems], else: problems
    problems = if page[:count] && count != length(base), do: ["count #{inspect(count)} want #{length(base)}" | problems], else: problems
    byid = Map.new(base, &{&1.id, &1})
    diffs =
      for r <- recs, f <- List.wrap(loads), is_atom(f), b = byid[r.id], Map.get(r, f) != Map.get(b, f) do
        "#{f}@t#{r.points}: #{inspect(Map.get(r, f))} (unauthorized baseline #{inspect(Map.get(b, f))})"
      end
    secrets = Enum.map(recs, fn r -> case r.secret do %Ash.ForbiddenField{} -> "F"; _ -> "v" end end) |> Enum.join()
    status = if problems == [], do: "OK", else: "WRONG " <> Enum.join(problems, "; ")
    "#{status} #{shape} n=#{length(recs)} count=#{inspect(count)} secret=#{secrets}" <> if(diffs == [], do: "", else: " DIFFS: " <> Enum.join(Enum.take(diffs, 4), " | "))
  end
  defp check({:error, e}, _, _, _, _, _), do: "ERROR " <> short(e)
  defp check({:raised, e, _}, _, _, _, _, _), do: "RAISED " <> short(e)

  def short(e) do
    msg = Exception.message(e)
    line = msg |> String.split("\n") |> Enum.find(&(&1 =~ "** (")) || (msg |> String.split("\n") |> Enum.reject(&(&1 == "")) |> Enum.take(2) |> Enum.join(" "))
    String.slice(String.trim(line), 0, 130)
  end
end
