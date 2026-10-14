defmodule AshDataTable.Test.Embedding.Place do
  @moduledoc "An embedded resource without a primary key, with a private attribute."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :street, :string, allow_nil?: false, public?: true
    attribute :city, :string, public?: true
    attribute :open?, :boolean, allow_nil?: false, default: false, public?: true
    attribute :kind, :atom, public?: true, constraints: [one_of: [:office, :main_depot]]
    attribute :opens_at, :time, public?: true
    attribute :tags, {:array, :string}, public?: true
    attribute :token, :string, public?: true
    attribute :memo, :string
  end
end

defmodule AshDataTable.Test.Embedding.Contact do
  @moduledoc "An embedded resource with another one inside it."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :place, AshDataTable.Test.Embedding.Place, public?: true
    attribute :places, {:array, AshDataTable.Test.Embedding.Place}, public?: true
  end
end

defmodule AshDataTable.Test.Embedding.Part do
  @moduledoc "An embedded resource with a public primary key that no action accepts."
  use Ash.Resource, data_layer: :embedded

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :made_at, :utc_datetime, public?: true, writable?: false
  end
end

defmodule AshDataTable.Test.Embedding.Coded do
  @moduledoc "An embedded resource whose primary key is an input."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :code, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :label, :string, public?: true
  end
end

defmodule AshDataTable.Test.Embedding.Sealed do
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

defmodule AshDataTable.Test.Embedding.Mixed do
  @moduledoc "An embedded resource with an input a table has no control for."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :label, :string, public?: true

    attribute :pair, :tuple,
      public?: true,
      constraints: [fields: [left: [type: :integer], right: [type: :integer]]]
  end
end

defmodule AshDataTable.Test.Embedding.Argued do
  @moduledoc "An embedded resource whose create action does not run without an argument."
  use Ash.Resource, data_layer: :embedded

  actions do
    defaults [:read, :destroy, update: [:label]]

    create :create do
      primary? true
      accept [:label]
      argument :reason, :string, allow_nil?: false
    end
  end

  attributes do
    attribute :label, :string, public?: true
  end
end

defmodule AshDataTable.Test.Embedding.Stamped do
  @moduledoc "An embedded resource whose create action requires a private attribute."
  use Ash.Resource, data_layer: :embedded

  actions do
    defaults [:read, :destroy, create: [:label, :stamp], update: [:label, :stamp]]
  end

  attributes do
    attribute :label, :string, public?: true
    attribute :stamp, :string, allow_nil?: false
  end
end

defmodule AshDataTable.Test.Embedding.Named do
  @moduledoc """
  An embedded resource cast through actions the attribute names, one of
  them private: `draft` accepts less than the primary create action.
  """
  use Ash.Resource, data_layer: :embedded

  actions do
    defaults [:read, :destroy, create: [:label, :note], update: [:label, :note]]

    create :draft do
      public? false
      accept [:label]
    end

    update :redraft do
      accept [:label]
    end
  end

  attributes do
    attribute :label, :string, public?: true
    attribute :note, :string, public?: true
  end
end

defmodule AshDataTable.Test.Embedding.Layout do
  @moduledoc "A NewType of a map that declares its fields."
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        columns: [type: :integer, allow_nil?: false],
        dense?: [type: :boolean]
      ]
    ]
end

defmodule AshDataTable.Test.Embedding.Point do
  @moduledoc "A typed struct: no cell of its own."
  use Ash.TypedStruct

  typed_struct do
    field :x, :integer
    field :y, :integer
  end
end

defmodule AshDataTable.Test.Embedding do
  @moduledoc "One column per kind of value that is made of fields."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  alias AshDataTable.Test.Embedding.{Argued, Coded, Contact, Layout, Mixed, Named, Part, Place}
  alias AshDataTable.Test.Embedding.{Point, Sealed, Stamped}

  table do
    update_action :update

    action :move
    create_action :create
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :place, :base, :parts]
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :name,
        :place,
        :base,
        :contact,
        :parts,
        :codes,
        :places,
        :settings,
        :layout,
        :entries,
        :notes,
        :notes_list,
        :sealed,
        :mixed,
        :argued,
        :stamped,
        :replaced,
        :named,
        :nameds,
        :point,
        :keyword
      ]
    end

    update :move do
      require_atomic? false
      accept [:place, :places, :notes]
      argument :stops, {:array, Place}
      argument :reason, :string, allow_nil?: false
    end

    # Fails with errors about fields of values inside the record, each with
    # the way to its value as Ash says it: its path, and for a value of an
    # array of maps its place among its variables, if at all.
    update :refuse do
      require_atomic? false
      accept [:place, :contact, :places, :entries, :settings]

      change fn changeset, _context ->
        invalid = fn field, path, vars ->
          Ash.Error.Changes.InvalidAttribute.exception(
            field: field,
            message: "is refused",
            path: path,
            vars: vars
          )
        end

        Ash.Changeset.add_error(changeset, [
          invalid.(:street, [:place], []),
          invalid.(:bogus, [:place], []),
          invalid.(:street, [:contact], []),
          invalid.(:street, [:places, 0], []),
          invalid.(:street, [:contact, :places, 2], []),
          invalid.(:label, [:entries], []),
          invalid.(:label, [:entries], index: 1),
          invalid.(:low, [:settings, :limits], []),
          invalid.(:limits, [:settings], []),
          invalid.(:name, [:parts, 0], []),
          invalid.(:name, [:elsewhere, 0], [])
        ])
      end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :place, Place, public?: true
    attribute :base, Place, allow_nil?: false, public?: true
    attribute :contact, Contact, public?: true
    attribute :parts, {:array, Part}, public?: true
    attribute :codes, {:array, Coded}, public?: true
    attribute :places, {:array, Place}, public?: true

    attribute :settings, :map do
      public? true

      constraints fields: [
                    title: [type: :string, allow_nil?: false],
                    count: [type: :integer, constraints: [min: 0]],
                    mode: [type: :atom, constraints: [one_of: [:fast, :extra_slow]]],
                    limits: [type: :map, constraints: [fields: [low: [type: :integer]]]],
                    place: [type: Place]
                  ]
    end

    attribute :layout, Layout, public?: true

    attribute :entries, {:array, :map},
      public?: true,
      constraints: [items: [fields: [label: [type: :string, allow_nil?: false]]]]

    attribute :notes, :map, public?: true
    attribute :notes_list, {:array, :map}, public?: true
    attribute :sealed, Sealed, public?: true
    attribute :mixed, Mixed, public?: true
    attribute :argued, Argued, public?: true
    attribute :stamped, Stamped, public?: true
    # always created anew: only the create action matters
    attribute :replaced, Sealed, public?: true, constraints: [on_update: :replace]

    attribute :named, Named,
      public?: true,
      constraints: [create_action: :draft, update_action: :redraft]

    attribute :nameds, {:array, Named},
      public?: true,
      constraints: [items: [create_action: :draft]]

    # a map with a field a table has no control for
    attribute :loose, :map,
      public?: true,
      constraints: [fields: [label: [type: :string], inner: [type: :map]]]

    # types that look like these and have no cell of their own
    attribute :point, Point, public?: true
    attribute :keyword, :keyword, public?: true, constraints: [fields: [a: [type: :string]]]

    attribute :struct, :struct,
      public?: true,
      constraints: [instance_of: Place, fields: [street: [type: :string]]]
  end
end
