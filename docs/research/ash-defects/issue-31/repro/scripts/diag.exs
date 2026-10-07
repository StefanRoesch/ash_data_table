# Run with BUG_VARIANT=diag, with and without BUG_PATCH=1.
Code.require_file("setup.exs", __DIR__)
require Ash.Query
Setup.pg!(); Setup.seed!(Bug.Pg)
:telemetry.attach("sql", [:bug, :repo, :query], fn _, _, meta, _ -> IO.puts("      SQL: #{meta.query}") end, nil)
member = %{role: :member}
IO.puts("BUG_PATCH=#{System.get_env("BUG_PATCH", "0")}  (1 = `if field do` in place of `if field_name do` in Ash.Policy.Authorizer.authorize_sort)")
for {label, sort, auth} <- [
      {"top-level secret (field policy)", ["secret", "-title"], [6, 5, 4, 3, 2, 1]},
      {"owner.name (related field policy)", ["owner.name", "-title"], [6, 5, 4, 3, 2, 1]},
      {"assignee.name (related read policy)", ["assignee.name", "-title"], [2, 4, 6, 5, 3, 1]}
    ] do
  IO.puts("  sort_input(#{inspect(sort)})  -- #{label}; authorized order would be #{inspect(auth)}, unauthorized [2, 3, 4, 1, 6, 5]")
  r = Bug.Pg.Task |> Ash.Query.sort_input(sort) |> Ash.Query.for_read(:read, %{}, actor: member) |> Ash.read(actor: member)
  IO.puts("      member: " <> case r do
    {:ok, rows} -> inspect(Enum.map(rows, & &1.id))
    {:error, e} -> "ERROR " <> (Exception.message(e) |> String.slice(0, 300))
  end)
end
