defmodule Demo.Support.Route do
  @moduledoc """
  A domain for the tests of the picker where a related record is not named
  by one UUID: a destination with a primary key of two attributes that is
  pointed at by another attribute of its own, and one whose key is a number;
  and of a destination that is multitenant, where nothing but the tenant
  says whose records are whose.
  Its resources exist for the tests only and keep their records in memory.

  The actors of these tests are maps: `%{role: :admin}`.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

  table do
    actor_assign :reader
  end

  resources do
    resource Demo.Support.Route.Zone
    resource Demo.Support.Route.Bay
    resource Demo.Support.Route.Dock
    resource Demo.Support.Route.Stop
  end
end

defmodule Demo.Support.Route.Zone do
  @moduledoc """
  A zone: its primary key is a country and a number, and a stop points at it
  by its code. A zone that is closed is read by admins alone.
  """
  use Ash.Resource,
    domain: Demo.Support.Route,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  table do
    label_field :name

    column :name
    column :code
    column :country
    column :number
  end

  actions do
    defaults [:read, create: [:country, :number, :code, :name, :closed]]
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(closed == false)
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  attributes do
    attribute :country, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :number, :integer, primary_key?: true, allow_nil?: false, public?: true
    attribute :code, :string, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
    attribute :closed, :boolean, default: false, public?: true
  end

  identities do
    identity :unique_code, [:code], pre_check_with: Demo.Support.Route
  end
end

defmodule Demo.Support.Route.Bay do
  @moduledoc """
  A loading bay, whose key is its number. The relationship of a stop to its
  bay reads through an action of its own, which returns the free ones.
  Nobody reads any bay while the gate (`Demo.Support.Gate`) is closed.
  """
  use Ash.Resource,
    domain: Demo.Support.Route,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  table do
    label_field :name

    column :number
    column :name
  end

  actions do
    defaults [:read, create: [:number, :name, :free]]

    read :free do
      filter expr(free == true)
    end
  end

  policies do
    policy action_type(:read) do
      access_type :strict
      authorize_if Demo.Support.Gate
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  attributes do
    attribute :number, :integer, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
    attribute :free, :boolean, default: true, public?: true
  end
end

defmodule Demo.Support.Route.Dock do
  @moduledoc """
  A dock of a region, which is its tenant. It has no policies: that a person
  of one region does not read the docks of another is the tenant's doing
  alone. Read without a tenant, it returns the docks of every region.
  """
  use Ash.Resource,
    domain: Demo.Support.Route,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  table do
    label_field :name

    column :name
  end

  actions do
    defaults [:read, create: [:name, :region]]
  end

  multitenancy do
    strategy :attribute
    attribute :region
    global? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :region, :string, allow_nil?: false, public?: true
  end
end

defmodule Demo.Support.Route.Stop do
  @moduledoc """
  A stop of a route, in a zone and at a bay, both of which are chosen in
  the picker. The zone of a stop that is sealed is seen by admins alone.
  """
  use Ash.Resource,
    domain: Demo.Support.Route,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  field_policies do
    field_policy :zone_code do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(sealed == false)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    update_action :update

    column :title
    column :zone

    # saved through an action of its own, which leaves a trace
    column :bay do
      update_action :rebay
    end

    column :dock

    action :reroute
    action :dock_at
    create_action :create
  end

  actions do
    defaults [
      :read,
      create: [:title, :sealed, :zone_code, :bay_number, :dock_id],
      update: [:title, :zone_code, :bay_number, :dock_id]
    ]

    update :dock_at do
      accept [:dock_id]
    end

    # says that it ran: a choice that changes nothing must not run it
    update :rebay do
      accept [:bay_number]
      change set_attribute(:rebays, 1)
    end

    update :reroute do
      accept [:zone_code, :bay_number]
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :sealed, :boolean, default: false, public?: true
    attribute :rebays, :integer, default: 0
  end

  relationships do
    belongs_to :zone, Demo.Support.Route.Zone do
      source_attribute :zone_code
      destination_attribute :code
      attribute_type :string
      public? true
    end

    belongs_to :bay, Demo.Support.Route.Bay do
      source_attribute :bay_number
      destination_attribute :number
      attribute_type :integer
      read_action :free
      public? true
    end

    belongs_to :dock, Demo.Support.Route.Dock, public?: true
  end
end
