alias Ash.Info.Manifest
{:ok, m} = Manifest.generate(otp_app: :spike)
al = Manifest.action_lookup(m)
tl = Manifest.type_lookup(m)

for a <- [:update, :set_price, :set_internal_note, :restock, :set_tags, :publish, :rename, :set_category, :create] do
  act = Manifest.get_action(al, Spike.Shop.Product, a)

  IO.inspect(
    Enum.map(act.inputs, &{&1.name, &1.type.kind, &1.type.module, [allow_nil?: &1.allow_nil?, required?: &1.required?, has_default?: &1.has_default?, sensitive?: &1.sensitive?]}),
    label: "inputs #{a}",
    limit: :infinity,
    width: 160
  )
end

IO.inspect(Manifest.get_type(tl, Spike.Types.Status), label: "Status type")
IO.inspect(Manifest.get_type(tl, Spike.Types.Sku) |> Map.take([:kind, :name, :module, :constraints, :instance_of]), label: "Sku type")
IO.inspect(Manifest.get_type(tl, Spike.Types.Dimensions) |> Map.take([:kind, :resource_module]), label: "Dimensions type")
IO.inspect(Manifest.get_type(tl, Spike.Types.Dimensions).resource.fields |> Map.keys(), label: "Dimensions fields")
IO.inspect(m.sort_capabilities, label: "sort caps")
IO.inspect(Enum.map(m.filter_capabilities.operators, & &1.name), label: "ops")
IO.inspect(Enum.map(m.filter_capabilities.functions, & &1.name), label: "fns", limit: :infinity)

p = Manifest.get_resource(Manifest.resource_lookup(m), Spike.Shop.Product)

for {n, f} <- Enum.sort(p.fields) do
  IO.inspect({n, f.kind, f.type.kind, f.filter_operators && Enum.map(f.filter_operators, & &1.name), f.filter_functions && Enum.map(f.filter_functions, & &1.name)},
    limit: :infinity,
    width: 250
  )
end

# private options
{:ok, mp} = Manifest.generate(otp_app: :spike, include_private_attributes?: true)
pp = Manifest.get_resource(Manifest.resource_lookup(mp), Spike.Shop.Product)
IO.inspect(Map.keys(pp.fields) -- Map.keys(p.fields), label: "extra fields with include_private_attributes?")
IO.inspect(Map.keys(Map.from_struct(pp.fields[:internal_note])), label: "field keys (no public? flag)")

# does a module calculation really sort / filter?
require Ash.Query
admin = %{role: :admin}
Spike.Shop.Product |> Ash.Changeset.for_create(:create, %{name: "Ab", sku: "ABCD", price: 3, stock: 2}, actor: admin) |> Ash.create!()

for {label, fun} <- [
      sort_module_calc: fn -> Spike.Shop.Product |> Ash.Query.sort(margin: :asc) |> Ash.read!() end,
      filter_module_calc: fn -> Spike.Shop.Product |> Ash.Query.filter(margin > 1) |> Ash.read!() end,
      sort_expr_calc: fn -> Spike.Shop.Product |> Ash.Query.sort(stock_value: :asc) |> Ash.read!() end,
      sort_aggregate: fn -> Spike.Shop.Product |> Ash.Query.sort(review_count: :asc) |> Ash.read!() end,
      sort_unsortable: fn -> Spike.Shop.Product |> Ash.Query.sort(big_blob: :asc) |> Ash.read!() end
    ] do
  res =
    try do
      {:ok, length(fun.())}
    rescue
      e -> {:error, e |> Exception.message() |> String.slice(0, 300)}
    end

  IO.inspect(res, label: label)
end

IO.inspect(Ash.Resource.Info.sortable?(Spike.Shop.Product, :margin), label: "Ash.Resource.Info.sortable?(:margin)")
IO.inspect(Ash.Resource.Info.sortable?(Spike.Shop.Product, :stock_value), label: "Ash.Resource.Info.sortable?(:stock_value)")
IO.inspect(Ash.Resource.Info.sortable?(Spike.Shop.Product, :big_blob), label: "Ash.Resource.Info.sortable?(:big_blob)")
