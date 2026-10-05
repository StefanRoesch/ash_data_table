# One snippet per gap in the manifest, each run against Spike.Shop.Product.
alias Ash.Info.Manifest
alias Ash.Resource.Info
alias Spike.Shop.Product
require Ash.Query

{:ok, m} = Manifest.generate(otp_app: :spike)
res = Manifest.get_resource!(Manifest.resource_lookup(m), Product)
actions = Manifest.action_lookup(m)
show = fn label, value -> IO.inspect(value, label: label, limit: :infinity, width: 200) end

IO.puts("-- 1. field declaration order")
show.("manifest Map.keys(fields)", Map.keys(res.fields))
show.("manifest Resource.field_names/1", Manifest.Resource.field_names(res))
show.("Info.public_attributes/1", Enum.map(Info.public_attributes(Product), & &1.name))
show.("Info.public_calculations/1", Enum.map(Info.public_calculations(Product), & &1.name))
show.("Info.public_aggregates/1", Enum.map(Info.public_aggregates(Product), & &1.name))

IO.puts("-- 2. relationship source/destination attributes")
show.("manifest relationship keys", res.relationships[:owner] |> Map.from_struct() |> Map.keys())

show.(
  "Info.relationships/1",
  for r <- Info.public_relationships(Product) do
    {r.name, r.type, r.source_attribute, r.destination, r.destination_attribute, Map.get(r, :through)}
  end
)

IO.puts("-- 3. domain")
show.("manifest resource keys", res |> Map.from_struct() |> Map.keys())
show.("Info.domain/1", Info.domain(Product))
show.("Ash.Domain.Info.resources/1", Ash.Domain.Info.resources(Info.domain(Product)))

IO.puts("-- 4. labels")
show.("manifest field description (the only human text)", res.fields[:name].description)
show.("attribute struct keys", Info.attribute(Product, :name) |> Map.from_struct() |> Map.keys())

IO.puts("-- 5. private attribute accepted by an action")
show.("manifest fields has :internal_note?", Map.has_key?(res.fields, :internal_note))
show.("manifest set_internal_note inputs", Enum.map(Manifest.get_action(actions, Product, :set_internal_note).inputs, & &1.name))
show.("Info.attribute(:internal_note).public?", Info.attribute(Product, :internal_note).public?)
show.("Info.action(:set_internal_note).accept", Info.action(Product, :set_internal_note).accept)

IO.puts("-- 6. attribute or argument")
show.("manifest restock inputs", Enum.map(Manifest.get_action(actions, Product, :restock).inputs, & &1.name))
show.("manifest set_price inputs", Enum.map(Manifest.get_action(actions, Product, :set_price).inputs, & &1.name))

for a <- [:restock, :set_price, :set_tags] do
  action = Info.action(Product, a)
  show.("Info.action(#{a})", accept: action.accept, arguments: Enum.map(action.arguments, & &1.name))
end

show.(
  "arguments feeding manage_relationship in :set_tags",
  for %{change: {Ash.Resource.Change.ManageRelationship, opts}} <- Info.action(Product, :set_tags).changes do
    {opts[:argument], opts[:relationship]}
  end
)

IO.puts("-- 7. enum values and labels")
status = Manifest.get_type!(Manifest.type_lookup(m), Spike.Types.Status)
show.("manifest field type kind", res.fields[:status].type.kind)
show.("manifest type definition values", status.values)
show.("Status.label/1", Enum.map(Spike.Types.Status.values(), &{&1, Spike.Types.Status.label(&1)}))
show.("Status.description/1", Enum.map(Spike.Types.Status.values(), &{&1, Spike.Types.Status.description(&1)}))

IO.puts("-- 8. defaults")
show.("manifest has_default?", for(n <- [:status, :stock, :id, :inserted_at], do: {n, res.fields[n].has_default?}))
show.("Info.attribute.default", for(n <- [:status, :stock, :id, :inserted_at], do: {n, Info.attribute(Product, n).default}))
show.("Info.attribute.update_default", Info.attribute(Product, :updated_at).update_default)
show.("generated?/writable?", for(n <- [:id, :inserted_at, :name], do: {n, Info.attribute(Product, n).generated?, Info.attribute(Product, n).writable?}))

IO.puts("-- 9. sortable")
show.("manifest sortable?", for(n <- [:margin, :keywords, :stock_value, :big_blob], do: {n, res.fields[n].sortable?}))
show.("Info.sortable?/3 offset", for(n <- [:margin, :keywords, :stock_value, :big_blob, :review_count], do: {n, Info.sortable?(Product, n)}))
show.("Info.sortable?/3 keyset", for(n <- [:margin, :keywords, :stock_value, :big_blob, :review_count], do: {n, Info.sortable?(Product, n, pagination_type: :keyset)}))

IO.puts("-- 10. pagination")
show.("manifest pagination", Manifest.get_action(actions, Product, :read).pagination)
show.("Info.action(:read).pagination", Info.action(Product, :read).pagination)
show.("Info.action(:unpaginated).pagination", Info.action(Product, :unpaginated).pagination)

IO.puts("-- 11. authorization (in neither source of static facts)")
admin = %{role: :admin}
staff = %{role: :staff}
product = Product |> Ash.Changeset.for_create(:create, %{name: "Ab", sku: "ABCD", price: 3, stock: 2}, actor: admin) |> Ash.create!()
Ash.update!(product, %{cost: 1, price: 3, reason: "x"}, action: :set_price, actor: admin)
show.("Ash.Policy.Info.field_policies/1", Enum.map(Ash.Policy.Info.field_policies(Product), & &1.fields))
show.("Ash.can?({product, :update}, staff)", Ash.can?({product, :update}, staff))
show.("Ash.can?({product, :update}, admin)", Ash.can?({product, :update}, admin))
show.("cost read as staff", (Product |> Ash.read!(actor: staff) |> hd()).cost)
show.("cost read as admin", (Product |> Ash.read!(actor: admin) |> hd()).cost)

IO.puts("-- 12. regex constraints")
show.("manifest match constraint", res.fields[:name].type.constraints[:match])
show.("Info match constraint", Info.attribute(Product, :name).constraints[:match])

IO.puts("-- 13. manifest.types oddity")
show.("types", Enum.map(m.types, &{&1.module, &1.kind}))
show.("published_at field kind", res.fields[:published_at].type.kind)
