defmodule Demo.Support.Live do
  @moduledoc """
  A domain for the tests of live updates, where the demo's own tables do
  not have the case: a record that stops being a person's to read, a
  sensitive column, a page mounted without authorization or without live
  updates, a table that does not follow, and a picker over a resource that
  announces its changes. Its resources exist for the tests only and keep
  their records in memory.

  The actors of these tests are maps: `%{role: :admin}`.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshTable.Domain]

  table do
    actor_assign :reader
    pub_sub Demo.PubSub
  end

  resources do
    resource Demo.Support.Live.Bulletin
    resource Demo.Support.Live.Reply
    resource Demo.Support.Live.Stamp
    resource Demo.Support.Live.Pin
  end
end

defmodule Demo.Support.Live.Bulletin do
  @moduledoc """
  A bulletin. An admin reads every one, anybody else those that are not
  hidden. Its code is sensitive, and its draft an admin's alone. It
  announces its changes; its table `:quiet` does not follow them.
  """
  use Ash.Resource,
    domain: Demo.Support.Live,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  field_policies do
    field_policy :draft do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(title == "shared")
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    live? true
    label_field :title
    update_action :update
    create_action :create

    column :title
    column :hidden?
    column :code
    column :draft

    relationship :replies

    action :destroy do
      confirm false
    end

    action :retitle
  end

  tables do
    table :quiet do
      live? false
      column :title
    end
  end

  actions do
    defaults [:destroy, create: [:title, :hidden?, :code, :draft]]

    read :read do
      primary? true
      pagination offset?: true, default_limit: 5, countable: true, required?: false
      prepare build(sort: [title: :asc])
    end

    update :update do
      primary? true
      accept [:title, :hidden?, :code, :draft]
    end

    update :retitle do
      accept [:title]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(hidden? == false)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true, allow_nil?: false
    attribute :hidden?, :boolean, public?: true, allow_nil?: false, default: false
    attribute :code, :string, public?: true, sensitive?: true
    attribute :draft, :string, public?: true
  end

  relationships do
    has_many :replies, Demo.Support.Live.Reply, public?: true
  end
end

defmodule Demo.Support.Live.Reply do
  @moduledoc """
  A reply to a bulletin, which a person chooses in the picker. It announces
  its changes too.
  """
  use Ash.Resource,
    domain: Demo.Support.Live,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  table do
    live? true
    update_action :update

    column :body
    column :bulletin
  end

  actions do
    defaults [:destroy, create: [:body, :bulletin_id]]

    read :read do
      primary? true
      pagination offset?: true, default_limit: 5, countable: true, required?: false
      prepare build(sort: [body: :asc])
    end

    update :update do
      primary? true
      accept [:body, :bulletin_id]
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true, allow_nil?: false
  end

  relationships do
    belongs_to :bulletin, Demo.Support.Live.Bulletin do
      public? true
      attribute_public? true
      allow_nil? true
    end
  end
end

defmodule Demo.Support.Live.Stamp do
  @moduledoc "A resource of the same domain that announces nothing."
  use Ash.Resource,
    domain: Demo.Support.Live,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  actions do
    defaults [:read, :destroy, create: [:mark], update: [:mark]]
  end

  attributes do
    uuid_primary_key :id
    attribute :mark, :string, public?: true
  end
end

defmodule Demo.Support.Live.Pin do
  @moduledoc """
  A pin on a board: its primary key is the board and the slot together. It
  announces its changes.
  """
  use Ash.Resource,
    domain: Demo.Support.Live,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  table do
    live? true
    update_action :update

    column :board
    column :slot
    column :note
  end

  actions do
    defaults [:destroy, create: [:board, :slot, :note]]

    read :read do
      primary? true
      prepare build(sort: [board: :asc, slot: :asc])
    end

    update :update do
      primary? true
      accept [:note]
    end
  end

  attributes do
    attribute :board, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :slot, :integer, primary_key?: true, allow_nil?: false, public?: true
    attribute :note, :string, public?: true
  end
end
