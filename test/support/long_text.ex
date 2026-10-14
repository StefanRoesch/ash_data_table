defmodule AshDataTable.Test.LongText.Note do
  @moduledoc "An embedded resource: a map cell."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :text, :string, public?: true
  end
end

defmodule AshDataTable.Test.LongText do
  @moduledoc """
  A resource for the tests of `max_lines`: a column of every cell type that
  takes it, one that says one line, and one whose component only edits. Its
  second table, `:short`, says another number for the same field.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :body, :string, public?: true
    attribute :summary, :ci_string, public?: true
    attribute :tags, {:array, :string}, public?: true
    attribute :note, AshDataTable.Test.LongText.Note, public?: true
    attribute :facts, :map, public?: true

    attribute :source, :union do
      public? true
      constraints types: [text: [type: :string], pages: [type: :integer]]
    end

    attribute :span, :duration, public?: true
    attribute :pages, :integer, public?: true
    # edited with a component, shown by the table
    attribute :mood, :string, public?: true
  end

  calculations do
    calculate :shout, :string, expr(body <> "!"), public?: true
  end

  actions do
    defaults [:read, update: [:title, :body, :mood]]
  end

  table do
    update_action :update

    column :title

    column :body do
      max_lines(3)
    end

    column :summary do
      max_lines(2)
    end

    column :tags do
      max_lines(2)
    end

    column :note do
      max_lines(2)
    end

    column :facts do
      max_lines(4)
    end

    column :source do
      max_lines(2)
    end

    column :span do
      max_lines(2)
    end

    column :shout do
      max_lines(10)
    end

    # one line said out loud is what a column has anyway: no finding
    column :pages do
      max_lines(1)
    end

    column :mood do
      max_lines(2)
      component AshDataTable.Test.Cells.Knob
    end
  end

  tables do
    table :short do
      column :title

      column :body do
        max_lines(2)
      end
    end
  end
end
