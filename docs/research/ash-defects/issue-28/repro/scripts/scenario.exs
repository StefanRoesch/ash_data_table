# usage: mix run scripts/scenario.exs <scenario> <cold|warm>
[scenario, temp] = System.argv()
loaded? = fn -> :code.is_loaded(Ash.Policy.Authorizer) != false end
member = %{id: 1, admin: false}

parent = Ash.Seed.seed!(Repro.Parent, %{})
thing = Ash.Seed.seed!(Repro.Thing, %{name: "n", secret: "TOPSECRET", parent_id: parent.id})
Ash.Seed.seed!(Repro.Holder, %{thing: thing})
seed_loaded = loaded?.()
if temp == "warm", do: Code.ensure_loaded(Ash.Policy.Authorizer)
before = loaded?.()

result =
  try do
    case scenario do
      "can_see_fields" -> Ash.can_see_fields({Repro.Thing, :read}, member, [:name, :secret])
      "can_see_fields_resource" -> Ash.can_see_fields(Repro.Thing, member, [:secret])
      "can_see_fields_filter_is_false" -> Ash.can_see_fields({Repro.Thing, :read}, member, [:secret], filter_is: false)
      "can_see_fields_query" -> Ash.can_see_fields(Ash.Query.for_read(Repro.Thing, :read, %{}, actor: member), member, [:secret])
      "can_see_fields_record" -> Ash.can_see_fields({thing, :read}, member, [:secret])
      "can_see_fields?" -> Ash.can_see_fields?(Repro.Thing, member, [:secret])
      "can_see_fields_nil_actor" -> Ash.can_see_fields({Repro.Thing, :read}, nil, [:secret])
      "evaluate_field_policies" -> Ash.Can.evaluate_field_policies({Repro.Thing, :read}, Repro.Domain, member, [:secret], [])
      "read" -> Repro.Thing |> Ash.read!(actor: member) |> Enum.map(& &1.secret)
      "read_select" -> Repro.Thing |> Ash.Query.select([:secret]) |> Ash.read!(actor: member) |> Enum.map(& &1.secret)
      "get" -> Ash.get!(Repro.Thing, thing.id, actor: member).secret
      "list_agg" -> Ash.list(Repro.Thing, :secret, actor: member)
      "list_agg_authorize_fields" -> Ash.list(Repro.Thing, :secret, actor: member, authorize_fields?: true)
      "parent_resource_agg" -> Repro.Parent |> Ash.Query.load(:secrets) |> Ash.read!(actor: member) |> Enum.map(& &1.secrets)
      "parent_load_things" -> Repro.Parent |> Ash.Query.load(:things) |> Ash.read!(actor: member) |> Enum.flat_map(& &1.things) |> Enum.map(& &1.secret)
      "apply_field_level_auth" -> Ash.Authorizer.apply_field_level_auth(Repro.Thing, [thing], actor: member, domain: Repro.Domain) |> then(fn {:ok, [r]} -> r.secret; o -> o end)
      "protected_fields" -> Ash.Resource.Info.protected_fields(Repro.Thing)
      "holder_read" -> Repro.Holder |> Ash.read!(actor: member) |> Enum.map(& &1.thing.secret)
      "holder_read_load_through" -> Repro.Holder |> Ash.Query.load(thing: [:parent]) |> Ash.read!(actor: member) |> Enum.map(& &1.thing.secret)
      "holder_ash_load" -> Repro.Holder |> Ash.read!(authorize?: false) |> Ash.load!([thing: []], actor: member) |> Enum.map(& &1.thing.secret)
      "can_read" -> Ash.can({Repro.Thing, :read}, member)
    end
  rescue
    e -> {:raised, Exception.message(e) |> String.slice(0, 200)}
  end

IO.puts(
  String.pad_trailing(scenario, 32) <> String.pad_trailing(temp, 5) <>
    " loaded(after seed/before call/after call)=#{seed_loaded}/#{before}/#{loaded?.()}  => #{inspect(result)}"
)
