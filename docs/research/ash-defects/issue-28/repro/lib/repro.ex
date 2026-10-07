defmodule Repro.Domain do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Repro.Thing
    resource Repro.Parent
    resource Repro.Holder
  end
end

defmodule Repro.Thing do
  use Ash.Resource,
    domain: Repro.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :secret, :string, public?: true
  end

  relationships do
    belongs_to :parent, Repro.Parent, public?: true
  end

  actions do
    defaults [:read, create: [:name, :secret, :parent_id]]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :secret do
      authorize_if actor_attribute_equals(:admin, true)
    end

    field_policy :* do
      authorize_if always()
    end
  end
end

# No authorizer of its own: a resource whose aggregate reaches into Thing.
defmodule Repro.Parent do
  use Ash.Resource, domain: Repro.Domain, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
  end

  relationships do
    has_many :things, Repro.Thing, destination_attribute: :parent_id, public?: true
  end

  aggregates do
    list :secrets, :things, :secret, public?: true
  end

  actions do
    defaults [:read, create: []]
  end
end

# No authorizer of its own; holds a Thing as an in-memory struct value.
defmodule Repro.Holder do
  use Ash.Resource, domain: Repro.Domain, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :thing, :struct, constraints: [instance_of: Repro.Thing], public?: true
  end

  actions do
    defaults [:read, create: [:thing]]
  end
end

defmodule Repro.Probe do
  def loaded?, do: :code.is_loaded(Ash.Policy.Authorizer) != false

  def run(label) do
    member = %{id: 1, admin: false}
    admin = %{id: 2, admin: true}
    IO.puts("== #{label} | ash #{Application.spec(:ash, :vsn)} | code mode #{:code.get_mode()}")
    IO.puts("authorizer loaded before call:        #{loaded?()}")
    IO.puts("function_exported? (no load):         #{function_exported?(Ash.Policy.Authorizer, :evaluate_field_policies, 3)}")
    IO.puts("authorizer loaded after that test:    #{loaded?()}")
    r1 = Ash.can_see_fields({Repro.Thing, :read}, member, [:name, :secret])
    IO.puts("member  can_see_fields (1st call):    #{inspect(r1)}")
    IO.puts("authorizer loaded after 1st call:     #{loaded?()}")
    Code.ensure_loaded(Ash.Policy.Authorizer)
    r2 = Ash.can_see_fields({Repro.Thing, :read}, member, [:name, :secret])
    IO.puts("member  can_see_fields (ensure_loaded): #{inspect(r2)}")
    r3 = Ash.can_see_fields({Repro.Thing, :read}, admin, [:name, :secret])
    IO.puts("admin   can_see_fields:               #{inspect(r3)}")
    IO.puts("VERDICT: #{if r1 == r2, do: "consistent", else: "DIFFERENT ANSWERS before/after loading"}")
  end
end
# touched 1791363672
