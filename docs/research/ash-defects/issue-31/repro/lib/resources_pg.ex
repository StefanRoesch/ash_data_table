# GENERATED from resources.tmpl by gen.sh -- the same resources once per data layer.
defmodule Bug.Pg.Domain do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Bug.Pg.User
    resource Bug.Pg.Person
    resource Bug.Pg.Task
  end
end

# (a) READ POLICY: a member reads only users with visible == true
defmodule Bug.Pg.User do
  use Ash.Resource, domain: Bug.Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "users"
    repo Bug.Repo
  end

  actions do
    defaults [:read, create: :*]
  end

  policies do
    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(visible == true)
    end
  end

  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :name, :string, public?: true
    attribute :visible, :boolean, public?: true, default: true
  end
end

# (b) FIELD POLICY: every person is readable, `name` only by an admin
defmodule Bug.Pg.Person do
  use Ash.Resource, domain: Bug.Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "people"
    repo Bug.Repo
  end

  actions do
    defaults [:read, create: :*]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :name do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :name, :string, public?: true
  end
end

defmodule Bug.Pg.Task do
  use Ash.Resource, domain: Bug.Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "tasks"
    repo Bug.Repo
  end

  actions do
    defaults [:read, create: :*]

    read :paged do
      pagination offset?: true, keyset?: true, required?: false
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    # a TOP-LEVEL hidden field, for the comparison
    field_policy :secret do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :title, :string, public?: true
    attribute :secret, :string, public?: true
    attribute :assignee_id, :integer, public?: true
    attribute :owner_id, :integer, public?: true
  end

  relationships do
    belongs_to :assignee, Bug.Pg.User, public?: true, define_attribute?: false, source_attribute: :assignee_id
    belongs_to :owner, Bug.Pg.Person, public?: true, define_attribute?: false, source_attribute: :owner_id
  end

  calculations do
    calculate :assignee_name_calc, :string, expr(assignee.name), public?: true
    calculate :owner_name_calc, :string, expr(owner.name), public?: true
  end

  aggregates do
    first :assignee_name_agg, :assignee, :name, public?: true
    first :owner_name_agg, :owner, :name, public?: true
  end
end
