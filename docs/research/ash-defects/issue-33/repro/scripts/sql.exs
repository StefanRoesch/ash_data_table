require Ash.Query
member = %{id: 2, role: :member}
show = fn label, q ->
  IO.puts("\n---- #{label}")
  q = Ash.Query.for_read(q, :read, %{}, actor: member)
  # run through Ash with query logging
  Logger.configure(level: :debug)
  try do
    IO.puts("OK: " <> (q |> Ash.read!(actor: member) |> Enum.map_join(",", & &1.name)))
  rescue
    e -> IO.puts(e |> Exception.message() |> String.split("\n") |> Enum.take(8) |> Enum.join("\n"))
  end
  Logger.configure(level: :warning)
end
Application.put_env(:agg, :dummy, 1)
show.("PG Thing filter_input secret > 15", Ash.Query.filter_input(Agg.Pg.Thing, %{secret: %{greater_than: 15}}))
show.("PG Thing filter_input secret is_nil", Ash.Query.filter_input(Agg.Pg.Thing, %{secret: %{is_nil: true}}))
show.("PG Thing filter_input rsecret > 0", Ash.Query.filter_input(Agg.Pg.Thing, %{rsecret: %{greater_than: 0}}))
show.("PG ParentFP sort_input -max_secret", Ash.Query.sort_input(Agg.Pg.ParentFP, "-max_secret,name"))
