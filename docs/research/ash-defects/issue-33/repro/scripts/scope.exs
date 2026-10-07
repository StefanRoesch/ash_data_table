require Ash.Query
member = %{id: 2, role: :member}
IO.puts("ash #{Application.spec(:ash, :vsn)}")
Agg.Repo.query!("truncate boxes, items")
for {dl, ns} <- [ets: Agg.Ets, pg: Agg.Pg] do
  box = Module.concat(ns, Box); item = Module.concat(ns, Item)
  # Box 1 open=true  has Item 1 open=false code=42  -> member must NOT see code 42
  # Box 2 open=false has Item 2 open=true  code=77  -> member MAY see code 77
  Ash.create!(box, %{id: 1, open: true}, authorize?: false); Ash.create!(box, %{id: 2, open: false}, authorize?: false)
  Ash.create!(item, %{id: 1, box_id: 1, open: false, code: 42}, authorize?: false); Ash.create!(item, %{id: 2, box_id: 2, open: true, code: 77}, authorize?: false)
  show = fn %Ash.ForbiddenField{} -> "FORBIDDEN"; v -> inspect(v) end
  IO.puts("\n#### #{dl}")
  IO.puts("  direct read of Item by member: " <> (item |> Ash.Query.sort(:id) |> Ash.read!(actor: member) |> Enum.map_join(", ", &"item#{&1.id} code=#{show.(&1.code)}")))
  IO.puts("  filter_input(Item, code == 42): " <> inspect(item |> Ash.Query.filter_input(%{code: %{eq: 42}}) |> Ash.read!(actor: member) |> Enum.map(& &1.id)) <> "   (correct: [])")
  IO.puts("  filter_input(Item, code == 77): " <> inspect(item |> Ash.Query.filter_input(%{code: %{eq: 77}}) |> Ash.read!(actor: member) |> Enum.map(& &1.id)) <> "   (correct: [2])")
  for {code, correct} <- [{42, "[]"}, {77, "[2]"}] do
    r = try do
      box |> Ash.Query.filter_input(%{items: %{code: %{eq: code}}}) |> Ash.read!(actor: member) |> Enum.map(& &1.id) |> inspect()
    rescue
      e -> "RAISED " <> (Exception.message(e) |> String.slice(0, 200))
    end
    IO.puts("  filter_input(Box, items.code == #{code}): boxes #{r}   (correct: #{correct})")
  end
end
