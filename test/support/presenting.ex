defmodule AshTable.Test.Presenting do
  @moduledoc """
  A resource for the tests of what a table makes of a column's `component`:
  one that only shows, one that only edits, one that does both, and columns
  without one. A viewer can never run `update`, and nobody but an admin
  sees `secret`.

  The actors of these tests are maps: `%{role: :admin}`.
  """
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

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
      component AshTable.Test.Cells.Shout
    end

    column :level do
      label "Rung"
      component AshTable.Test.Cells.Knob
    end

    column :note do
      component AshTable.Test.Cells.Both
    end

    column :grade do
      component AshTable.Test.Cells.Both
    end

    column :plain

    column :secret do
      component AshTable.Test.Cells.Both
    end

    column :loud_mood do
      component AshTable.Test.Cells.Both
    end

    action :relevel
    create_action :create
  end
end
