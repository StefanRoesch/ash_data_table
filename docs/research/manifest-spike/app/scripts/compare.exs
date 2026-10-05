alias Spike.TableModel.{FromInfo, FromManifest}

diff = fn a, b ->
  for {ca, cb} <- Enum.zip(a.columns, b.columns), {k, va} <- ca, va != cb[k] do
    {ca.name, k, manifest: va, info: cb[k]}
  end ++ (for {k, v} <- Map.delete(a, :columns), v != b[k], do: {k, manifest: v, info: b[k]})
end

cases = [
  {Spike.Shop.Product, []},
  {Spike.Shop.Product, [edit: [default: :update, price: :set_price, cost: :set_price, name: :rename, stock: :restock, category_id: :set_category]]},
  {Spike.Shop.Product, [read_action: :search, columns: [:name, :internal_note, :margin, :review_count, :category_name, :stock_value], edit: [default: :set_internal_note]]},
  {Spike.Shop.Product, [read_action: :unpaginated]},
  {Spike.Shop.Category, []},
  {Spike.Shop.Review, []},
  {Spike.Shop.Tag, []},
  {Spike.Shop.ProductDetail, []},
  {Spike.Accounts.User, []}
]

for {resource, opts} <- cases do
  m = FromManifest.build(resource, [otp_app: :spike] ++ opts)
  i = FromInfo.build(resource, opts)
  IO.puts("#{inspect(resource)} #{inspect(opts)}: equal? #{m == i} (#{length(m.columns)} columns)")
  if m != i, do: IO.inspect(diff.(m, i), limit: :infinity, width: 200)
end

model = FromInfo.build(Spike.Shop.Product, edit: [default: :update, price: :set_price, cost: :set_price, stock: :restock, category_id: :set_category])
IO.inspect(Map.delete(model, :columns), label: "model (without columns)")

for c <- model.columns do
  IO.inspect({c.name, c.kind, c.type.kind, sort: c.sortable?, filter: c.filterable?, edit: c.edit, default: c.default, belongs_to: c.belongs_to && c.belongs_to.relationship},
    width: 220
  )
end

IO.inspect(Enum.find(model.columns, &(&1.name == :status)), label: "status column", limit: :infinity)
IO.inspect(Enum.find(model.columns, &(&1.name == :sku)).type, label: "sku type")
IO.inspect(Enum.find(model.columns, &(&1.name == :keywords)), label: "keywords column", limit: :infinity)
