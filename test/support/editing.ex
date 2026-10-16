defmodule AshDataTable.Test.Editing do
  @moduledoc """
  A resource for the tests of what a table lets a person edit: a table-level
  update action, a column with its own action, a column switched off, and
  columns that no action can save.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true
    attribute :email, :ci_string, public?: true
    attribute :visits, :integer, public?: true
    attribute :weight, :float, public?: true
    attribute :price, :decimal, public?: true
    attribute :active, :boolean, public?: true
    attribute :due_on, :date, public?: true
    attribute :seen_at, :utc_datetime, public?: true
    attribute :status, AshDataTable.Test.Status, public?: true
    attribute :size, :atom, public?: true, constraints: [one_of: [:small, :large]]

    # accepted by the table's action, switched off in the block
    attribute :slug, :string, public?: true
    # not accepted by the table's action
    attribute :notes, :string, public?: true
    # arrays of values that have an editor: edited value by value, and an
    # array of enum values as multiple choice
    attribute :tags, {:array, :string}, public?: true
    attribute :scores, {:array, :integer}, public?: true
    attribute :stages, {:array, AshDataTable.Test.Status}, public?: true
    # an array the table's action does not accept
    attribute :aliases, {:array, :string}, public?: true
    # accepted, but of a type without an editor
    attribute :settings, :map, public?: true
    attribute :keys, {:array, :uuid}, public?: true
    attribute :grid, {:array, {:array, :integer}}, public?: true
    # never an input of any action
    attribute :locked, :string, public?: true, writable?: false
  end

  relationships do
    has_many :comments, AshDataTable.Test.Editing.Comment, destination_attribute: :subject_id
  end

  calculations do
    calculate :shouted_title, :string, expr(title <> "!"), public?: true
  end

  aggregates do
    count :comment_count, :comments, public?: true
  end

  actions do
    defaults [:read]

    update :update do
      primary? true
      # `grid`, an array of arrays, cannot be updated atomically (ash 3.36.1)
      require_atomic? false

      accept [
        :title,
        :email,
        :visits,
        :weight,
        :price,
        :active,
        :due_on,
        :seen_at,
        :status,
        :size,
        :slug,
        :tags,
        :scores,
        :stages,
        :settings,
        :keys,
        :grid
      ]
    end

    update :reprice do
      accept [:price]
    end
  end

  table do
    update_action :update

    column :id
    column :title
    column :email
    column :visits
    column :weight

    column :price do
      update_action :reprice
      confirm "Change the price?"
    end

    column :active
    column :due_on
    column :seen_at
    column :status
    column :size

    column :slug do
      update_action false
    end

    column :notes
    column :tags
    column :scores
    column :stages
    column :aliases
    column :settings
    column :keys
    column :grid
    column :locked
    column :shouted_title
    column :comment_count
  end
end

defmodule AshDataTable.Test.Editing.Comment do
  @moduledoc false
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
  end

  relationships do
    belongs_to :subject, AshDataTable.Test.Editing, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshDataTable.Test.Editing.NeedsArgument do
  @moduledoc "A table whose update action cannot run without a value that is not on the record."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :assignee, :string, public?: true
  end

  actions do
    defaults [:read]

    update :reassign do
      accept [:title, :assignee]
      argument :reason, :string, allow_nil?: false
    end
  end

  table do
    update_action :reassign
  end
end

defmodule AshDataTable.Test.Editing.Defaults do
  @moduledoc "A table without columns of its own, edited through a table-level action."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :notes, :string, public?: true
  end

  actions do
    defaults [:read, update: [:title]]
  end

  table do
    update_action :update
  end
end
