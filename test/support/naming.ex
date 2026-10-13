defmodule AshTable.Test.Naming do
  @moduledoc """
  Resources with several tables: a default table and named ones, a
  relationship that names which of its destination's tables it nests, and
  tables that are declared in a file of their own (Spark fragments).

  The actors of these tests are maps: `%{role: :admin}`.
  """
end

defmodule AshTable.Test.Naming.Author do
  @moduledoc "A destination of a reference column: a default table only."
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read, create: [:name]]
  end

  table do
    label_field :name
  end
end

defmodule AshTable.Test.Naming.Comment do
  @moduledoc """
  A default table and two named ones, each with settings of its own.

    * the default table edits, creates and deletes, and names the record;
    * `:compact` reads through another action, shows two columns, changes
      nothing, never expands and says so when its read is refused;
    * `:plain` declares nothing at all.
  """
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true
    attribute :rating, :integer, public?: true
    attribute :post_id, :uuid, public?: true
    attribute :author_id, :uuid, public?: true
  end

  relationships do
    belongs_to :post, AshTable.Test.Naming.Post do
      define_attribute? false
      public? true
    end

    belongs_to :author, AshTable.Test.Naming.Author do
      define_attribute? false
      public? true
    end
  end

  actions do
    defaults [:destroy, create: [:body, :rating, :post_id, :author_id]]

    read :read do
      primary? true
      pagination offset?: true, keyset?: true, required?: false, default_limit: 5
    end

    read :recent do
      pagination keyset?: true, required?: false, default_limit: 2
      argument :search, :string
    end

    update :update do
      accept [:body, :rating, :author_id]
    end

    update :rate do
      accept [:rating]
    end

    action :import, :integer do
      argument :file, :file, allow_nil?: false
      run fn _input, _context -> {:ok, 0} end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :reader)
    end

    policy action_type([:create, :update, :destroy, :action]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  table do
    label_field :body
    update_action :update
    create_action :create
    max_depth 2

    column :body
    column :rating
    column :author

    action :destroy do
      confirm "Delete this comment?"
    end

    action :import

    upload :file do
      accept ~w(.csv)
      max_file_size 1_000
    end
  end

  tables do
    table :compact do
      read_action :recent
      max_depth 0
      on_forbidden :message

      column :body do
        label "Text"
      end

      column :rating

      argument :search do
        label "Find"
      end
    end

    table :plain
  end
end

defmodule AshTable.Test.Naming.Post do
  @moduledoc """
  A resource whose tables nest different tables of `Comment`: the default
  table nests the default one, `:board` the compact one, and `:both` each of
  them, through two relationships.
  """
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :state, :atom, public?: true, constraints: [one_of: [:draft, :live]]
  end

  relationships do
    has_many :comments, AshTable.Test.Naming.Comment do
      destination_attribute :post_id
      public? true
    end

    has_many :remarks, AshTable.Test.Naming.Comment do
      destination_attribute :post_id
      public? true
    end
  end

  actions do
    defaults [:read, create: [:title, :state], update: [:title, :state]]
  end

  table do
    label_field :title
    column :title
    relationship :comments
  end

  tables do
    table :board do
      update_action :update

      column :state
      column :title

      relationship :comments do
        table :compact
        label "Short comments"
      end
    end

    table :both do
      relationship :comments do
        table :default
      end

      relationship :remarks do
        table :compact
      end
    end
  end
end

# A table in a file of its own is a Spark fragment of the resource. Here they
# share the file with the resource; what counts is that each is a module.

defmodule AshTable.Test.Naming.Ticket.BoardTable do
  @moduledoc "One named table of `Ticket`."
  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshTable.Resource]

  tables do
    table :board do
      update_action :update

      column :title
      column :state

      relationship :notes do
        table :compact
      end
    end
  end
end

defmodule AshTable.Test.Naming.Ticket.ListTable do
  @moduledoc "Another named table of `Ticket`, from a second fragment."
  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshTable.Resource]

  tables do
    table :list do
      max_depth 0
      column :title
    end
  end
end

defmodule AshTable.Test.Naming.Ticket do
  @moduledoc """
  The default table in the resource, two named tables in a fragment each,
  and a third named table in the resource beside them.
  """
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource],
    fragments: [
      AshTable.Test.Naming.Ticket.BoardTable,
      AshTable.Test.Naming.Ticket.ListTable
    ]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :state, :atom, public?: true, constraints: [one_of: [:open, :done]]
  end

  relationships do
    has_many :notes, AshTable.Test.Naming.Note do
      destination_attribute :ticket_id
      public? true
    end
  end

  actions do
    defaults [:read, update: [:title, :state]]
  end

  table do
    label_field :title
    column :title
  end

  tables do
    table :own do
      column :state
    end
  end
end

defmodule AshTable.Test.Naming.Note.Table do
  @moduledoc "The default table of `Note`, `label_field` and all, in a fragment."
  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshTable.Resource]

  table do
    label_field :text
    read_action :read
    max_depth 1

    column :text
    column :ticket
  end
end

defmodule AshTable.Test.Naming.Note do
  @moduledoc "The default table in a fragment, a named table in the resource."
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource],
    fragments: [AshTable.Test.Naming.Note.Table]

  attributes do
    uuid_primary_key :id
    attribute :text, :string, public?: true
    attribute :ticket_id, :uuid, public?: true
  end

  relationships do
    belongs_to :ticket, AshTable.Test.Naming.Ticket do
      define_attribute? false
      public? true
    end
  end

  actions do
    defaults [:read, create: [:text, :ticket_id]]
  end

  tables do
    table :compact do
      column :text
    end
  end
end
