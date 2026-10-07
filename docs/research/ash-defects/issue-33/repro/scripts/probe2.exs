# Adjacent checks: (1) relationship-path field references from outside input, per root resource;
# (2) many_to_many: is the JOIN resource's read policy applied to loads, filters and aggregates?
# Run after scenario.exs (uses the Postgres rows it left; seeds ETS itself).
require Ash.Query
admin = %{id: 1, role: :admin}
member = %{id: 2, role: :member}
IO.puts("ash #{Application.spec(:ash, :vsn)}  flags=#{System.get_env("ASH_FLAGS", "default")}")
try_ = fn f ->
  try do
    f.()
  rescue
    e -> "RAISED " <> (e |> Exception.message() |> String.split("\n") |> Enum.reject(&(&1 == "")) |> Enum.at(-1) |> String.slice(0, 110))
  end
end

for {dl, ns} <- [ets: Agg.Ets, pg: Agg.Pg] do
  thing = Module.concat(ns, Thing); tag = Module.concat(ns, Tag); ptag = Module.concat(ns, ParentTag)
  if dl == :ets do
    for {id, name} <- [{1, "P1"}, {2, "P2"}, {3, "P3"}], do: Ash.create!(Agg.Ets.ParentNA, %{id: id, name: name}, authorize?: false)
    for {id, p, s, r, o, v} <- [{1, 1, 10, 1, true, true}, {2, 1, 20, 2, false, true}, {3, 1, 300, 4, true, false},
                                 {4, 2, 50, 8, false, true}, {5, 2, 70, 16, true, true}, {6, 3, 1000, 32, true, false}] do
      Ash.create!(thing, %{id: id, name: "t#{id}", parent_id: p, secret: s, rsecret: r, open: o, visible: v}, authorize?: false)
    end
    for {id, w, pub} <- [{1, 1, true}, {2, 2, true}, {3, 4, false}], do: Ash.create!(tag, %{id: id, weight: w, public: pub}, authorize?: false)
    for {t, vis} <- [{1, true}, {2, false}, {3, true}], do: Ash.create!(ptag, %{parent_id: 1, tag_id: t, visible: vis}, authorize?: false)
  end
  IO.puts("\n################ DATA LAYER #{dl} ################")
  IO.puts("== G. member: binary search on filter_input(Parent, %{things: %{id: 2, secret: %{greater_than: n}}})  (t2 is readable by the member, its secret=20 is hidden by Thing's field policy)")
  for parent <- [ParentNA, ParentA, ParentFP], pm = Module.concat(ns, parent) do
    probe = fn n -> pm |> Ash.Query.filter_input(%{things: %{id: %{eq: 2}, secret: %{greater_than: n}}}) |> Ash.read!(actor: member) != [] end
    res = try_.(fn ->
      if probe.(-1) do
        {lo, _, st} = Enum.reduce_while(1..40, {-1, 4096, 0}, fn _, {lo, hi, st} ->
          if hi - lo <= 1, do: {:halt, {lo, hi, st}}, else: (mid = div(lo + hi, 2); if(probe.(mid), do: {:cont, {mid, hi, st + 1}}, else: {:cont, {lo, mid, st + 1}}))
        end)
        "RECOVERED t2.secret = #{lo + 1} in #{st} probes"
      else
        "no probe matched: nothing recovered"
      end end)
    IO.puts("    #{inspect(parent)}: #{res}")
  end
  IO.puts("   same for the hidden ROW t3 (id 3, secret 300, not readable by the member):")
  for parent <- [ParentNA, ParentA], pm = Module.concat(ns, parent) do
    r = try_.(fn -> pm |> Ash.Query.filter_input(%{things: %{id: %{eq: 3}, secret: %{greater_than: 100}}}) |> Ash.read!(actor: member) |> Enum.map(& &1.name) |> inspect() end)
    IO.puts("    #{inspect(parent)}: things.id==3 and things.secret>100 -> #{r}")
  end
  IO.puts("   record-dependent field (rsecret; visible to member only where open): things.id==2 (open=false, rsecret=2) and rsecret>1")
  for parent <- [ParentNA, ParentA], pm = Module.concat(ns, parent) do
    r = try_.(fn -> pm |> Ash.Query.filter_input(%{things: %{id: %{eq: 2}, rsecret: %{greater_than: 1}}}) |> Ash.read!(actor: member) |> Enum.map(& &1.name) |> inspect() end)
    IO.puts("    #{inspect(parent)}: -> #{r}   (field policy applied => [])")
  end
  IO.puts("   control, the Thing resource itself as root (it has the authorizer): filter_input(Thing, id==2 and secret>15)")
  IO.puts("    " <> try_.(fn -> thing |> Ash.Query.filter_input(%{id: %{eq: 2}, secret: %{greater_than: 15}}) |> Ash.read!(actor: member) |> Enum.map(& &1.name) |> inspect() end))

  IO.puts("== H. many_to_many P1 -> tags.  A(id1,w1,public,join visible)  B(id2,w2,public,join HIDDEN)  C(id3,w4,PRIVATE,join visible)")
  for parent <- [ParentNA, ParentA], pm = Module.concat(ns, parent), {an, actor} <- [admin: admin, member: member] do
    loaded = try_.(fn -> pm |> Ash.Query.filter(id == 1) |> Ash.Query.load(tags: Ash.Query.sort(tag, :id)) |> Ash.read_one!(actor: actor) |> Map.get(:tags) |> Enum.map(& &1.id) |> inspect() end)
    agg = try_.(fn -> pm |> Ash.Query.filter(id == 1) |> Ash.Query.load([:n_tags, :weights]) |> Ash.read_one!(actor: actor) |> then(&"n_tags=#{&1.n_tags} weights=#{inspect(&1.weights, charlists: :as_lists)}") end)
    f = try_.(fn -> pm |> Ash.Query.filter_input(%{tags: %{id: %{eq: 2}}}) |> Ash.read!(actor: actor) |> Enum.map(& &1.name) |> inspect() end)
    joins = ptag |> Ash.Query.sort(:tag_id) |> Ash.read!(actor: actor) |> Enum.map(& &1.tag_id) |> inspect()
    IO.puts("    #{inspect(parent)} #{an}: load(:tags) ids=#{loaded}   aggregates: #{agg}   filter_input tags.id==2 -> #{f}   direct read of join rows: #{joins}")
  end
end
