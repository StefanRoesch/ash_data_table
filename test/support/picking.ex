defmodule AshDataTable.Test.Picking do
  @moduledoc """
  Resources for the tests of the picker: reference cells that are edited by
  choosing a record of the destination's table, and inputs of actions that
  are given the same way.

  The actors of these tests are maps: `%{role: :admin}`.
  """
end

defmodule AshDataTable.Test.Picking.Depot do
  @moduledoc """
  A destination everybody reads, called by its name: its table reads through
  the primary read action, in pages.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :open?, :boolean, public?: true, default: true
  end

  relationships do
    has_many :shipments, AshDataTable.Test.Picking.Shipment, public?: true
  end

  actions do
    defaults [:destroy, create: [:name], update: [:name]]

    read :read do
      primary? true
      pagination offset?: true, keyset?: true, default_limit: 10, required?: false
    end

    # the action of one relationship: without pages
    read :open do
      filter expr(open? == true)
    end

    # and one that pages by keyset alone
    read :recent do
      pagination keyset?: true, default_limit: 5, required?: false
    end
  end

  table do
    update_action :update
    label_field :name
    paginate_with :offset

    column :name do
      confirm "Rename the depot?"
    end

    column :open?

    relationship :shipments

    action :destroy do
      confirm "Delete this depot?"
    end

    create_action :create
  end
end

defmodule AshDataTable.Test.Picking.Vault do
  @moduledoc """
  A destination everybody is shown the label of, through the primary read
  action, and only an admin can ever list, through the read action of its
  table.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :code, :string, public?: true
  end

  actions do
    defaults [:read]

    read :listed
  end

  policies do
    policy action(:read) do
      authorize_if always()
    end

    policy action(:listed) do
      access_type :strict
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  table do
    read_action :listed
    label_field :code
  end
end

defmodule AshDataTable.Test.Picking.Port do
  @moduledoc "A destination without a table: nothing to choose its records from."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshDataTable.Test.Picking.Zone do
  @moduledoc """
  A destination that is pointed at by an attribute that is not its primary
  key, which has two attributes: a zone is known by its code.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    attribute :country, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :number, :integer, primary_key?: true, allow_nil?: false, public?: true
    attribute :code, :string, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, create: [:country, :number, :code]]
  end

  identities do
    identity :unique_code, [:code], pre_check_with: AshDataTable.Test.Domain
  end

  table do
    label_field :code
  end
end

defmodule AshDataTable.Test.Picking.Shipment do
  @moduledoc """
  A table with reference columns of every kind the picker has to tell
  apart: by what their relationship is, and by what the update action
  accepts.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  alias AshDataTable.Test.Picking.{Depot, Port, Vault, Zone}

  attributes do
    uuid_primary_key :id
    attribute :code, :string, public?: true
    # the key of a relationship the resource does not have
    attribute :batch_id, :uuid, public?: true
    # and of one that is private
    attribute :ghost_id, :uuid, public?: true
  end

  relationships do
    # can be empty: "none" can be chosen
    belongs_to :depot, Depot, public?: true
    # cannot
    belongs_to :origin, Depot, allow_nil?: false, public?: true

    # read through an action of its own, which the picker reads through too
    belongs_to :relay, Depot do
      read_action :open
      public? true
    end

    # with a filter: a table cannot say which records it can hold
    belongs_to :haven, Depot do
      filter expr(open? == true)
      public? true
    end

    # its key is no input of `update`
    belongs_to :auditor, Depot, public?: true
    # its key is not written from the outside, so no action accepts it
    belongs_to :sealer, Depot, public?: true, attribute_writable?: false
    # its key is private
    belongs_to :owner, Depot, public?: true, attribute_public?: false
    # its key is seen by admins alone
    belongs_to :backer, Depot, public?: true
    # listed by admins alone
    belongs_to :vault, Vault, public?: true
    # saved through an action of its own, after a question
    belongs_to :broker, Depot, public?: true
    # switched off in the block
    belongs_to :courier, Depot, public?: true
    # no table at its destination
    belongs_to :port, Port, public?: true

    # joined by an attribute that is not the destination's primary key
    belongs_to :zone, Zone do
      source_attribute :zone_code
      destination_attribute :code
      attribute_type :string
      public? true
    end

    belongs_to :ghost, Depot do
      source_attribute :ghost_id
      define_attribute? false
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:code, :depot_id, :origin_id, :haven_id, :port_id, :batch_id, :ghost_id, :zone_code]
    end

    update :update do
      primary? true

      accept [
        :code,
        :depot_id,
        :origin_id,
        :relay_id,
        :haven_id,
        :owner_id,
        :backer_id,
        :vault_id,
        :courier_id,
        :port_id,
        :zone_code
      ]
    end

    update :rebroker do
      accept [:broker_id]
    end

    update :move do
      accept [:depot_id]
      argument :reason, :string, allow_nil?: false
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :backer_id do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    update_action :update

    column :code
    column :depot
    column :origin
    column :relay
    column :haven
    column :auditor
    column :sealer
    column :owner
    column :backer
    column :vault

    column :broker do
      update_action :rebroker
      confirm "Change the broker?"
    end

    column :courier do
      update_action false
    end

    column :zone

    action :move
    create_action :create
  end
end

defmodule AshDataTable.Test.Picking.Crate do
  @moduledoc """
  A table that has no column for the depot a crate is in, and a create
  action that takes its key.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :label, :string, public?: true
  end

  relationships do
    belongs_to :depot, AshDataTable.Test.Picking.Depot, public?: true
  end

  actions do
    defaults [:read, create: [:label, :depot_id]]
  end

  table do
    column :label
    create_action :create
  end
end

defmodule AshDataTable.Test.Picking.Unguarded do
  @moduledoc "A domain whose tables do not authorize."
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

  table do
    authorize? false
  end

  resources do
    allow_unregistered? true
  end
end

defmodule AshDataTable.Test.Picking.Locker do
  @moduledoc "A destination nobody may read, in a domain whose tables do not authorize."
  use Ash.Resource,
    domain: AshDataTable.Test.Picking.Unguarded,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read, create: [:name]]
  end

  policies do
    policy action_type(:read) do
      forbid_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  table do
    label_field :name
  end
end
