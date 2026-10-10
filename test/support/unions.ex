defmodule AshTable.Test.Unions.Place do
  @moduledoc "An embedded resource that is one kind of a union."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :street, :string, allow_nil?: false, public?: true
    attribute :city, :string, public?: true, constraints: [min_length: 2]
    attribute :memo, :string
  end
end

defmodule AshTable.Test.Unions.Card do
  @moduledoc "An embedded resource that says its own kind: a member of a tagged union."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :type, :atom, public?: true, constraints: [one_of: [:card]]
    attribute :number, :string, allow_nil?: false, public?: true
  end
end

defmodule AshTable.Test.Unions.Transfer do
  @moduledoc "Another member of a tagged union, without an attribute for its tag."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :iban, :string, allow_nil?: false, public?: true
  end
end

defmodule AshTable.Test.Unions.Holder do
  @moduledoc "An embedded resource with a union inside it."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :label, :string, public?: true

    attribute :either, :union,
      public?: true,
      constraints: [
        types: [
          text: [type: :string],
          number: [type: :integer, constraints: [min: 0]],
          place: [type: AshTable.Test.Unions.Place]
        ]
      ]

    # a second union with a kind of the same fields
    attribute :other, :union,
      public?: true,
      constraints: [types: [text: [type: :string], place: [type: AshTable.Test.Unions.Place]]]
  end
end

defmodule AshTable.Test.Unions.Content do
  @moduledoc "A NewType of a union."
  use Ash.Type.NewType,
    subtype_of: :union,
    constraints: [
      types: [
        text: [type: :string, constraints: [max_length: 20]],
        amount: [type: :integer, constraints: [min: 0]]
      ]
    ]
end

defmodule AshTable.Test.Unions do
  @moduledoc "One column per kind of union."
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  alias AshTable.Test.Unions.{Card, Content, Holder, Place, Transfer}

  table do
    update_action :update
    create_action :create
    action :note
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :value, :payment]
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :name,
        :value,
        :required,
        :payment,
        :content,
        :values,
        :odd,
        :listed,
        :holder,
        :holders
      ]
    end

    # Fails with errors about a union and about fields of the value of one
    # of its kinds, each with the way to it as Ash says it.
    update :refuse do
      require_atomic? false
      accept [:value, :holder, :holders]

      change fn changeset, _context ->
        invalid = fn field, path ->
          Ash.Error.Changes.InvalidAttribute.exception(
            field: field,
            message: "is refused",
            path: path
          )
        end

        Ash.Changeset.add_error(changeset, [
          invalid.(:value, []),
          invalid.(:street, [:value]),
          invalid.(:bogus, [:value]),
          invalid.(:either, [:holder]),
          invalid.(:street, [:holder, :either]),
          invalid.(:city, [:holder, :other]),
          # Ash names the value around it: two values in it have the field
          invalid.(:street, [:holder]),
          invalid.(:street, [:holders, 1, :either])
        ])
      end
    end

    update :note do
      require_atomic? false
      argument :value, :union, constraints: [types: [text: [type: :string], on: [type: :date]]]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true

    # untagged: a simple kind, a number, a choice, and an embedded resource
    attribute :value, :union,
      public?: true,
      constraints: [
        types: [
          amount: [type: :integer, constraints: [min: 0]],
          done: [type: :boolean],
          shade: [type: :atom, constraints: [one_of: [:light, :dark]]],
          place: [type: Place],
          spot: [
            type: :map,
            constraints: [fields: [x: [type: :integer, allow_nil?: false], y: [type: :integer]]]
          ],
          text: [type: :string]
        ]
      ]

    attribute :required, :union,
      public?: true,
      allow_nil?: false,
      default: %Ash.Union{type: :text, value: "x"},
      constraints: [types: [text: [type: :string], amount: [type: :integer]]]

    # tagged
    attribute :payment, :union,
      public?: true,
      constraints: [
        types: [
          card: [type: Card, tag: :type, tag_value: :card],
          transfer: [type: Transfer, tag: :type, tag_value: :transfer, cast_tag?: false]
        ]
      ]

    attribute :content, Content, public?: true

    attribute :values, {:array, :union},
      public?: true,
      constraints: [items: [types: [text: [type: :string], amount: [type: :integer]]]]

    # a union inside an embedded resource, and inside one of an array
    attribute :holder, Holder, public?: true
    attribute :holders, {:array, Holder}, public?: true

    # a kind that is an array
    attribute :listed, :union,
      public?: true,
      constraints: [types: [text: [type: :string], tags: [type: {:array, :string}]]]

    # a kind a table has no control for
    attribute :odd, :union,
      public?: true,
      constraints: [
        types: [
          text: [type: :string],
          pair: [type: :tuple, constraints: [fields: [a: [type: :integer]]]]
        ]
      ]

    update_timestamp :updated_at
  end
end

defmodule AshTable.Test.Unions.Once do
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

defmodule AshTable.Test.Unions.Odd do
  @moduledoc "Unions where a table has no input for them: on the argument line, and of kinds without a control."
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  table do
    action :mark
  end

  actions do
    default_accept []
    defaults [:create]

    read :read do
      primary? true
      argument :either, :union, constraints: [types: [text: [type: :string]]]
    end

    update :mark do
      require_atomic? false
      argument :reason, :string, allow_nil?: false

      argument :odd, :union,
        constraints: [
          types: [pair: [type: :tuple, constraints: [fields: [a: [type: :integer]]]]]
        ]

      argument :values, {:array, :union}, constraints: [items: [types: [text: [type: :string]]]]
    end
  end

  attributes do
    uuid_primary_key :id
  end
end
