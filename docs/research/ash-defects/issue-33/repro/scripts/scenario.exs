require Ash.Query
admin = %{id: 1, role: :admin}
member = %{id: 2, role: :member}
IO.puts("ash #{Application.spec(:ash, :vsn)}  ash_postgres #{Application.spec(:ash_postgres, :vsn)}  ash_sql #{Application.spec(:ash_sql, :vsn)}  flags=#{System.get_env("ASH_FLAGS", "default")}")
IO.puts("no_filter_static_forbidden_reads?=#{inspect(Application.get_env(:ash, :policies)[:no_filter_static_forbidden_reads?])}")

Agg.Repo.query!("truncate parents, things, tags, parent_tags")

show = fn
  %Ash.ForbiddenField{} -> "FORBIDDEN"
  %Ash.NotLoaded{} -> "NOTLOADED"
  %Decimal{} = d -> Decimal.to_string(d)
  v -> inspect(v, charlists: :as_lists)
end

try_ = fn f ->
  try do
    f.()
  rescue
    e -> "RAISED " <> (e |> Exception.message() |> String.split("\n") |> Enum.reject(&(&1 == "")) |> Enum.reject(&(String.starts_with?(&1, "Bread Crumbs") or String.contains?(&1, "returned from") or String.contains?(&1, "raised in"))) |> Enum.take(2) |> Enum.join(" / ") |> String.slice(0, 170))
  end
end

for {dl, ns} <- [ets: Agg.Ets, pg: Agg.Pg] do
  thing = Module.concat(ns, Thing); tag = Module.concat(ns, Tag); ptag = Module.concat(ns, ParentTag)
  pna = Module.concat(ns, ParentNA)

  for {id, name} <- [{1, "P1"}, {2, "P2"}, {3, "P3"}], do: Ash.create!(pna, %{id: id, name: name}, authorize?: false)
  # id, parent, secret, rsecret, open, visible
  for {id, p, s, r, o, v} <- [{1, 1, 10, 1, true, true}, {2, 1, 20, 2, false, true}, {3, 1, 300, 4, true, false},
                               {4, 2, 50, 8, false, true}, {5, 2, 70, 16, true, true}, {6, 3, 1000, 32, true, false}] do
    Ash.create!(thing, %{id: id, name: "t#{id}", parent_id: p, secret: s, rsecret: r, open: o, visible: v}, authorize?: false)
  end
  for {id, w, pub} <- [{1, 1, true}, {2, 2, true}, {3, 4, false}], do: Ash.create!(tag, %{id: id, weight: w, public: pub}, authorize?: false)
  for {t, vis} <- [{1, true}, {2, false}, {3, true}], do: Ash.create!(ptag, %{parent_id: 1, tag_id: t, visible: vis}, authorize?: false)

  IO.puts("\n################ DATA LAYER #{dl} ################")
  IO.puts("\n== A. direct read of Thing (baseline: child READ + FIELD policy)")
  for {an, actor} <- [admin: admin, member: member] do
    rows = thing |> Ash.Query.sort(:id) |> Ash.read!(actor: actor)
    IO.puts("  #{an}: " <> Enum.map_join(rows, "  ", &"#{&1.name}(secret=#{show.(&1.secret)},rsecret=#{show.(&1.rsecret)})"))
  end

  IO.puts("\n== B. aggregates loaded on the parent (rows P1 | P2 | P3)")
  for parent <- [ParentNA, ParentA, ParentFP], pm = Module.concat(ns, parent) do
    IO.puts("  -- #{inspect(parent)}")
    for agg <- Agg.Def.aggs() do
      cells =
        for {an, opts} <- [admin: [actor: admin], member: [actor: member], "member authorize?:false": [actor: member, authorize?: false]] do
          v = try_.(fn -> pm |> Ash.Query.sort(:id) |> Ash.Query.load(agg) |> Ash.read!(opts) |> Enum.map_join(" | ", &show.(Map.get(&1, agg))) end)
          "#{an}: #{v}"
        end
      IO.puts("    #{String.pad_trailing(to_string(agg), 14)} " <> Enum.join(cells, "   ;   "))
    end
  end

  IO.puts("\n== C. outside input: sort_input / filter_input on the parent by an aggregate (names returned, in order)")
  names = fn q, actor -> try_.(fn -> q |> Ash.read!(actor: actor) |> Enum.map_join(",", & &1.name) end) end
  for parent <- [ParentNA, ParentA, ParentFP], pm = Module.concat(ns, parent) do
    IO.puts("  -- #{inspect(parent)}")
    for {label, qf} <- [
          {"sort_input -max_secret,name", fn -> Ash.Query.sort_input(pm, "-max_secret,name") end},
          {"sort_input max_secret,name", fn -> Ash.Query.sort_input(pm, "max_secret,name") end},
          {"sort_input -sum_secret,name", fn -> Ash.Query.sort_input(pm, "-sum_secret,name") end},
          {"sort_input -big,name", fn -> Ash.Query.sort_input(pm, "-big,name") end},
          {"sort_input -sum_r,name", fn -> Ash.Query.sort_input(pm, "-sum_r,name") end},
          {"sort_input -sum_na,name", fn -> Ash.Query.sort_input(pm, "-sum_na,name") end},
          {"sort_input -sum_nofs,name (sortable? false)", fn -> Ash.Query.sort_input(pm, "-sum_nofs,name") end},
          {"filter_input sum_nofs == 30 (filterable? false)", fn -> pm |> Ash.Query.filter_input(%{sum_nofs: %{eq: 30}}) |> Ash.Query.sort(:id) end},
          {"Ash.Query.sort(max_secret: :desc, name: :asc)", fn -> Ash.Query.sort(pm, max_secret: :desc, name: :asc) end},
          {"filter_input max_secret > 15", fn -> pm |> Ash.Query.filter_input(%{max_secret: %{greater_than: 15}}) |> Ash.Query.sort(:id) end},
          {"filter_input max_secret > 25", fn -> pm |> Ash.Query.filter_input(%{max_secret: %{greater_than: 25}}) |> Ash.Query.sort(:id) end},
          {"filter_input max_secret > 100", fn -> pm |> Ash.Query.filter_input(%{max_secret: %{greater_than: 100}}) |> Ash.Query.sort(:id) end},
          {"filter_input max_secret is_nil true", fn -> pm |> Ash.Query.filter_input(%{max_secret: %{is_nil: true}}) |> Ash.Query.sort(:id) end},
          {"filter_input sum_secret == 30", fn -> pm |> Ash.Query.filter_input(%{sum_secret: %{eq: 30}}) |> Ash.Query.sort(:id) end},
          {"filter_input sum_secret == 330", fn -> pm |> Ash.Query.filter_input(%{sum_secret: %{eq: 330}}) |> Ash.Query.sort(:id) end},
          {"filter_input n == 2", fn -> pm |> Ash.Query.filter_input(%{n: %{eq: 2}}) |> Ash.Query.sort(:id) end},
          {"filter_input n == 3", fn -> pm |> Ash.Query.filter_input(%{n: %{eq: 3}}) |> Ash.Query.sort(:id) end},
          {"filter_input any == true", fn -> pm |> Ash.Query.filter_input(%{any: %{eq: true}}) |> Ash.Query.sort(:id) end},
          {"filter_input big == 1", fn -> pm |> Ash.Query.filter_input(%{big: %{eq: 1}}) |> Ash.Query.sort(:id) end},
          {"filter_input sum_na == 330", fn -> pm |> Ash.Query.filter_input(%{sum_na: %{eq: 330}}) |> Ash.Query.sort(:id) end},
          {"filter_input sum_weight == 1", fn -> pm |> Ash.Query.filter_input(%{sum_weight: %{eq: 1}}) |> Ash.Query.sort(:id) end},
          {"Ash.Query.filter(max_secret > 15)", fn -> pm |> Ash.Query.filter(max_secret > 15) |> Ash.Query.sort(:id) end},
          {"filter_input things.secret > 15 (rel path)", fn -> pm |> Ash.Query.filter_input(%{things: %{secret: %{greater_than: 15}}}) |> Ash.Query.sort(:id) end},
          {"filter_input things.secret > 100 (rel path)", fn -> pm |> Ash.Query.filter_input(%{things: %{secret: %{greater_than: 100}}}) |> Ash.Query.sort(:id) end}
        ] do
      cells = for {an, actor} <- [admin: admin, member: member], do: "#{an}: [#{try_.(fn -> names.(qf.(), actor) end)}]"
      IO.puts("    #{String.pad_trailing(label, 46)} " <> Enum.join(cells, "   "))
    end
  end

  IO.puts("\n== D. binary search by the member: recover max_secret of P1 through filter_input alone")
  for parent <- [ParentNA, ParentA, ParentFP], pm = Module.concat(ns, parent) do
    probe = fn n -> pm |> Ash.Query.filter_input(%{id: %{eq: 1}, max_secret: %{greater_than: n}}) |> Ash.read!(actor: member) != [] end
    res = try_.(fn ->
      if probe.(-1) do
        {lo, _hi, steps} =
          Enum.reduce_while(1..40, {-1, 4096, 0}, fn _, {lo, hi, st} ->
            if hi - lo <= 1, do: {:halt, {lo, hi, st}}, else: (mid = div(lo + hi, 2); if(probe.(mid), do: {:cont, {mid, hi, st + 1}}, else: {:cont, {lo, mid, st + 1}}))
          end)
        "recovered max_secret(P1) = #{lo + 1} in #{steps} probes  (true value over rows the member may read: 20; over all rows: 300)"
      else
        "no probe ever matched: nothing recovered"
      end end)
    IO.puts("    #{inspect(parent)}: #{res}")
  end

  IO.puts("\n== E. baseline: outside input directly on Thing (field policy on the attribute itself)")
  for {label, qf} <- [
        {"filter_input secret > 15", fn -> thing |> Ash.Query.filter_input(%{secret: %{greater_than: 15}}) |> Ash.Query.sort(:id) end},
        {"sort_input -secret,name", fn -> Ash.Query.sort_input(thing, "-secret,name") end},
        {"Ash.Query.sort(secret: :desc, name: :asc)", fn -> Ash.Query.sort(thing, secret: :desc, name: :asc) end},
        {"filter_input rsecret > 0", fn -> thing |> Ash.Query.filter_input(%{rsecret: %{greater_than: 0}}) |> Ash.Query.sort(:id) end},
        {"sort_input -rsecret,name", fn -> Ash.Query.sort_input(thing, "-rsecret,name") end}
      ] do
    cells = for {an, actor} <- [admin: admin, member: member], do: "#{an}: [#{names.(qf.(), actor)}]"
    IO.puts("    #{String.pad_trailing(label, 46)} " <> Enum.join(cells, "   "))
  end

  IO.puts("\n== F. Ash.can_see_fields on the parent for the member")
  for parent <- [ParentNA, ParentA, ParentFP], pm = Module.concat(ns, parent) do
    IO.puts("    #{inspect(parent)}: " <> try_.(fn -> inspect(Ash.can_see_fields({pm, :read}, member, [:name, :sum_secret, :secrets])) end))
  end

  if dl == :ets, do: Agg.Repo.query!("truncate parents, things, tags, parent_tags")
end
