require Ash.Query
member = %{id: 2, role: :member}
try do
  Agg.Pg.ParentA |> Ash.Query.filter_input(%{things: %{id: %{eq: 2}, rsecret: %{greater_than: 1}}}) |> Ash.read!(actor: member) |> IO.inspect()
rescue
  e -> IO.puts(e |> Exception.message() |> String.split("\n") |> Enum.take(12) |> Enum.join("\n") |> String.slice(0, 1500))
end
