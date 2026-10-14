defmodule AshDataTable.Test.Relating do
  @moduledoc """
  Resources for the tests of what a table offers below a row: one
  relationship of every kind, to destinations with and without a table.

  The actors of these tests are maps: `%{role: :admin}`.
  """
end

defmodule AshDataTable.Test.Relating.Shelf do
  @moduledoc "A destination without a table: it does not list the extension."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshDataTable.Test.Relating.Tag do
  @moduledoc "A destination whose read is not paginated, and whose rows never expand."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    many_to_many :books, AshDataTable.Test.Relating.Book do
      through AshDataTable.Test.Relating.BookTag
      source_attribute_on_join_resource :tag_id
      destination_attribute_on_join_resource :book_id
      public? true
    end
  end

  actions do
    # declared, and so without pagination
    read :read do
      primary? true
    end
  end

  table do
    max_depth 0
  end
end

defmodule AshDataTable.Test.Relating.BookTag do
  @moduledoc false
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  relationships do
    belongs_to :book, AshDataTable.Test.Relating.Book, primary_key?: true, allow_nil?: false
    belongs_to :tag, AshDataTable.Test.Relating.Tag, primary_key?: true, allow_nil?: false
  end

  actions do
    defaults [:read]
  end
end

defmodule AshDataTable.Test.Relating.Note do
  @moduledoc """
  A destination whose primary read pages by offset and keyset and counts, with
  a second read action that pages by keyset only and does not count.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true
    attribute :written_on, :date, public?: true
  end

  relationships do
    belongs_to :book, AshDataTable.Test.Relating.Book, public?: true
  end

  aggregates do
    count :sibling_count, [:book, :notes], public?: true
  end

  actions do
    read :read do
      primary? true

      pagination offset?: true,
                 keyset?: true,
                 countable: true,
                 default_limit: 10,
                 required?: false
    end

    read :recent do
      pagination keyset?: true, countable: false, default_limit: 5, required?: false
    end

    update :update do
      primary? true
      accept [:body]
    end
  end

  table do
    update_action :update

    column :body
    column :written_on
    column :sibling_count
  end
end

defmodule AshDataTable.Test.Relating.Secret do
  @moduledoc "A destination only an admin may ever read: its read is refused outright."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :text, :string, public?: true
  end

  relationships do
    belongs_to :book, AshDataTable.Test.Relating.Book, public?: true
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
end

defmodule AshDataTable.Test.Relating.ManualNotes do
  @moduledoc "A manual relationship: the notes of the books, fetched by hand."
  use Ash.Resource.ManualRelationship

  require Ash.Query

  @impl true
  def load(books, _opts, %{query: query} = context) do
    ids = Enum.map(books, & &1.id)

    notes =
      query
      |> Ash.Query.filter(book_id in ^ids)
      |> Ash.read!(Ash.Context.to_opts(context))

    {:ok, Enum.group_by(notes, & &1.book_id)}
  end
end

defmodule AshDataTable.Test.Relating.Book do
  @moduledoc """
  A table that declares no `relationship`: a row offers every public
  relationship whose destination has a table, except the manual one.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  relationships do
    belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
    # its destination has no table
    belongs_to :shelf, AshDataTable.Test.Relating.Shelf, public?: true
    has_many :notes, AshDataTable.Test.Relating.Note, public?: true

    # through an action of its own, with a sort of its own
    has_many :recent_notes, AshDataTable.Test.Relating.Note do
      read_action :recent
      sort written_on: :asc
      public? true
    end

    has_one :latest_note, AshDataTable.Test.Relating.Note do
      from_many? true
      sort written_on: :desc
      public? true
    end

    # not public
    has_many :private_notes, AshDataTable.Test.Relating.Note

    many_to_many :tags, AshDataTable.Test.Relating.Tag do
      through AshDataTable.Test.Relating.BookTag
      source_attribute_on_join_resource :book_id
      destination_attribute_on_join_resource :tag_id
      public? true
    end

    has_many :by_the_same_author, __MODULE__ do
      no_attributes? true
      filter expr(author_id == parent(author_id) and id != parent(id))
      public? true
    end

    has_many :manual_notes, AshDataTable.Test.Relating.Note do
      manual AshDataTable.Test.Relating.ManualNotes
      public? true
    end

    has_many :secrets, AshDataTable.Test.Relating.Secret, public?: true
  end

  actions do
    defaults [:read]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end
end

defmodule AshDataTable.Test.Relating.Author do
  @moduledoc """
  A table that declares its relationships: exactly those, in that order, one
  of them relabelled and one of them manual. Its rows expand one level only.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    has_many :books, AshDataTable.Test.Relating.Book, public?: true

    has_many :manual_books, AshDataTable.Test.Relating.Book do
      manual AshDataTable.Test.Relating.ManualBooks
      public? true
    end

    has_one :first_book, AshDataTable.Test.Relating.Book do
      from_many? true
      sort title: :asc
      public? true
    end
  end

  actions do
    defaults [:read]
  end

  table do
    max_depth 1
    # what a book's reference cell calls its author
    label_field :name

    relationship :manual_books

    relationship :books do
      label "Written"
    end
  end
end

defmodule AshDataTable.Test.Relating.ManualBooks do
  @moduledoc false
  use Ash.Resource.ManualRelationship

  require Ash.Query

  @impl true
  def load(authors, _opts, %{query: query} = context) do
    ids = Enum.map(authors, & &1.id)

    books =
      query
      |> Ash.Query.filter(author_id in ^ids)
      |> Ash.read!(Ash.Context.to_opts(context))

    {:ok, Enum.group_by(books, & &1.author_id)}
  end
end
