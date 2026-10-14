defmodule AshDataTable.Test.Status do
  @moduledoc false
  use Ash.Type.Enum,
    values: [
      open: [label: "Open"],
      in_progress: [label: "Being worked on"],
      done: [label: "Done"]
    ]
end

defmodule AshDataTable.Test.Project do
  @moduledoc false
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

defmodule AshDataTable.Test.Task do
  @moduledoc "A resource with the extension and no `table` block."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true, allow_nil?: false
    attribute :status, AshDataTable.Test.Status, public?: true
    attribute :estimate, :integer, public?: true
    attribute :internal_note, :string
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, AshDataTable.Test.Project, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshDataTable.Test.Comment do
  @moduledoc false
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true
  end

  relationships do
    belongs_to :issue, AshDataTable.Test.Issue, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshDataTable.Test.Issue do
  @moduledoc "A resource whose `table` block declares its columns."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true, allow_nil?: false
    attribute :status, AshDataTable.Test.Status, public?: true
    attribute :estimate, :integer, public?: true
    attribute :due_on, :date, public?: true
  end

  relationships do
    has_many :comments, AshDataTable.Test.Comment
  end

  calculations do
    calculate :shouted_title, :string, expr(title <> "!"), public?: true
  end

  aggregates do
    count :comment_count, :comments, public?: true
  end

  actions do
    defaults [:read]
  end

  table do
    column :status
    column :comment_count
    column :title
    column :shouted_title
  end
end

defmodule AshDataTable.Test.Labelled do
  @moduledoc "A table that labels a column and switches sorting off on another."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :due_on, :date, public?: true
    attribute :comment_count, :integer, public?: true
  end

  actions do
    defaults [:read]
  end

  table do
    column :due_on do
      label "Deadline"
    end

    column :comment_count do
      sortable? false
    end
  end
end
