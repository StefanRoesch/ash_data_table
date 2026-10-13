defmodule AshTable.Test.Filtering.Shout do
  @moduledoc "A calculation computed in Elixir: it has no expression a data layer could filter by."
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:name]

  @impl true
  def calculate(records, _opts, _context), do: Enum.map(records, &String.upcase(&1.name))
end

defmodule AshTable.Test.Filtering.Note do
  @moduledoc false
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :subject, AshTable.Test.Filtering, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTable.Test.Filtering do
  @moduledoc """
  A resource for the tests of what a table can filter by: a required and a
  nil-able field of every cell type, fields the resource does not allow to be
  filtered, calculations and aggregates.
  """
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :nickname, :string, public?: true
    attribute :email, :ci_string, public?: true, allow_nil?: false
    attribute :slug, AshTable.Test.Slug, public?: true

    attribute :visits, :integer, public?: true, allow_nil?: false
    attribute :weight, :float, public?: true
    attribute :balance, :decimal, public?: true
    attribute :percentage, AshTable.Test.Percentage, public?: true, allow_nil?: false

    attribute :active, :boolean, public?: true, allow_nil?: false
    attribute :verified, :boolean, public?: true

    attribute :born_on, :date, public?: true, allow_nil?: false
    attribute :left_on, :date, public?: true

    attribute :seen_at, :utc_datetime_usec, public?: true, allow_nil?: false
    attribute :archived_at, :naive_datetime, public?: true

    attribute :status, AshTable.Test.Status, public?: true, allow_nil?: false
    attribute :size, :atom, public?: true, constraints: [one_of: [:small, :large]]

    attribute :tags, {:array, :string}, public?: true
    attribute :settings, :map, public?: true

    attribute :secret, :string, public?: true, filterable?: false
    attribute :remark, :string, public?: true
  end

  relationships do
    has_many :notes, AshTable.Test.Filtering.Note, destination_attribute: :subject_id
  end

  calculations do
    calculate :greeting, :string, expr("Hello " <> name), public?: true

    calculate :adult?, :boolean, expr(visits >= 18) do
      public? true
      allow_nil? false
    end

    calculate :whisper, :string, expr(name <> "…"), public?: true, filterable?: false
    calculate :shout, :string, AshTable.Test.Filtering.Shout, public?: true
  end

  aggregates do
    count :note_count, :notes, public?: true
    max :last_note_at, :notes, :inserted_at, public?: true
    first :first_note, :notes, :body, public?: true
    count :hidden_count, :notes, public?: true, filterable?: false
  end

  actions do
    defaults [:read]
  end

  table do
    column :id
    column :name
    column :nickname
    column :email
    column :slug
    column :visits
    column :weight
    column :balance
    column :percentage
    column :active
    column :verified
    column :born_on
    column :left_on
    column :seen_at
    column :archived_at
    column :status
    column :size
    column :tags
    column :settings
    column :secret

    column :remark do
      filterable? false
    end

    column :greeting
    column :adult?
    column :whisper
    column :shout
    column :note_count
    column :last_note_at
    column :first_note
    column :hidden_count
  end
end

defmodule AshTable.Test.Filtering.SimpleEquality do
  @moduledoc """
  A field that can only be filtered by equality. It is a resource of its own
  because `Ash.Info.Manifest.generate/1` (ash 3.34.4) raises on a field
  declared `filterable?: :simple_equality`, and the model tests compare
  `AshTable.Test.Filtering` with the manifest.
  """
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :code, :string, public?: true, filterable?: :simple_equality
    attribute :rank, :integer, public?: true, filterable?: :simple_equality
    attribute :status, AshTable.Test.Status, public?: true, filterable?: :simple_equality
  end

  actions do
    defaults [:read]
  end
end
