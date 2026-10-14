defmodule Demo.Support.Lists do
  @moduledoc """
  A domain for the tests of what a table does with a column that is an
  array. Its resource exists for the tests only and keeps its records in
  memory.
  """
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Demo.Support.Lists.Roster
    resource Demo.Support.Lists.Earlier
  end
end

defmodule Demo.Support.Lists.Stage do
  @moduledoc false
  use Ash.Type.Enum,
    values: [
      draft: [label: "Draft"],
      in_review: [label: "In review"],
      done: [label: "Done"]
    ]
end

defmodule Demo.Support.Lists.Roster do
  @moduledoc """
  A roster with one array per kind of value a table has an editor for, and
  the arrays it has none for.

  `words` takes at most three values of at least two characters. `gaps`
  takes values that are empty, and says that an empty text is one of them
  (`empty_values: []`). `stages` is saved through an action of its
  own, which leaves a trace, and asks first. `frozen` is accepted by no
  action, and `sealed` is switched off in the block. `misplace` fails with
  an error about a record nested in the roster. A viewer changes nothing,
  and sees `secrets` on no roster.
  """
  use Ash.Resource,
    domain: Demo.Support.Lists,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  field_policies do
    field_policy :secrets do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    update_action :update

    column :name
    column :words
    column :numbers
    column :gaps
    column :days
    column :moments
    column :switches

    column :stages do
      update_action :restage
      confirm "Change the stages?"
    end

    column :sizes

    # shown by a component, and edited with the table's own editor
    column :marks do
      component DemoWeb.Support.Cells.Probe
    end

    column :frozen

    column :sealed do
      update_action false
    end

    column :secrets
    # arrays a table has no cell for
    column :keys
    column :grid

    # opens the panel: arrays among its attributes, and one as an argument
    action :revise
    # fails with an error about a field of something nested in the roster
    action :misplace

    create_action :create
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :words, :numbers, :switches, :stages, :sizes]
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :name,
        :words,
        :numbers,
        :gaps,
        :days,
        :moments,
        :switches,
        :sizes,
        :marks,
        :sealed,
        :secrets,
        :keys,
        :grid
      ]
    end

    update :restage do
      accept [:stages]
      require_atomic? false
      change set_attribute(:trace, "restage")
    end

    # What an action that manages nested records returns when one of them is
    # refused: an error that names a field of the nested record, with the way
    # to that record as its path.
    update :misplace do
      accept []
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.add_error(
          changeset,
          Ash.Error.Changes.InvalidAttribute.exception(
            field: :name,
            message: "is nested",
            path: [:parts, 0]
          )
        )
      end
    end

    update :revise do
      accept [:name, :words, :stages, :switches, :sizes]
      require_atomic? false
      argument :weights, {:array, :integer}, allow_nil?: false, constraints: [min_length: 1]
      change set_attribute(:trace, "revise")
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

    attribute :words, {:array, :string} do
      allow_nil? false
      default []
      public? true
      constraints max_length: 3, items: [min_length: 2, max_length: 12]
    end

    attribute :numbers, {:array, :decimal}, public?: true

    attribute :gaps, {:array, :integer} do
      public? true
      constraints nil_items?: true, empty_values: []
    end

    attribute :days, {:array, :date}, public?: true
    attribute :moments, {:array, :utc_datetime}, public?: true
    attribute :switches, {:array, :boolean}, public?: true

    attribute :stages, {:array, Demo.Support.Lists.Stage} do
      public? true
      constraints min_length: 1
    end

    attribute :sizes, {:array, :atom} do
      public? true
      constraints items: [one_of: [:small, :extra_large]]
    end

    attribute :marks, {:array, :integer}, public?: true
    attribute :frozen, {:array, :string}, public?: true
    attribute :sealed, {:array, :string}, public?: true
    attribute :secrets, {:array, :string}, public?: true
    attribute :keys, {:array, :uuid}, public?: true
    attribute :grid, {:array, {:array, :integer}}, allow_nil?: false, default: [], public?: true
    # which action changed the record last: private, never a column
    attribute :trace, :string
  end
end

defmodule Demo.Support.Lists.Earlier do
  @moduledoc """
  The rosters as they were before `sizes` lost a value: the same records,
  kept in the same table, with `:medium` still one of the sizes. A test
  writes a roster through it that holds a size `Demo.Support.Lists.Roster`
  no longer has.
  """
  use Ash.Resource,
    domain: Demo.Support.Lists,
    data_layer: Ash.DataLayer.Ets

  ets do
    table Demo.Support.Lists.Roster
  end

  actions do
    defaults [:read, create: [:name, :sizes]]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true

    attribute :sizes, {:array, :atom} do
      public? true
      constraints items: [one_of: [:small, :medium, :extra_large]]
    end
  end
end
