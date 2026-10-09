defmodule Demo.Support.Ran do
  @moduledoc """
  Which read actions were prepared while a test looked, and what for: to
  `:read` records, or to `:load` something onto records that are already
  read. An action is prepared when it is run, and when Ash is asked whether
  somebody may run it (`Ash.can/3`). A preparation of the read actions of
  `Demo.Support.Vault`, public and private, so that a test can say that a
  private one was never reached.

  Ash's telemetry of read actions leaves out what `Ash.load/3` reads; this
  does not.
  """
  use Ash.Resource.Preparation

  @doc "Starts to look, for as long as the calling process lives."
  def watch, do: :ets.new(__MODULE__, [:named_table, :public, :set])

  @doc "Forgets what was seen so far."
  def forget, do: :ets.delete_all_objects(__MODULE__)

  @doc "What was prepared since, each once: `{resource, action, :read | :load}`."
  def actions, do: __MODULE__ |> :ets.tab2list() |> Enum.map(&elem(&1, 0)) |> Enum.sort()

  @impl true
  def prepare(query, _opts, _context) do
    # Ash marks the query of an `Ash.load/3`
    what = if query.context[:query_for] == :load, do: :load, else: :read

    if :ets.whereis(__MODULE__) != :undefined,
      do: :ets.insert(__MODULE__, {{query.resource, query.action.name, what}})

    query
  end
end

defmodule Demo.Support.Vault do
  @moduledoc """
  A domain for the tests of the rule that every action a table runs is
  `public?`. Its resources exist for the tests only and read the demo's own
  tables in Postgres. Each has a private read action that the policies let
  everybody run, as Ash's documentation has it for a private action
  (`bypass private_action?() do authorize_if always() end`), and that
  returns what the public one hides.

  The tables of the resources listed here are sound: none runs a private
  action. The tables that would are written in the test
  (`test/demo_web/tables/private_action_test.exs`), where what the compiler
  says about them is taken as a result; they are of this domain without
  being listed in it.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshTable.Domain]

  resources do
    allow_unregistered? true

    resource Demo.Support.Vault.Dossier
    resource Demo.Support.Vault.Note
    resource Demo.Support.Vault.Folder
    resource Demo.Support.Vault.Binder
    resource Demo.Support.Vault.Mark
    resource Demo.Support.Vault.Link
  end
end

defmodule Demo.Support.Vault.Dossier do
  @moduledoc """
  A project under another name. Its primary read action is private and
  returns every dossier; its table names the public one, which returns the
  open dossiers only (those described as "open").

  The table only reads: Ash loads what a create, an update or a destroy
  returns through the primary read action, so a table that changed dossiers
  would run the private one. Its rows offer the default set of
  relationships: the notes, and not `all_notes`, whose read action is
  private.
  """
  use Ash.Resource,
    domain: Demo.Support.Vault,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  postgres do
    table "projects"
    repo Demo.Repo
    migrate? false
  end

  table do
    read_action :open
    label_field :name

    column :name
    column :description
    column :shouted
    column :note_count
  end

  actions do
    # for the code of the application: every dossier, sealed or not
    read :read do
      primary? true
      public? false
      prepare Demo.Support.Ran
    end

    read :open do
      prepare Demo.Support.Ran
    end
  end

  policies do
    bypass private_action?() do
      authorize_if always()
    end

    policy action(:open) do
      authorize_if expr(description == "open")
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :description, :string, public?: true
    # what an organization's dossiers are found by
    attribute :organization_id, :uuid
  end

  relationships do
    has_many :notes, Demo.Support.Vault.Note do
      destination_attribute :project_id
      public? true
    end

    has_many :all_notes, Demo.Support.Vault.Note do
      destination_attribute :project_id
      read_action :internal
      public? true
    end
  end

  calculations do
    calculate :shouted, :string, expr(name <> "!"), public?: true
  end

  aggregates do
    count :note_count, :notes, public?: true
  end
end

defmodule Demo.Support.Vault.Note do
  @moduledoc """
  A task under another name. Its primary read action is public and hides
  the sealed notes (the billable tasks); a private one returns them all.

  Its reference cell says which action reads the dossier: the relationship
  names the public one, where Ash would otherwise load through the
  dossiers' private primary read action.

  Its rows offer the default set of relationships: the dossier, the binder,
  and the marks, which Ash joins through the links' public read action; not
  `all_marks`, which it joins through their private one. A private destroy
  action is there for the code of the application.
  """
  use Ash.Resource,
    domain: Demo.Support.Vault,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  postgres do
    table "tasks"
    repo Demo.Repo
    migrate? false
  end

  table do
    label_field :title
    # "New note" under a dossier; never run by a test, only opened
    create_action :create

    column :title
    column :dossier
  end

  actions do
    create :create do
      accept [:title, :project_id]
    end

    read :read do
      primary? true
      prepare Demo.Support.Ran
    end

    # for the code of the application: every note, sealed or not
    read :internal do
      public? false
      prepare Demo.Support.Ran
    end

    # and nobody's to run from a table
    destroy :shred do
      public? false
    end
  end

  policies do
    bypass private_action?() do
      authorize_if always()
    end

    policy action(:read) do
      authorize_if expr(sealed == false)
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true

    attribute :sealed, :boolean do
      source :billable
      public? true
    end
  end

  relationships do
    belongs_to :dossier, Demo.Support.Vault.Dossier do
      source_attribute :project_id
      read_action :open
      public? true
      attribute_public? true
      attribute_writable? true
    end

    # the same project as a binder, through another public read action than
    # the one the binders' table names: every binder, open or not
    belongs_to :binder, Demo.Support.Vault.Binder do
      source_attribute :project_id
      define_attribute? false
      read_action :every
      public? true
    end

    # for the code of the application: every link
    has_many :links, Demo.Support.Vault.Link, destination_attribute: :task_id

    has_many :open_links, Demo.Support.Vault.Link do
      destination_attribute :task_id
      read_action :open
    end

    many_to_many :marks, Demo.Support.Vault.Mark do
      through Demo.Support.Vault.Link
      join_relationship :open_links
      source_attribute_on_join_resource :task_id
      destination_attribute_on_join_resource :label_id
      public? true
    end

    many_to_many :all_marks, Demo.Support.Vault.Mark do
      through Demo.Support.Vault.Link
      join_relationship :links
      source_attribute_on_join_resource :task_id
      destination_attribute_on_join_resource :label_id
      public? true
    end
  end
end

defmodule Demo.Support.Vault.Folder do
  @moduledoc """
  A project under yet another name, whose table reads through another
  action than the primary one, and edits. Both are public: the primary read
  action returns the open folders (those described as "open"), the table's
  returns every folder.

  A table reads the record of a row again before it changes it: through
  its own read action, so that a row it shows is a row it can change. What
  the update returns is loaded through the primary read action, by Ash and
  by the table alike.
  """
  use Ash.Resource,
    domain: Demo.Support.Vault,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  postgres do
    table "projects"
    repo Demo.Repo
    migrate? false
  end

  table do
    read_action :every
    update_action :update

    column :name
    column :description
    column :shouted
  end

  actions do
    # Ash runs an update as a statement over a read action of the resource:
    # the primary one, unless the action names another. The primary one
    # would not find a folder that is not open.
    update :update do
      accept [:name]
      atomic_upgrade_with :every
    end

    read :read do
      primary? true
      filter expr(description == "open")
      prepare Demo.Support.Ran
    end

    read :every do
      prepare Demo.Support.Ran
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :description, :string, public?: true
  end

  calculations do
    calculate :shouted, :string, expr(name <> "!"), public?: true
  end
end

defmodule Demo.Support.Vault.Binder do
  @moduledoc """
  A project under a third name, with nothing private. Its table shows the
  open binders (those described as "open"); another public read action
  returns every binder, and the notes' relationship to their binder names
  that one. A row a nested table shows through it is not a row the binders'
  own table would show.
  """
  use Ash.Resource,
    domain: Demo.Support.Vault,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  postgres do
    table "projects"
    repo Demo.Repo
    migrate? false
  end

  table do
    read_action :open
    label_field :name

    column :name
  end

  actions do
    defaults [:read]

    read :open do
      filter expr(description == "open")
    end

    read :every
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :description, :string, public?: true
  end

  relationships do
    has_many :notes, Demo.Support.Vault.Note do
      destination_attribute :project_id
      public? true
    end
  end
end

defmodule Demo.Support.Vault.Mark do
  @moduledoc "A label under another name, with nothing private."
  use Ash.Resource,
    domain: Demo.Support.Vault,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTable.Resource]

  postgres do
    table "labels"
    repo Demo.Repo
    migrate? false
  end

  table do
    label_field :name

    column :name
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end
end

defmodule Demo.Support.Vault.Link do
  @moduledoc """
  What joins a note and a mark: a task's label under another name. Its
  primary read action is private and returns every link; the public one
  hides the withheld links (those with a note on them). No table: Ash reads
  a join resource on the way from a note to its marks.
  """
  use Ash.Resource,
    domain: Demo.Support.Vault,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

  postgres do
    table "task_labels"
    repo Demo.Repo
    migrate? false
  end

  actions do
    read :read do
      primary? true
      public? false
      prepare Demo.Support.Ran
    end

    read :open do
      prepare Demo.Support.Ran
    end
  end

  policies do
    bypass private_action?() do
      authorize_if always()
    end

    policy action(:open) do
      authorize_if expr(is_nil(note))
    end
  end

  attributes do
    attribute :task_id, :uuid, primary_key?: true, allow_nil?: false
    attribute :label_id, :uuid, primary_key?: true, allow_nil?: false
    attribute :note, :string
  end
end
