defmodule AshDataTable.Test.Referencing do
  @moduledoc """
  Resources for the tests of reference cells: columns that name a belongs-to
  relationship and show the related record's label.

  The actors of these tests are maps: `%{role: :admin}`.
  """
end

defmodule AshDataTable.Test.Referencing.Person do
  @moduledoc "A destination everybody reads, called by its name."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :email, :string, public?: true
  end

  actions do
    defaults [:read]
  end

  table do
    label_field :name
  end
end

defmodule AshDataTable.Test.Referencing.Rank do
  @moduledoc "A destination called by an enum, whose labels a reference cell shows."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id

    attribute :grade, :atom do
      constraints one_of: [:junior, :senior]
      public? true
    end
  end

  actions do
    defaults [:read]
  end

  table do
    label_field :grade
  end
end

defmodule AshDataTable.Test.Referencing.Vault do
  @moduledoc "A destination only an admin may ever read: its read is refused outright."
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
  end

  policies do
    policy action_type(:read) do
      access_type :strict
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  table do
    label_field :code
  end
end

defmodule AshDataTable.Test.Referencing.Agent do
  @moduledoc """
  A destination everybody reads, whose label only an admin ever sees, and
  whose records are read through an action of their own by one relationship.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :alias, :string, public?: true
  end

  actions do
    defaults [:read]

    read :active
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :alias do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  table do
    label_field :alias
  end
end

defmodule AshDataTable.Test.Referencing.Letter do
  @moduledoc "A table with reference columns beside a column a person edits."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :subject, :string, public?: true
  end

  relationships do
    belongs_to :sender, AshDataTable.Test.Referencing.Person, public?: true
    belongs_to :rank, AshDataTable.Test.Referencing.Rank, public?: true
    belongs_to :vault, AshDataTable.Test.Referencing.Vault, public?: true

    belongs_to :agent, AshDataTable.Test.Referencing.Agent do
      read_action :active
      public? true
    end
  end

  actions do
    defaults [:read, update: [:subject]]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  table do
    update_action :update

    column :subject

    column :sender do
      label "From"
    end

    column :rank
    column :vault
    column :agent
  end
end

defmodule AshDataTable.Test.Referencing.Ledger do
  @moduledoc "A destination with a label and without a primary read action."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    read :list
  end

  table do
    read_action :list
    label_field :name
  end
end
