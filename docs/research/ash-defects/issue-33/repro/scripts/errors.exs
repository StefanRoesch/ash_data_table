# Full error text of the calls that raise in scenario.exs (data must already be seeded on pg; ETS is seeded here)
require Ash.Query
member = %{id: 2, role: :member}
for {id, name} <- [{1, "P1"}, {2, "P2"}, {3, "P3"}], do: Ash.create!(Agg.Ets.ParentNA, %{id: id, name: name}, authorize?: false)
for {id, p, s} <- [{1, 1, 10}, {2, 1, 20}], do: Ash.create!(Agg.Ets.Thing, %{id: id, name: "t#{id}", parent_id: p, secret: s, rsecret: 1, open: true, visible: true}, authorize?: false)
run = fn label, q ->
  IO.puts("\n---- #{label}")
  try do
    IO.puts("OK: " <> (q.() |> Ash.read!(actor: member) |> Enum.map_join(",", & &1.name)))
  rescue
    e -> IO.puts(e |> Exception.message() |> String.split("\n") |> Enum.take(16) |> Enum.join("\n"))
  end
end
run.("ETS ParentFP sort_input -max_secret", fn -> Ash.Query.sort_input(Agg.Ets.ParentFP, "-max_secret,name") end)
run.("PG  ParentFP sort_input -max_secret", fn -> Ash.Query.sort_input(Agg.Pg.ParentFP, "-max_secret,name") end)
run.("PG  ParentFP filter_input max_secret > 15", fn -> Ash.Query.filter_input(Agg.Pg.ParentFP, %{max_secret: %{greater_than: 15}}) end)
run.("PG  ParentFP filter_input n == 2", fn -> Ash.Query.filter_input(Agg.Pg.ParentFP, %{n: %{eq: 2}}) end)
run.("PG  ParentA filter_input things.secret > 15", fn -> Ash.Query.filter_input(Agg.Pg.ParentA, %{things: %{secret: %{greater_than: 15}}}) end)
run.("PG  Thing filter_input secret > 15", fn -> Ash.Query.filter_input(Agg.Pg.Thing, %{secret: %{greater_than: 15}}) end)
run.("PG  Thing filter_input secret == 20", fn -> Ash.Query.filter_input(Agg.Pg.Thing, %{secret: %{eq: 20}}) end)
run.("PG  Thing filter_input name == t1 (control)", fn -> Ash.Query.filter_input(Agg.Pg.Thing, %{name: %{eq: "t1"}}) end)
