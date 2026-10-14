defmodule AshDataTable.Test.Presenting do
  @moduledoc """
  A resource for the tests of what a table makes of a column's `component`:
  one that only shows, one that only edits, one that does both, and columns
  without one. A viewer can never run `update`, and nobody but an admin
  sees `secret`.

  The actors of these tests are maps: `%{role: :admin}`.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :mood, :string, public?: true

    attribute :level, :integer do
      public? true
      constraints min: 0, max: 10
    end

    attribute :note, :string, public?: true

    attribute :grade, :atom do
      public? true
      constraints one_of: [:junior, :senior]
    end

    attribute :plain, :string, public?: true
    # admins only
    attribute :secret, :string, public?: true
  end

  calculations do
    calculate :loud_mood, :string, expr(mood <> "!"), public?: true
  end

  actions do
    defaults [:read]

    update :update do
      primary? true
      accept [:mood, :level, :note, :grade, :plain, :secret]
    end

    update :relevel do
      accept [:level, :plain, :mood]
      argument :note, :string
    end

    create :create do
      accept [:level, :note, :secret]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:update) do
      forbid_if actor_attribute_equals(:role, :viewer)
      authorize_if always()
    end

    policy action([:relevel, :create]) do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :secret do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    update_action :update

    column :mood do
      component AshDataTable.Test.Cells.Shout
    end

    column :level do
      label "Rung"
      component AshDataTable.Test.Cells.Knob
    end

    column :note do
      component AshDataTable.Test.Cells.Both
    end

    column :grade do
      component AshDataTable.Test.Cells.Both
    end

    column :plain

    column :secret do
      component AshDataTable.Test.Cells.Both
    end

    column :loud_mood do
      component AshDataTable.Test.Cells.Both
    end

    action :relevel
    create_action :create
  end
end

defmodule AshDataTable.Test.Presenting.Lists do
  @moduledoc "Arrays whose columns have a component: one that shows and edits, one that only edits."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :moods, {:array, :string}, public?: true

    attribute :grades, {:array, :atom} do
      public? true
      constraints items: [one_of: [:junior, :senior]]
    end
  end

  actions do
    defaults [:read, update: [:moods, :grades]]
  end

  table do
    update_action :update

    column :moods do
      component AshDataTable.Test.Cells.Both
    end

    column :grades do
      component AshDataTable.Test.Cells.Knob
    end

    action :update
  end
end

defmodule AshDataTable.Test.Presenting.Maps do
  @moduledoc "A value made of fields, and an array of them, whose columns have a component."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :place, AshDataTable.Test.Embedding.Place, public?: true
    attribute :places, {:array, AshDataTable.Test.Embedding.Place}, public?: true
  end

  actions do
    defaults [:read]

    update :update do
      require_atomic? false
      accept [:place, :places]
    end
  end

  table do
    update_action :update

    column :place do
      component AshDataTable.Test.Cells.Both
    end

    column :places do
      component AshDataTable.Test.Cells.Both
    end

    action :update
  end
end
