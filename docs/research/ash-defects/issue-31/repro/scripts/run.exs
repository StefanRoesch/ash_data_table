Code.require_file("setup.exs", __DIR__)
require Ash.Query
import Ash.Expr
require Ash.Sort

vsn = fn app -> Application.spec(app, :vsn) |> to_string() end
IO.puts("ash #{vsn.(:ash)}  ash_postgres #{vsn.(:ash_postgres)}  ash_sql #{vsn.(:ash_sql)}  ecto_sql #{vsn.(:ecto_sql)}  flags=#{System.get_env("BUG_FLAGS", "0")}")
IO.puts("config :ash = #{inspect(Application.get_all_env(:ash) |> Enum.sort(), limit: :infinity)}\n")

Setup.pg!()
Setup.seed!(Bug.Pg)
Setup.seed!(Bug.Ets)

# --- SQL capture -----------------------------------------------------------
{:ok, agent} = Agent.start_link(fn -> [] end)
:telemetry.attach("sql", [:bug, :repo, :query], fn _, _, meta, _ -> Agent.update(agent, &[{meta.query, meta.params} | &1]) end, nil)
sql = fn fun ->
  Agent.update(agent, fn _ -> [] end)
  r = fun.()
  {r, Agent.get(agent, &Enum.reverse/1)}
end

admin = %{role: :admin}
member = %{role: :member}

ids = fn
  {:ok, %{results: rs}} -> Enum.map(rs, & &1.id)
  {:ok, rs} -> Enum.map(rs, & &1.id)
  {:error, e} -> {:error, e |> Exception.message() |> String.split("\n") |> Enum.reject(&(&1 == "")) |> Enum.take(3) |> Enum.join(" | ") |> String.slice(0, 220)}
end

run = fn task, build, actor ->
  try do
    task |> build.() |> Ash.Query.for_read(:read, %{}, actor: actor, authorize?: true) |> Ash.read(actor: actor, authorize?: true) |> ids.()
  rescue
    e -> {:raised, e |> Exception.message() |> String.slice(0, 220)}
  end
end

truth = [2, 3, 4, 1, 6, 5]
verdict = fn got, expect_auth, expect_unauth ->
  cond do
    got == expect_auth and got == expect_unauth -> "(indistinguishable)"
    got == expect_auth -> "AUTHORIZED order/result"
    got == expect_unauth -> "UNAUTHORIZED: reflects hidden data"
    match?({:error, _}, got) or match?({:raised, _}, got) -> "rejected"
    true -> "OTHER"
  end
end

for {layer, ns} <- [{"POSTGRES", Bug.Pg}, {"ETS", Bug.Ets}] do
  task = Module.concat(ns, Task)
  user = Module.concat(ns, User)
  person = Module.concat(ns, Person)
  IO.puts("\n================================ #{layer} ================================")

  IO.puts("-- controls: what each actor can READ directly")
  IO.inspect(Ash.read!(user, actor: admin) |> Enum.map(&{&1.id, &1.name}) |> Enum.sort(), label: "users as admin ")
  IO.inspect(Ash.read!(user, actor: member) |> Enum.map(&{&1.id, &1.name}) |> Enum.sort(), label: "users as member")
  IO.inspect(Ash.read!(person, actor: member) |> Enum.map(&{&1.id, &1.name}) |> Enum.sort(), label: "people as member")
  IO.inspect(Ash.read!(task, actor: member, load: [:assignee, :owner]) |> Enum.sort_by(& &1.id) |> Enum.map(&{&1.id, &1.secret, &1.assignee && &1.assignee.name, &1.owner && &1.owner.name}),
    label: "tasks as member {id, secret, assignee.name, owner.name} via load", width: 200)

  # {label, build, expected authorized, expected unauthorized}
  a_auth = [2, 4, 6, 5, 3, 1]   # Alice t2, Carol t4, then NULLs (Bob, Dave, Erin hidden; t5 none) by title desc
  all_null = [6, 5, 4, 3, 2, 1] # every key NULL -> only "-title" decides (same as "sort ignored")
  cases = [
    {"A  READ POLICY (Task.assignee -> User; member reads only Alice, Carol)", [
      {~s|sort_input(["assignee.name", "-title"])|, &Ash.Query.sort_input(&1, ["assignee.name", "-title"]), a_auth, truth},
      {~s|sort_input("assignee.name,-title")|, &Ash.Query.sort_input(&1, "assignee.name,-title"), a_auth, truth},
      {~s|sort_input([{"assignee.name", :asc}, {"title", :desc}])|, &Ash.Query.sort_input(&1, [{"assignee.name", :asc}, {"title", :desc}]), a_auth, truth},
      {~s|sort_input(assignee: :name) (keyword)|, &Ash.Query.sort_input(&1, [assignee: :name]), a_auth, truth},
      {~s|sort_input(["assignee", "-title"]) (the relationship itself)|, &Ash.Query.sort_input(&1, ["assignee", "-title"]), a_auth, truth},
      {~s|sort(["assignee.name", "-title"]) (trusted sort, string path)|, &Ash.Query.sort(&1, ["assignee.name", "-title"]), a_auth, truth},
      {~s|sort([{calc(assignee.name), :asc}, title: :desc]) (trusted)|, &Ash.Query.sort(&1, [{Ash.Sort.expr_sort(assignee.name, :string), :asc}, {:title, :desc}]), a_auth, truth},
      {~s|sort_input(["assignee_name_agg", "-title"]) (first aggregate)|, &Ash.Query.sort_input(&1, ["assignee_name_agg", "-title"]), a_auth, truth},
      {~s|sort_input(["assignee_name_calc", "-title"]) (expr(assignee.name))|, &Ash.Query.sort_input(&1, ["assignee_name_calc", "-title"]), a_auth, truth},
      {~s|filter_input(%{assignee: %{name: %{eq: "Bob"}}})|, &(&1 |> Ash.Query.filter_input(%{assignee: %{name: %{eq: "Bob"}}}) |> Ash.Query.sort(:id)), [], [3]},
      {~s|filter_input(%{assignee: %{name: %{greater_than: "B"}}})|, &(&1 |> Ash.Query.filter_input(%{assignee: %{name: %{greater_than: "B"}}}) |> Ash.Query.sort(:id)), [4], [1, 3, 4, 6]},
      {~s|filter(assignee.name == "Bob") (trusted)|, &(&1 |> Ash.Query.filter(assignee.name == "Bob") |> Ash.Query.sort(:id)), [], [3]},
      {~s|filter_input(%{assignee_name_agg: %{eq: "Bob"}})|, &(&1 |> Ash.Query.filter_input(%{assignee_name_agg: %{eq: "Bob"}}) |> Ash.Query.sort(:id)), [], [3]},
      {~s|filter_input(%{assignee_name_calc: %{eq: "Bob"}})|, &(&1 |> Ash.Query.filter_input(%{assignee_name_calc: %{eq: "Bob"}}) |> Ash.Query.sort(:id)), [], [3]}
    ]},
    {"B  FIELD POLICY (Task.owner -> Person; member reads every person, never Person.name)", [
      {~s|sort_input(["owner.name", "-title"])|, &Ash.Query.sort_input(&1, ["owner.name", "-title"]), all_null, truth},
      {~s|sort_input("owner.name,-title")|, &Ash.Query.sort_input(&1, "owner.name,-title"), all_null, truth},
      {~s|sort(["owner.name", "-title"]) (trusted sort, string path)|, &Ash.Query.sort(&1, ["owner.name", "-title"]), all_null, truth},
      {~s|sort([{calc(owner.name), :asc}, title: :desc]) (trusted)|, &Ash.Query.sort(&1, [{Ash.Sort.expr_sort(owner.name, :string), :asc}, {:title, :desc}]), all_null, truth},
      {~s|sort_input(["owner_name_agg", "-title"]) (first aggregate)|, &Ash.Query.sort_input(&1, ["owner_name_agg", "-title"]), all_null, truth},
      {~s|sort_input(["owner_name_calc", "-title"]) (expr(owner.name))|, &Ash.Query.sort_input(&1, ["owner_name_calc", "-title"]), all_null, truth},
      {~s|filter_input(%{owner: %{name: %{eq: "Bea"}}})|, &(&1 |> Ash.Query.filter_input(%{owner: %{name: %{eq: "Bea"}}}) |> Ash.Query.sort(:id)), [], [3]},
      {~s|filter(owner.name == "Bea") (trusted)|, &(&1 |> Ash.Query.filter(owner.name == "Bea") |> Ash.Query.sort(:id)), [], [3]},
      {~s|filter_input(%{owner_name_agg: %{eq: "Bea"}})|, &(&1 |> Ash.Query.filter_input(%{owner_name_agg: %{eq: "Bea"}}) |> Ash.Query.sort(:id)), [], [3]},
      {~s|filter_input(%{owner_name_calc: %{eq: "Bea"}})|, &(&1 |> Ash.Query.filter_input(%{owner_name_calc: %{eq: "Bea"}}) |> Ash.Query.sort(:id)), [], [3]}
    ]},
    {"C  TOP-LEVEL FIELD POLICY (Task.secret, hidden from member) -- the comparison", [
      {~s|sort_input(["secret", "-title"])|, &Ash.Query.sort_input(&1, ["secret", "-title"]), all_null, truth},
      {~s|sort(secret: :asc, title: :desc) (trusted)|, &Ash.Query.sort(&1, secret: :asc, title: :desc), all_null, truth},
      {~s|filter_input(%{secret: %{eq: "b"}})|, &(&1 |> Ash.Query.filter_input(%{secret: %{eq: "b"}}) |> Ash.Query.sort(:id)), [], [3]}
    ]}
  ]

  for {heading, list} <- cases do
    IO.puts("\n-- #{heading}")
    for {label, build, exp_auth, exp_unauth} <- list do
      a = run.(task, build, admin)
      {m, qs} = sql.(fn -> run.(task, build, member) end)
      IO.puts("  #{label}")
      IO.puts("      expected if authorized: #{inspect(exp_auth)}   if NOT authorized: #{inspect(exp_unauth)}")
      IO.puts("      admin : #{inspect(a)}")
      IO.puts("      member: #{inspect(m)}   => #{verdict.(m, exp_auth, exp_unauth)}")
      if layer == "POSTGRES", do: for({q, p} <- qs, do: IO.puts("      SQL   : #{q}   params=#{inspect(p)}"))
    end
  end

  IO.puts("\n-- D  actor placement, for sort_input([\"assignee.name\", \"-title\"]) as member (authorized #{inspect(a_auth)}, not #{inspect(truth)})")
  q = fn -> Ash.Query.sort_input(task, ["assignee.name", "-title"]) end
  IO.inspect(q.() |> Ash.read(actor: member) |> ids.(), label: "  Ash.read(query, actor: member)                              ")
  IO.inspect(q.() |> Ash.Query.for_read(:read, %{}, actor: member) |> Ash.read() |> ids.(), label: "  for_read(.., actor: member) |> Ash.read()                   ")
  IO.inspect(task |> Ash.Query.for_read(:read, %{}, actor: member) |> Ash.Query.sort_input(["assignee.name", "-title"]) |> Ash.read(actor: member, authorize?: true) |> ids.(),
    label: "  for_read first, then sort_input, Ash.read(actor, authorize?)")
  IO.inspect(q.() |> Ash.Query.for_read(:paged, %{}, actor: member) |> Ash.read(actor: member, page: [limit: 10]) |> ids.(), label: "  action :paged, keyset page limit 10                         ")
  IO.inspect(q.() |> Ash.Query.for_read(:paged, %{}, actor: member) |> Ash.read(actor: member, page: [limit: 10, offset: 0]) |> ids.(), label: "  action :paged, offset page limit 10                         ")
  IO.inspect(q.() |> Ash.read(actor: nil, authorize?: true) |> ids.(), label: "  no actor at all (authorize?: true)                          ")

  IO.puts("\n-- E  what is VALUE-visible to the member through aggregate / calculation loads (not only order)")
  rows = task |> Ash.Query.load([:assignee_name_agg, :assignee_name_calc, :owner_name_agg, :owner_name_calc]) |> Ash.Query.sort(:id) |> Ash.read!(actor: member)
  for r <- rows, do: IO.puts("  task #{r.id}: assignee_name_agg=#{inspect(r.assignee_name_agg)} assignee_name_calc=#{inspect(r.assignee_name_calc)} owner_name_agg=#{inspect(r.owner_name_agg)} owner_name_calc=#{inspect(r.owner_name_calc)}")
end
