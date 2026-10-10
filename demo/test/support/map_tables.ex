defmodule Demo.Support.Maps do
  @moduledoc """
  A domain for the tests of what a table does with a column whose value is
  made of fields: an embedded resource, a map, or an array of either. Its
  resource exists for the tests only and keeps its records in memory.
  """
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Demo.Support.Maps.Site
  end
end

defmodule Demo.Support.Maps.Kind do
  @moduledoc false
  use Ash.Type.Enum, values: [office: [label: "Office"], depot: [label: "Depot"]]
end

defmodule Demo.Support.Maps.Place do
  @moduledoc """
  An embedded resource without a primary key: one field per kind of control.
  Its city has a validation of the resource's own, beside the constraints.
  """
  use Ash.Resource, data_layer: :embedded

  validations do
    validate string_length(:city, max: 12), message: "is too long for a sign"
  end

  attributes do
    attribute :street, :string, allow_nil?: false, public?: true, constraints: [min_length: 3]
    attribute :city, :string, allow_nil?: false, public?: true
    attribute :floor, :integer, public?: true, constraints: [min: 0]
    attribute :open?, :boolean, allow_nil?: false, default: false, public?: true
    attribute :since, :date, public?: true
    attribute :kind, Demo.Support.Maps.Kind, public?: true
    # written as one line of text: a table has no editor of its own for it
    attribute :opens_at, :time, public?: true
    # private: never shown, never asked for
    attribute :memo, :string
  end
end

defmodule Demo.Support.Maps.Contact do
  @moduledoc "An embedded resource with another one inside it, and with arrays of plain values."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :place, Demo.Support.Maps.Place, public?: true
    attribute :phones, {:array, :string}, public?: true, constraints: [items: [min_length: 3]]
    attribute :kinds, {:array, Demo.Support.Maps.Kind}, public?: true
  end
end

defmodule Demo.Support.Maps.Part do
  @moduledoc """
  An embedded resource with a public primary key, of which a site holds a
  list. Ash updates the parts that are still in the list when it is saved,
  which the private `trace` shows: only `update` writes it.
  """
  use Ash.Resource, data_layer: :embedded

  actions do
    defaults [:read, :destroy, create: [:name, :quantity]]

    update :update do
      primary? true
      accept [:name, :quantity]
      change set_attribute(:trace, "updated")
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true, constraints: [min_length: 2]
    attribute :quantity, :integer, public?: true, constraints: [min: 0]
    attribute :trace, :string
  end
end

defmodule Demo.Support.Maps.Sealed do
  @moduledoc "An embedded resource whose create and update actions accept different attributes."
  use Ash.Resource, data_layer: :embedded

  actions do
    defaults [:read, :destroy, create: [:code, :label], update: [:label]]
  end

  attributes do
    attribute :code, :string, public?: true
    attribute :label, :string, public?: true
  end
end

defmodule Demo.Support.Maps.Mixed do
  @moduledoc "An embedded resource with an input a table has no control for: a union."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :label, :string, public?: true

    attribute :either, :union,
      public?: true,
      constraints: [types: [text: [type: :string], number: [type: :integer]]]
  end
end

defmodule Demo.Support.Maps.Vault do
  @moduledoc """
  An embedded resource with a field policy of its own: `combination` is the
  admin's alone. Ash applies it when the site is read.
  """
  use Ash.Resource, data_layer: :embedded, authorizers: [Ash.Policy.Authorizer]

  field_policies do
    field_policy :combination do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    attribute :label, :string, public?: true
    attribute :combination, :string, public?: true
  end
end

defmodule Demo.Support.Maps.Site do
  @moduledoc """
  A site with one column per kind of value that is made of fields.

  `place` is an embedded resource, `contact` one with another inside it,
  `parts` an array of embedded resources that have a primary key and
  `places` an array of ones that have none. `settings` is a map that
  declares its fields, one of them a map itself, and `entries` an array of
  such maps. `notes` is a map that declares none. `base` cannot be empty.
  `sealed` and `mixed` cannot be edited, each for a reason of its
  own, and `vault` holds a field that only an admin sees.

  `contact` is saved through an action of its own, which leaves a trace,
  and asks first. `update` refuses a site that is called "Locked". A viewer
  changes nothing.
  """
  use Ash.Resource,
    domain: Demo.Support.Maps,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  table do
    update_action :update
    label_field :name

    column :name
    column :place

    column :contact do
      update_action :recontact
      confirm "Change the contact?"
    end

    column :parts
    column :places
    column :settings
    column :entries
    column :notes
    column :base
    column :sealed
    column :mixed
    column :vault

    column :frozen do
      label "Kept"
    end

    # opens the panel: a value made of fields among its attributes
    action :relocate
    create_action :create
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :place, :base, :parts, :settings]
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :name,
        :place,
        :parts,
        :places,
        :settings,
        :entries,
        :notes,
        :base,
        :sealed,
        :mixed,
        :vault
      ]

      validate attribute_does_not_equal(:name, "Locked"), message: "is locked"
      change set_attribute(:trace, "update")
    end

    update :recontact do
      accept [:contact]
      require_atomic? false
      change set_attribute(:trace, "recontact")
    end

    update :relocate do
      accept [:place, :places]
      require_atomic? false
      argument :reason, :string, allow_nil?: false
      change set_attribute(:trace, "relocate")
    end
  end

  policies do
    policy action_type([:read, :create]) do
      authorize_if always()
    end

    policy action_type(:update) do
      forbid_if actor_attribute_equals(:role, :viewer)
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :place, Demo.Support.Maps.Place, public?: true
    attribute :contact, Demo.Support.Maps.Contact, public?: true
    attribute :parts, {:array, Demo.Support.Maps.Part}, public?: true

    attribute :places, {:array, Demo.Support.Maps.Place},
      public?: true,
      constraints: [max_length: 3]

    attribute :settings, :map do
      public? true

      constraints fields: [
                    title: [type: :string, allow_nil?: false, constraints: [min_length: 2]],
                    count: [type: :integer, constraints: [min: 0]],
                    mode: [type: :atom, constraints: [one_of: [:fast, :extra_slow]]],
                    limits: [
                      type: :map,
                      constraints: [fields: [low: [type: :integer], high: [type: :integer]]]
                    ]
                  ]
    end

    attribute :entries, {:array, :map} do
      public? true

      constraints items: [
                    fields: [
                      label: [type: :string, allow_nil?: false],
                      weight: [type: :decimal]
                    ]
                  ]
    end

    attribute :notes, :map, public?: true
    attribute :base, Demo.Support.Maps.Place, allow_nil?: false, public?: true
    attribute :sealed, Demo.Support.Maps.Sealed, public?: true
    attribute :mixed, Demo.Support.Maps.Mixed, public?: true
    attribute :vault, Demo.Support.Maps.Vault, public?: true
    # no action accepts it
    attribute :frozen, Demo.Support.Maps.Place, public?: true
    # which action changed the record last: private, never a column
    attribute :trace, :string
  end
end
