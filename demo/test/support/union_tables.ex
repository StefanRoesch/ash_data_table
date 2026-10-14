defmodule Demo.Support.Unions do
  @moduledoc """
  A domain for the tests of what a table does with a union
  (`Ash.Type.Union`), where the demo's own tables do not have the case. Its
  resource exists for the tests only and keeps its records in memory.
  """
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Demo.Support.Unions.Gift
  end
end

defmodule Demo.Support.Unions.Lid do
  @moduledoc "An embedded resource inside a kind of a union."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :colour, :string, allow_nil?: false, public?: true
  end
end

defmodule Demo.Support.Unions.Box do
  @moduledoc "A kind made of fields, one of them a value that can be left out."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :label, :string, allow_nil?: false, public?: true, constraints: [min_length: 2]
    attribute :lid, Demo.Support.Unions.Lid, public?: true
    # private: never shown, never asked for
    attribute :memo, :string
  end
end

defmodule Demo.Support.Unions.Card do
  @moduledoc "A kind of a tagged union that says its own kind in an attribute."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :type, :atom, allow_nil?: false, public?: true, constraints: [one_of: [:card]]
    attribute :number, :string, allow_nil?: false, public?: true
  end
end

defmodule Demo.Support.Unions.Transfer do
  @moduledoc "Another kind of that union, which has no attribute for the tag."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :iban, :string, allow_nil?: false, public?: true
  end
end

defmodule Demo.Support.Unions.Holder do
  @moduledoc "An embedded resource with a union inside it."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :name, :string, public?: true

    attribute :either, :union,
      public?: true,
      constraints: [
        types: [
          text: [type: :string],
          number: [type: :integer, constraints: [min: 0]],
          box: [type: Demo.Support.Unions.Box]
        ]
      ]
  end
end

defmodule Demo.Support.Unions.Gift do
  @moduledoc """
  A gift with one column per kind of union.

  `content` is a text, an amount, a day, a yes or no, or a box, which is an
  embedded resource with another inside it. `must` cannot be empty.
  `payment` is a tagged union of two embedded resources. `holder` is an
  embedded resource with a union in it, and `holders` an array of them.
  `extras` is an array of unions, and `odd` a union with a kind a table has
  no control for: both are shown and not edited.

  `send` takes a union as an argument besides `content`, and `tally` is a
  table action with one. `update` refuses a gift that is called "Locked".
  """
  use Ash.Resource,
    domain: Demo.Support.Unions,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  alias Demo.Support.Unions.{Box, Card, Holder, Transfer}

  table do
    update_action :update
    label_field :name

    column :name
    column :content

    column :must do
      label "Wrapping"
    end

    column :payment
    column :holder
    column :holders
    column :extras
    column :odd
    column :seal
    column :locker

    action :send
    action :tally
    create_action :create
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :content, :must, :seal]
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:name, :content, :must, :payment, :holder, :holders, :extras, :odd, :seal, :locker]

      validate fn changeset, _context ->
        if Ash.Changeset.get_attribute(changeset, :name) == "Locked",
          do: {:error, field: :name, message: "is locked"},
          else: :ok
      end
    end

    update :send do
      require_atomic? false
      accept [:content]

      argument :note, :union,
        allow_nil?: false,
        constraints: [
          types: [text: [type: :string, constraints: [min_length: 3]], on: [type: :date]]
        ]

      change fn changeset, _context ->
        said =
          case Ash.Changeset.get_argument(changeset, :note) do
            %Ash.Union{type: :text, value: text} -> "text #{text}"
            %Ash.Union{type: :on, value: day} -> "on #{day}"
            other -> inspect(other)
          end

        Ash.Changeset.force_change_attribute(changeset, :sent, said)
      end
    end

    action :tally, :string do
      argument :by, :union,
        constraints: [
          types: [amount: [type: :integer, constraints: [min: 1]], word: [type: :string]]
        ]

      run fn input, _context ->
        case input.arguments[:by] do
          nil -> {:ok, "by nothing"}
          %Ash.Union{type: kind, value: value} -> {:ok, "by #{kind} #{value}"}
        end
      end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true

    attribute :content, :union,
      public?: true,
      constraints: [
        types: [
          text: [type: :string, constraints: [min_length: 2]],
          amount: [type: :integer, constraints: [min: 0]],
          on: [type: :date],
          wrapped: [type: :boolean],
          box: [type: Box],
          spot: [type: :map, constraints: [fields: [x: [type: :integer], y: [type: :integer]]]]
        ]
      ]

    # cannot be empty, and has no default: a new gift has to be given one
    attribute :seal, :union,
      allow_nil?: false,
      public?: true,
      constraints: [types: [wax: [type: :string], stamps: [type: :integer]]]

    # a kind with a field policy of its own: `combination` is the admin's
    attribute :locker, :union,
      public?: true,
      constraints: [types: [code: [type: :string], vault: [type: Demo.Support.Maps.Vault]]]

    attribute :must, :union,
      allow_nil?: false,
      default: %Ash.Union{type: :paper, value: "plain"},
      public?: true,
      constraints: [
        types: [paper: [type: :string], ribbons: [type: :integer, constraints: [min: 1]]]
      ]

    attribute :payment, :union,
      public?: true,
      constraints: [
        types: [
          card: [type: Card, tag: :type, tag_value: :card],
          transfer: [type: Transfer, tag: :type, tag_value: :transfer, cast_tag?: false]
        ]
      ]

    attribute :holder, Holder, public?: true
    attribute :holders, {:array, Holder}, public?: true

    attribute :extras, {:array, :union},
      public?: true,
      constraints: [items: [types: [text: [type: :string], amount: [type: :integer]]]]

    attribute :odd, :union,
      public?: true,
      constraints: [
        types: [
          text: [type: :string],
          pair: [type: :tuple, constraints: [fields: [left: [type: :integer]]]]
        ]
      ]

    attribute :sent, :string, public?: true
  end
end
