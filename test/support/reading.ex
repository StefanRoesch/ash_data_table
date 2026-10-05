defmodule AshTable.Test.Reading do
  @moduledoc """
  Resources that differ only in their read action and `table` block, for the
  tests of read action, pagination and sortability.

  `use AshTable.Test.Reading` gives a resource the same fields every time:
  a title, an attribute declared `sortable?: false`, an array attribute, an
  expression calculation and a count aggregate.
  """

  defmacro __using__(_opts) do
    quote do
      use Ash.Resource,
        domain: AshTable.Test.Domain,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshTable.Resource]

      attributes do
        uuid_primary_key :id
        attribute :title, :string, public?: true
        attribute :notes, :string, public?: true, sortable?: false
        attribute :tags, {:array, :string}, public?: true
      end

      relationships do
        has_many :comments, AshTable.Test.Comment, destination_attribute: :issue_id
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

defmodule AshTable.Test.Reading.Unpaginated do
  @moduledoc false
  use AshTable.Test.Reading

  actions do
    read :read do
      primary? true
    end
  end
end

defmodule AshTable.Test.Reading.OffsetOnly do
  @moduledoc false
  use AshTable.Test.Reading

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

defmodule AshTable.Test.Reading.KeysetOnly do
  @moduledoc false
  use AshTable.Test.Reading

  actions do
    read :read do
      primary? true
      pagination keyset?: true, max_page_size: 40, countable: false
    end
  end
end

defmodule AshTable.Test.Reading.Both do
  @moduledoc false
  use AshTable.Test.Reading

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

defmodule AshTable.Test.Reading.BothWithKeysetChosen do
  @moduledoc false
  use AshTable.Test.Reading

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
