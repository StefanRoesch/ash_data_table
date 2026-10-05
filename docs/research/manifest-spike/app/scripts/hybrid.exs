alias Spike.TableModel.{FromInfo, FromManifest, Hybrid}

cases = [
  {Spike.Shop.Product, []},
  {Spike.Shop.Product, [edit: [default: :update, price: :set_price, cost: :set_price, name: :rename, stock: :restock, category_id: :set_category]]},
  {Spike.Shop.Product, [read_action: :search, columns: [:name, :internal_note, :margin, :review_count, :category_name, :stock_value], edit: [default: :set_internal_note]]},
  {Spike.Shop.Product, [read_action: :unpaginated]},
  {Spike.Shop.Category, []},
  {Spike.Shop.Review, []},
  {Spike.Shop.Tag, []},
  {Spike.Shop.ProductDetail, []},
  {Spike.Accounts.User, []},
  {Spike.Accounts.Team, []}
]

for {resource, opts} <- cases do
  m = FromManifest.build(resource, [otp_app: :spike] ++ opts)
  i = FromInfo.build(resource, opts)
  h = Hybrid.build(resource, opts)
  IO.puts("#{inspect(resource)} #{inspect(Keyword.keys(opts))}: manifest == info? #{m == i}; hybrid == info? #{h == i} (#{length(i.columns)} columns)")
end

ms = fn us -> Float.round(us / 1000, 3) end

stats = fn fun, n ->
  sorted = Enum.sort(for _ <- 1..n, do: elem(:timer.tc(fun), 0))
  %{median_ms: ms.(Enum.at(sorted, div(n, 2))), min_ms: ms.(hd(sorted)), max_ms: ms.(List.last(sorted))}
end

:persistent_term.erase({Hybrid, :capabilities, Ash.DataLayer.Ets})
{first, _} = :timer.tc(fn -> Hybrid.build(Spike.Shop.Product) end)
IO.puts("Hybrid first call (builds the operator catalogue): #{ms.(first)} ms")
IO.puts("Hybrid warm: #{inspect(stats.(fn -> Hybrid.build(Spike.Shop.Product) end, 200))}")
IO.puts("FromInfo warm: #{inspect(stats.(fn -> FromInfo.build(Spike.Shop.Product) end, 200))}")
IO.puts("FromManifest warm: #{inspect(stats.(fn -> FromManifest.build(Spike.Shop.Product, otp_app: :spike) end, 50))}")
caps = :persistent_term.get({Hybrid, :capabilities, Ash.DataLayer.Ets})
IO.puts("operator catalogue: #{:erts_debug.flat_size(caps) * 8} bytes flat")
