# GENERATED from resources.tmpl by gen.sh -- identical resources on two data layers.
defmodule Ashbug.Ets.Task do
  use Ash.Resource, domain: Ashbug.Ets, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]


  actions do
    defaults [:read, create: :*]

    read :paged do
      pagination offset?: true, keyset?: true, countable: true, required?: false
    end

    read :keyset_only do
      pagination keyset?: true, countable: true, required?: false
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    # record-dependent: visible to admins, and to the owner of the task
    field_policy :hours do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(owner_id == ^actor(:id))
    end

    # never visible to a member
    field_policy [:secret, :code] do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :title, :string, public?: true
    attribute :hours, :integer, public?: true
    attribute :secret, :integer, public?: true
    attribute :code, :string, public?: true
    attribute :owner_id, :uuid, public?: true
    attribute :org_id, :uuid, public?: true
  end
end

defmodule Ashbug.Ets.Link do
  use Ash.Resource, domain: Ashbug.Ets, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]


  actions do
    defaults [:read, create: :*]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    attribute :org_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :task_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
  end
end

defmodule Ashbug.Ets.Org do
  use Ash.Resource, domain: Ashbug.Ets, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]


  actions do
    defaults [:read, create: :*]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :name, :string, public?: true
  end

  relationships do
    has_many :tasks, Ashbug.Ets.Task, destination_attribute: :org_id, public?: true, read_action: :paged

    many_to_many :linked_tasks, Ashbug.Ets.Task,
      through: Ashbug.Ets.Link,
      source_attribute_on_join_resource: :org_id,
      destination_attribute_on_join_resource: :task_id,
      public?: true,
      read_action: :paged
  end
end

defmodule Ashbug.Ets do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Ashbug.Ets.Org
    resource Ashbug.Ets.Task
    resource Ashbug.Ets.Link
  end
end
