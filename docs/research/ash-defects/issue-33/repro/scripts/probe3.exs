# Parent whose field policy on the aggregates is RECORD-DEPENDENT (member sees them only on P2).
# Run after scenario.exs (Postgres rows present); seeds ETS itself.
require Ash.Query
member = %{id: 2, role: :member}
IO.puts("ash #{Application.spec(:ash, :vsn)}")
try_ = fn f ->
  try do
    f.()
  rescue
    e -> "RAISED " <> (e |> Exception.message() |> String.split("\n") |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "Bread") or String.contains?(&1, " in: ") or String.contains?(&1, "returned from") or String.ends_with?(&1, "Error"))) |> Enum.at(0) |> String.slice(0, 150))
  end
end
for {dl, ns} <- [ets: Agg.Ets, pg: Agg.Pg] do
  thing = Module.concat(ns, Thing); pm = Module.concat(ns, ParentFPR)
  if dl == :ets do
    for {id, name} <- [{1, "P1"}, {2, "P2"}, {3, "P3"}], do: Ash.create!(Agg.Ets.ParentNA, %{id: id, name: name}, authorize?: false)
    for {id, p, s, r, o, v} <- [{1, 1, 10, 1, true, true}, {2, 1, 20, 2, false, true}, {3, 1, 300, 4, true, false},
                                 {4, 2, 50, 8, false, true}, {5, 2, 70, 16, true, true}, {6, 3, 1000, 32, true, false}] do
      Ash.create!(thing, %{id: id, name: "t#{id}", parent_id: p, secret: s, rsecret: r, open: o, visible: v}, authorize?: false)
    end
  end
  IO.puts("\n######## #{dl}: ParentFPR, member")
  show = fn %Ash.ForbiddenField{} -> "FORBIDDEN"; v -> inspect(v, charlists: :as_lists) end
  IO.puts("  load max_secret, secrets: " <> try_.(fn -> pm |> Ash.Query.sort(:id) |> Ash.Query.load([:max_secret, :secrets]) |> Ash.read!(actor: member) |> Enum.map_join(" | ", &"#{&1.name}: #{show.(&1.max_secret)} #{show.(&1.secrets)}") end))
  for {label, q} <- [
        {"filter_input max_secret > 15   (unprotected answer P1,P2; protected answer P2)", fn -> pm |> Ash.Query.filter_input(%{max_secret: %{greater_than: 15}}) |> Ash.Query.sort(:id) end},
        {"filter_input max_secret is_nil (protected answer P1,P3)", fn -> pm |> Ash.Query.filter_input(%{max_secret: %{is_nil: true}}) |> Ash.Query.sort(:id) end},
        {"filter_input big == 1          (unprotected answer P1; protected answer none)", fn -> pm |> Ash.Query.filter_input(%{big: %{eq: 1}}) |> Ash.Query.sort(:id) end},
        {"sort_input -max_secret,name", fn -> Ash.Query.sort_input(pm, "-max_secret,name") end},
        {"sort_input name (control)", fn -> Ash.Query.sort_input(pm, "name") end}
      ] do
    IO.puts("  #{label}: " <> try_.(fn -> q.() |> Ash.read!(actor: member) |> Enum.map(& &1.name) |> inspect() end))
  end
end
