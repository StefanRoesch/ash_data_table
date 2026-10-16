defmodule AshDataTable.Test.Resource.Domain do
  @moduledoc """
  The domain of `AshDataTable.Test.Resource`: test support for
  `AshDataTable.KitCase`, shipped so that a kit's own tests have a table of
  every part to draw. Without authorization; nothing of it is meant for a
  page of an application.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

  table do
    authorize? false
  end

  resources do
    resource AshDataTable.Test.Resource
    resource AshDataTable.Test.Resource.Owner
    resource AshDataTable.Test.Resource.Part
  end
end

defmodule AshDataTable.Test.Resource.Owner do
  @moduledoc "Who a `AshDataTable.Test.Resource` belongs to: its reference cell's picker shows them."
  use Ash.Resource,
    domain: AshDataTable.Test.Resource.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  multitenancy do
    strategy :context
  end

  table do
    label_field :name

    column :name
  end

  actions do
    defaults [:read, create: [:name]]
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string,
      public?: true,
      allow_nil?: false,
      constraints: [length_count: :codepoints]
  end
end

defmodule AshDataTable.Test.Resource.Part do
  @moduledoc "A part of a `AshDataTable.Test.Resource`: the nested table under its rows."
  use Ash.Resource,
    domain: AshDataTable.Test.Resource.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  multitenancy do
    strategy :context
  end

  table do
    label_field :title
    update_action :update

    column :title
  end

  actions do
    defaults [:read, create: [:title, :resource_id], update: [:title]]
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string,
      public?: true,
      allow_nil?: false,
      constraints: [length_count: :codepoints]
  end

  relationships do
    belongs_to :resource, AshDataTable.Test.Resource, public?: true
  end
end

defmodule AshDataTable.Test.Resource do
  @moduledoc """
  A table of every part, for `AshDataTable.KitCase`: a resource kept in
  memory (`Ash.DataLayer.Ets`, a table of its own per tenant) whose table
  has a column of each kind a kit draws, and shipped in the library so
  that a kit's own tests can draw it.

    * `name`, text that cannot be empty and is at most 40 long, edited in
      place; `note`, two lines of text, asked about before a save;
    * `secret`, a `sensitive?` text, which no rendered state may hold
      (`secret/0`); `done`, a boolean; `size`, a number drawn by a
      component (`AshDataTable.Components.Progress`);
    * `place`, a value made of fields (a map), `kind`, a union, both edited
      in the action panel;
    * `owner`, a reference cell with its picker (`AshDataTable.Test.Resource.Owner`),
      and `parts`, the nested table under a row (`AshDataTable.Test.Resource.Part`);
    * a row action that takes a file (`stamp`), one that asks first and
      runs on the selected rows (`destroy`), and the create action.

  A read in a tenant whose name begins with `broken` fails, for the
  table's error.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Resource.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  @secret "kit-case-secret-4f1d"

  @doc "The value of `secret` on every record `AshDataTable.KitCase` makes."
  def secret, do: @secret

  multitenancy do
    strategy :context
  end

  table do
    label_field :name
    update_action :update
    create_action :create

    column :name

    column :note do
      max_lines 2
      confirm "Change the note?"
    end

    column :secret
    column :done

    column :size do
      component AshDataTable.Components.Progress
    end

    column :place
    column :kind
    column :owner

    relationship :parts

    action :stamp

    action :destroy do
      confirm "Delete it?"
    end

    upload :file do
      accept ~w(.txt text/plain)
      max_file_size 1_000
    end
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      prepare AshDataTable.Test.Resource.Broken
      pagination offset?: true, required?: false, default_limit: 5, countable: true
    end

    create :create do
      primary? true
      accept [:name, :note, :secret, :done, :size, :place, :kind, :owner_id]
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:name, :note, :secret, :done, :size, :place, :kind, :owner_id]
    end

    update :stamp do
      require_atomic? false
      accept [:note]
      argument :file, :file, allow_nil?: false
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string,
      public?: true,
      allow_nil?: false,
      constraints: [max_length: 40, length_count: :codepoints]

    attribute :note, :string, public?: true, constraints: [length_count: :codepoints]

    attribute :secret, :string,
      public?: true,
      sensitive?: true,
      constraints: [length_count: :codepoints]

    attribute :done, :boolean, public?: true, allow_nil?: false, default: false
    attribute :size, :integer, public?: true, constraints: [min: 0, max: 100]

    attribute :place, :map,
      public?: true,
      constraints: [
        fields: [
          city: [type: :string, constraints: [length_count: :codepoints]],
          zip: [type: :string, constraints: [length_count: :codepoints]]
        ]
      ]

    attribute :kind, :union,
      public?: true,
      constraints: [
        types: [
          count: [type: :integer],
          word: [type: :string, constraints: [length_count: :codepoints]]
        ]
      ]
  end

  relationships do
    belongs_to :owner, AshDataTable.Test.Resource.Owner, public?: true
    has_many :parts, AshDataTable.Test.Resource.Part, public?: true
  end
end

defmodule AshDataTable.Test.Resource.Broken do
  @moduledoc false
  # A read in a tenant whose name begins with `broken` fails.
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    if is_binary(query.tenant) and String.starts_with?(query.tenant, "broken"),
      do: Ash.Query.add_error(query, "the test resource cannot be read in this tenant"),
      else: query
  end
end
