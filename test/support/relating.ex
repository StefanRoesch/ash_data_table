defmodule AshTable.Test.Relating do
  @moduledoc """
  Resources for the tests of what a table offers below a row: one
  relationship of every kind, to destinations with and without a table.

  The actors of these tests are maps: `%{role: :admin}`.
  """
end

defmodule AshTable.Test.Relating.Shelf do
  @moduledoc "A destination without a table: it does not list the extension."
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTable.Test.Relating.Tag do
  @moduledoc "A destination whose read is not paginated, and whose rows never expand."
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    many_to_many :books, AshTable.Test.Relating.Book do
      through AshTable.Test.Relating.BookTag
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

defmodule AshTable.Test.Relating.BookTag do
  @moduledoc false
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  relationships do
    belongs_to :book, AshTable.Test.Relating.Book, primary_key?: true, allow_nil?: false
    belongs_to :tag, AshTable.Test.Relating.Tag, primary_key?: true, allow_nil?: false
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTable.Test.Relating.Note do
  @moduledoc """
  A destination whose primary read pages by offset and keyset and counts, with
  a second read action that pages by keyset only and does not count.
  """
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true
    attribute :written_on, :date, public?: true
  end

  relationships do
    belongs_to :book, AshTable.Test.Relating.Book, public?: true
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

defmodule AshTable.Test.Relating.Secret do
  @moduledoc "A destination only an admin may ever read: its read is refused outright."
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :text, :string, public?: true
  end

  relationships do
    belongs_to :book, AshTable.Test.Relating.Book, public?: true
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

defmodule AshTable.Test.Relating.ManualNotes do
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

defmodule AshTable.Test.Relating.Book do
  @moduledoc """
  A table that declares no `relationship`: a row offers every public
  relationship whose destination has a table, except the manual one.
  """
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  relationships do
    belongs_to :author, AshTable.Test.Relating.Author, public?: true
    # its destination has no table
    belongs_to :shelf, AshTable.Test.Relating.Shelf, public?: true
    has_many :notes, AshTable.Test.Relating.Note, public?: true

    # through an action of its own, with a sort of its own
    has_many :recent_notes, AshTable.Test.Relating.Note do
      read_action :recent
      sort written_on: :asc
      public? true
    end

    has_one :latest_note, AshTable.Test.Relating.Note do
      from_many? true
      sort written_on: :desc
      public? true
    end

    # not public
    has_many :private_notes, AshTable.Test.Relating.Note

    many_to_many :tags, AshTable.Test.Relating.Tag do
      through AshTable.Test.Relating.BookTag
      source_attribute_on_join_resource :book_id
      destination_attribute_on_join_resource :tag_id
      public? true
    end

    has_many :by_the_same_author, __MODULE__ do
      no_attributes? true
      filter expr(author_id == parent(author_id) and id != parent(id))
      public? true
    end

    has_many :manual_notes, AshTable.Test.Relating.Note do
      manual AshTable.Test.Relating.ManualNotes
      public? true
    end

    has_many :secrets, AshTable.Test.Relating.Secret, public?: true
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

defmodule AshTable.Test.Relating.Author do
  @moduledoc """
  A table that declares its relationships: exactly those, in that order, one
  of them relabelled and one of them manual. Its rows expand one level only.
  """
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    has_many :books, AshTable.Test.Relating.Book, public?: true

    has_many :manual_books, AshTable.Test.Relating.Book do
      manual AshTable.Test.Relating.ManualBooks
      public? true
    end

    has_one :first_book, AshTable.Test.Relating.Book do
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

defmodule AshTable.Test.Relating.ManualBooks do
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
