defmodule AshDataTable.Test.Reading do
  @moduledoc """
  Resources that differ only in their read action and `table` block, for the
  tests of read action, pagination and sortability.

  `use AshDataTable.Test.Reading` gives a resource the same fields every time:
  a title, an attribute declared `sortable?: false`, an array attribute, an
  expression calculation and a count aggregate.
  """

  defmacro __using__(_opts) do
    quote do
      use Ash.Resource,
        domain: AshDataTable.Test.Domain,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshDataTable.Resource]

      attributes do
        uuid_primary_key :id
        attribute :title, :string, public?: true
        attribute :notes, :string, public?: true, sortable?: false
        attribute :tags, {:array, :string}, public?: true
      end

      relationships do
        has_many :comments, AshDataTable.Test.Comment, destination_attribute: :issue_id
      end

      calculations do
        calculate :shouted_title, :string, expr(^ref(:title) <> "!"), public?: true
      end

      aggregates do
        count :comment_count, :comments, public?: true
      end
    end
  end
end

defmodule AshDataTable.Test.Reading.Unpaginated do
  @moduledoc false
  use AshDataTable.Test.Reading

  actions do
    read :read do
      primary? true
    end
  end
end

defmodule AshDataTable.Test.Reading.OffsetOnly do
  @moduledoc false
  use AshDataTable.Test.Reading

  actions do
    read :read do
      primary? true
    end

    read :paged do
      pagination offset?: true, default_limit: 10, countable: true
    end
  end

  table do
    read_action :paged
  end
end

defmodule AshDataTable.Test.Reading.KeysetOnly do
  @moduledoc false
  use AshDataTable.Test.Reading

  actions do
    read :read do
      primary? true
      pagination keyset?: true, max_page_size: 40, countable: false
    end
  end
end

defmodule AshDataTable.Test.Reading.Both do
  @moduledoc false
  use AshDataTable.Test.Reading

  actions do
    read :read do
      primary? true

      pagination offset?: true,
                 keyset?: true,
                 default_limit: 5,
                 max_page_size: 50,
                 countable: :by_default
    end
  end

  table do
    column :title
    column :shouted_title
    column :comment_count
  end
end

defmodule AshDataTable.Test.Reading.BothWithKeysetChosen do
  @moduledoc false
  use AshDataTable.Test.Reading

  actions do
    read :read do
      primary? true
      pagination offset?: true, keyset?: true, default_limit: 5
    end
  end

  table do
    paginate_with :keyset

    column :title
    column :shouted_title
    column :comment_count
  end
end

defmodule AshDataTable.Test.Reading.SmallMaximum do
  @moduledoc false
  use AshDataTable.Test.Reading

  actions do
    read :read do
      primary? true
      pagination offset?: true, max_page_size: 10
    end
  end
end

defmodule AshDataTable.Test.Reading.Sized do
  @moduledoc """
  Tables that offer page sizes. The default one pages by offset and opens
  with the action's `default_limit`; `:by_keyset` pages by keyset;
  `:first_wins` reads through an action without a `default_limit` and opens
  with the first size as it is written.

  The other read actions are for relationships that read it through an
  action of their own (`AshDataTable.Test.Reading.SizedShelf`).
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :shelf_id, :uuid, public?: true
  end

  actions do
    defaults [:destroy, create: [:title, :shelf_id]]

    read :read do
      primary? true

      pagination offset?: true,
                 keyset?: true,
                 default_limit: 5,
                 max_page_size: 50,
                 countable: true,
                 required?: false
    end

    read :without_default do
      pagination offset?: true, max_page_size: 40, required?: false
    end

    # allows less than the default table offers
    read :few do
      pagination offset?: true, default_limit: 5, max_page_size: 10, required?: false
    end

    # opens with a size the default table does not offer
    read :sevens do
      pagination offset?: true, default_limit: 7, max_page_size: 50, required?: false
    end

    read :unpaged

    # a page of related records cannot be read through it
    read :needy do
      argument :term, :string, allow_nil?: false
      pagination offset?: true, default_limit: 7, max_page_size: 10, required?: false
    end
  end

  table do
    page_sizes [20, 5, 10]

    column :title
  end

  tables do
    table :by_keyset do
      paginate_with :keyset
      page_sizes [5, 10]

      column :title
    end

    table :first_wins do
      read_action :without_default
      page_sizes [30, 10, 20]

      column :title
    end
  end
end

defmodule AshDataTable.Test.Reading.SizedShelf do
  @moduledoc """
  A table that declares no `relationship`, over records that are read in
  `AshDataTable.Test.Reading.Sized`'s table through actions of their own.
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
    has_many :items, AshDataTable.Test.Reading.Sized,
      destination_attribute: :shelf_id,
      public?: true

    has_many :few_items, AshDataTable.Test.Reading.Sized do
      destination_attribute :shelf_id
      read_action :few
      public? true
    end

    has_many :unpaged_items, AshDataTable.Test.Reading.Sized do
      destination_attribute :shelf_id
      read_action :unpaged
      public? true
    end

    has_many :needy_items, AshDataTable.Test.Reading.Sized do
      destination_attribute :shelf_id
      read_action :needy
      public? true
    end

    has_one :first_item, AshDataTable.Test.Reading.Sized do
      destination_attribute :shelf_id
      from_many? true
      public? true
    end
  end

  actions do
    defaults [:read, create: [:name]]
  end
end
