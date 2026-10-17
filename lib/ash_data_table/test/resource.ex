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
  @moduledoc """
  Who a `AshDataTable.Test.Resource` belongs to, and who helps with one: the
  picker of its reference cell and of its field of helpers shows them. Its
  primary key is a name, which is no id of the page as it is (`Ann Lee`):
  the rows of the picker say what they name a record by (`data-key`). Its
  `pin` is `sensitive?`.
  """
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
    column :pin
  end

  actions do
    defaults [:read, create: [:name, :pin, :holder_id], update: [:holder_id]]
  end

  attributes do
    attribute :name, :string,
      primary_key?: true,
      public?: true,
      allow_nil?: false,
      constraints: [length_count: :codepoints]

    attribute :pin, :string,
      public?: true,
      sensitive?: true,
      constraints: [length_count: :codepoints]
  end

  relationships do
    belongs_to :holder, AshDataTable.Test.Resource, public?: true
  end
end

defmodule AshDataTable.Test.Resource.Part do
  @moduledoc """
  A part of a `AshDataTable.Test.Resource`: the nested table under its rows.
  Its `secret` is `sensitive?`. Without a label field, its list of columns
  keeps one of them shown (`data-keeps-one`).
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Resource.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  multitenancy do
    strategy :context
  end

  table do
    update_action :update

    column :title
    column :secret
  end

  actions do
    defaults [:read, create: [:title, :secret, :resource_id], update: [:title]]
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string,
      public?: true,
      allow_nil?: false,
      constraints: [length_count: :codepoints]

    attribute :secret, :string,
      public?: true,
      sensitive?: true,
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
      place, and the label column, which stays in view as the grid scrolls
      sideways (`sticky_label? true`); `note`, two lines of text, asked
      about before a save;
    * `secret`, a `sensitive?` text of at most 30, which no rendered state
      may hold (`secret/0`), asked about before a save; `done`, a boolean; `size`, a number drawn by a
      component (`AshDataTable.Components.Progress`), summed in the footer;
      `tier`, one of two values, filtered by several of them;
    * `tags`, a list of short texts, edited value by value; `place`, a value
      made of fields (a map), `stops`, a list of them, and `kind`, a union,
      edited in the action panel;
    * `owner`, a reference cell with its picker
      (`AshDataTable.Test.Resource.Owner`), asked about before a choice
      changes it, and `parts`, the nested table
      under a row (`AshDataTable.Test.Resource.Part`);
    * the read action's argument `near`, in the argument line; it reads
      the same records whatever it holds;
    * row actions: one that takes a file (`stamp`), one whose panel holds
      the sensitive field and the tags (`rekey`), one whose panel holds the helpers
      chosen in the picker (`staff`), and one that asks first and runs on
      the selected rows (`destroy`); a table action that asks first
      (`greet`); the create action, whose panel holds every field; `place`
      asks before its panel saves a change.

  The records are read by name. A read in a tenant whose name begins with
  `broken` fails, for the table's error.
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
    sticky_label? true
    update_action :update
    create_action :create

    column :name

    column :note do
      max_lines 2
      confirm "Change the note?"
    end

    column :secret do
      confirm "Change the secret?"
    end

    column :done

    column :size do
      component AshDataTable.Components.Progress
      summary :sum
    end

    column :tier
    column :tags

    column :place do
      confirm "Change the place?"
    end

    column :stops
    column :kind

    column :owner do
      confirm "Change the owner?"
    end

    relationship :parts

    action :stamp
    action :rekey
    action :staff

    action :destroy do
      confirm "Delete it?"
    end

    action :greet do
      confirm "Greet everyone?"
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
      argument :near, :string, constraints: [length_count: :codepoints]
      prepare build(sort: [name: :asc])
      prepare AshDataTable.Test.Resource.Broken
      pagination offset?: true, required?: false, default_limit: 5, countable: true
    end

    create :create do
      primary? true

      accept [:name, :note, :secret, :done, :size, :tier, :tags, :place, :stops, :kind] ++
               [:owner_id]
    end

    update :update do
      primary? true
      require_atomic? false

      accept [:name, :note, :secret, :done, :size, :tier, :tags, :place, :stops, :kind] ++
               [:owner_id]
    end

    update :stamp do
      require_atomic? false
      accept [:note]
      argument :file, :file, allow_nil?: false
    end

    update :rekey do
      require_atomic? false
      accept [:secret, :tags]
    end

    update :staff do
      require_atomic? false
      argument :helpers, {:array, :string}
      change manage_relationship(:helpers, type: :append_and_remove)
    end

    action :greet, :string do
      run fn _input, _context -> {:ok, "Hello"} end
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
      constraints: [max_length: 30, length_count: :codepoints]

    attribute :done, :boolean, public?: true, allow_nil?: false, default: false
    attribute :size, :integer, public?: true, constraints: [min: 0, max: 100]
    attribute :tier, :atom, public?: true, constraints: [one_of: [:low, :high]]

    attribute :tags, {:array, :string},
      public?: true,
      constraints: [items: [max_length: 8, length_count: :codepoints]]

    attribute :place, :map,
      public?: true,
      constraints: [
        fields: [
          city: [type: :string, constraints: [length_count: :codepoints]],
          zip: [type: :string, constraints: [length_count: :codepoints]]
        ]
      ]

    attribute :stops, {:array, :map},
      public?: true,
      constraints: [
        items: [
          fields: [
            city: [type: :string, constraints: [length_count: :codepoints]]
          ]
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
    belongs_to :owner, AshDataTable.Test.Resource.Owner,
      public?: true,
      attribute_type: :string,
      destination_attribute: :name

    has_many :parts, AshDataTable.Test.Resource.Part, public?: true

    has_many :helpers, AshDataTable.Test.Resource.Owner,
      public?: true,
      destination_attribute: :holder_id
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
