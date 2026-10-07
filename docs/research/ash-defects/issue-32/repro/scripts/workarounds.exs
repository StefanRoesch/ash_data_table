Code.require_file("setup.exs", __DIR__)
require Ash.Query
vsn = fn app -> Application.spec(app, :vsn) |> to_string() end
IO.puts("# ash #{vsn.(:ash)}  ash_postgres #{vsn.(:ash_postgres)}  ash_sql #{vsn.(:ash_sql)}")
Setup.pg!(); Setup.seed!(V32.Pg)
{:ok, agent} = Agent.start_link(fn -> [] end)
:telemetry.attach("sql", [:v32, :repo, :query], fn _, _, meta, _ -> Agent.update(agent, &[meta.query | &1]) end, nil)
member = %{role: :member}
task = V32.Pg.Task
trig = %{"sort_input path" => &Ash.Query.sort_input(&1, ["assignee.name"]),
         "filter_input path OR" => &Ash.Query.filter_input(&1, %{or: [%{assignee: %{name: %{not_eq: "zzz"}}}, %{id: %{gt: 0}}]})}
IO.puts("entitled for member: 1=>Alice 2=>nil 3=>Carol 4=>nil 5=>nil\n")
for {tn, tf} <- trig do
  for agg <- [:assignee_name_agg, :assignee_name_agg_jf, :assignee_name_agg_ra] do
    Agent.update(agent, fn _ -> [] end)
    rows = task |> Ash.Query.load(agg) |> tf.() |> Ash.read!(actor: member)
    IO.puts("A. same query, #{tn}, load(#{inspect(agg)}): #{inspect(rows |> Enum.sort_by(& &1.id) |> Enum.map(&{&1.id, Map.get(&1, agg)}))}")
    for q <- Agent.get(agent, & &1), do: IO.puts("     SQL: #{q}")
  end
  Agent.update(agent, fn _ -> [] end)
  rows = task |> tf.() |> Ash.read!(actor: member) |> Ash.load!(:assignee_name_agg, actor: member)
  IO.puts("B. two steps, #{tn}: read, THEN Ash.load!(records, :assignee_name_agg): order=#{inspect(Enum.map(rows, & &1.id))} #{inspect(rows |> Enum.sort_by(& &1.id) |> Enum.map(&{&1.id, &1.assignee_name_agg}))}")
  for q <- Agent.get(agent, &Enum.reverse/1), do: IO.puts("     SQL: #{q}")
  IO.puts("")
end
# what the member is told if they try to read the users directly
IO.puts("C. member reads users directly: #{inspect(V32.Pg.User |> Ash.read!(actor: member) |> Enum.map(& &1.name))}")
IO.puts("D. member loads :assignee on tasks: #{inspect(task |> Ash.Query.load(:assignee) |> Ash.read!(actor: member) |> Enum.sort_by(& &1.id) |> Enum.map(&{&1.id, &1.assignee && &1.assignee.name}))}")
