defmodule AshDataTable.Test.Private do
  @moduledoc """
  Resources for the tests of the rule that every action a table runs is
  `public?`: destinations with private actions, each exempted from the
  policies in the way Ash documents for a private action
  (`bypass private_action?() do authorize_if always() end`).

  The tables of these resources are sound: none of them runs a private
  action. The tables that would are written in the tests.
  """
end

defmodule AshDataTable.Test.Private.Paper do
  @moduledoc """
  A destination whose primary read is public and hides the sealed papers,
  beside private actions of every type: a read that returns the sealed ones
  too, an update, a destroy and a create.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :sealed, :boolean, public?: true, default: false
    attribute :folder_id, :uuid, public?: true
  end

  actions do
    defaults [:read, create: [:title, :sealed, :folder_id], update: [:title]]

    # for the code of the application: everything, sealed or not
    read :internal do
      public? false
    end

    update :redact do
      public? false
      accept [:title]
    end

    destroy :shred do
      public? false
    end

    create :import do
      public? false
      accept [:title, :sealed, :folder_id]
    end
  end

  policies do
    # the idiom of Ash's documentation for a private action
    bypass private_action?() do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(sealed == false)
    end

    policy action_type([:create, :update]) do
      authorize_if always()
    end
  end

  table do
    label_field :title
  end
end

defmodule AshDataTable.Test.Private.Minute do
  @moduledoc """
  A destination whose primary read is private, and whose table names a
  public read action: the table of the minutes is sound, and so is a nested
  table of them, which runs the table's read action. What Ash loads through
  the primary read is another matter: a reference cell, an aggregate.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :sealed, :boolean, public?: true, default: false
  end

  relationships do
    # says which action reads the folder: its primary read is private
    belongs_to :folder, AshDataTable.Test.Private.Folder do
      read_action :open
      public? true
      attribute_public? true
      attribute_writable? true
    end
  end

  calculations do
    calculate :shouted, :string, expr(title <> "!"), public?: true
  end

  actions do
    defaults create: [:title, :sealed, :folder_id], update: [:title]

    # for the code of the application: everything, sealed or not
    read :read do
      primary? true
      public? false
    end

    read :open

    # the minutes a folder lists: another public read action than the table's
    read :listed
  end

  policies do
    bypass private_action?() do
      authorize_if always()
    end

    policy action([:open, :listed]) do
      authorize_if expr(sealed == false)
    end

    policy action_type([:create, :update]) do
      authorize_if always()
    end
  end

  # read-only: Ash loads what a create, an update or a destroy returns
  # through the primary read action, so a table that changes records needs
  # that one to be public
  table do
    read_action :open
    label_field :title

    column :title
    column :shouted
    column :folder
  end
end

defmodule AshDataTable.Test.Private.Folder do
  @moduledoc """
  A folder of papers and minutes whose primary read is private, with a
  table that names a public read action. Its rows offer the default set of
  relationships: those whose nested table runs a public read action, and is
  reached through one.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :locked, :boolean, public?: true, default: false
  end

  relationships do
    has_many :papers, AshDataTable.Test.Private.Paper, public?: true

    # everything, sealed or not: for the code of the application
    has_many :all_papers, AshDataTable.Test.Private.Paper do
      read_action :internal
      public? true
    end

    has_many :minutes, AshDataTable.Test.Private.Minute, public?: true

    has_many :all_minutes, AshDataTable.Test.Private.Minute do
      read_action :read
      public? true
    end

    # says which action reads them, and names a public one
    has_many :listed_minutes, AshDataTable.Test.Private.Minute do
      read_action :listed
      public? true
    end

    # for the code of the application
    has_many :taggings, AshDataTable.Test.Private.Tagging

    has_many :open_taggings, AshDataTable.Test.Private.Tagging do
      read_action :open
    end

    # joined through the taggings' private primary read action
    many_to_many :tags, AshDataTable.Test.Private.Tag do
      through AshDataTable.Test.Private.Tagging
      join_relationship :taggings
      source_attribute_on_join_resource :folder_id
      destination_attribute_on_join_resource :tag_id
      public? true
    end

    # and through their public one
    many_to_many :open_tags, AshDataTable.Test.Private.Tag do
      through AshDataTable.Test.Private.Tagging
      join_relationship :open_taggings
      source_attribute_on_join_resource :folder_id
      destination_attribute_on_join_resource :tag_id
      public? true
    end
  end

  actions do
    defaults create: [:name, :locked], update: [:name]

    read :read do
      primary? true
      public? false
    end

    read :open
  end

  policies do
    bypass private_action?() do
      authorize_if always()
    end

    policy action(:open) do
      authorize_if expr(locked == false)
    end

    policy action_type([:create, :update]) do
      authorize_if always()
    end
  end

  table do
    read_action :open
    label_field :name
  end
end

defmodule AshDataTable.Test.Private.Tag do
  @moduledoc "A tag of folders: nothing about it is private."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

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

defmodule AshDataTable.Test.Private.Tagging do
  @moduledoc """
  What joins a folder and a tag. Its primary read is private and returns
  every tagging; a public one hides the withheld ones. No table: a join
  resource is read by Ash on the way from a folder to its tags.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    attribute :folder_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :tag_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :withheld, :boolean, public?: true, default: false
  end

  actions do
    defaults create: [:folder_id, :tag_id, :withheld]

    read :read do
      primary? true
      public? false
    end

    read :open
  end

  policies do
    bypass private_action?() do
      authorize_if always()
    end

    policy action(:open) do
      authorize_if expr(withheld == false)
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end
end

defmodule AshDataTable.Test.Private.FolderOfPapers do
  @moduledoc """
  A folder that counts its papers through their private read action, for
  the code of the application: the aggregate is no column of anything.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
  end

  relationships do
    has_many :papers, AshDataTable.Test.Private.Paper, destination_attribute: :folder_id
  end

  aggregates do
    count :every_paper, :papers do
      read_action :internal
    end
  end

  actions do
    defaults [:read]

    read :open
  end
end
