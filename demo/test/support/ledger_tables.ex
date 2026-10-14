defmodule Demo.Support.Ledger do
  @moduledoc """
  A domain for the tests of what a table does about aggregate and
  calculation columns where Ash, or its SQL layer, does less than a table
  needs (the library's internal tickets #32, #34 and #35).

  Its resources exist for the tests only. They read the demo's own tables in
  Postgres, where those things happen, under policies of their own: a
  person reads the people of their own organization only, and sees some
  fields on some records only.

  The actors of these tests are the demo's users.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

  table do
    actor_assign :reader
  end

  resources do
    resource Demo.Support.Ledger.Person
    resource Demo.Support.Ledger.Job
    resource Demo.Support.Ledger.Errand
    resource Demo.Support.Ledger.Remark
    resource Demo.Support.Ledger.Tag
    resource Demo.Support.Ledger.Tagging
  end
end

defmodule Demo.Support.Ledger.Person do
  @moduledoc "A person, read by the people of their own organization only."
  use Ash.Resource,
    domain: Demo.Support.Ledger,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  postgres do
    table "users"
    repo Demo.Repo
    migrate? false
  end

  table do
    label_field :name

    column :name
  end

  actions do
    defaults [:read]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :role, :atom, public?: true
    attribute :organization_id, :uuid, public?: true
  end
end

defmodule Demo.Support.Ledger.Job do
  @moduledoc """
  A task under another name, read by everybody, five to a page.

  Its estimate, and the number of its remarks, are seen by an admin and by
  the job's own assignee: by a member on some records only. It shows the
  name of its assignee three ways: as a reference cell, as a `first`
  aggregate and, of the assignee's role, as a calculation over the
  relationship.
  """
  use Ash.Resource,
    domain: Demo.Support.Ledger,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  postgres do
    table "tasks"
    repo Demo.Repo
    migrate? false
  end

  field_policies do
    field_policy [:estimate_hours, :remark_count] do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(assignee_id == ^actor(:id))
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    update_action :update

    column :title
    column :estimate_hours
    column :remark_count
    column :tag_count
    # over an aggregate that a field policy protects: shown to everybody on
    # purpose, to have a calculation over an aggregate among the columns
    column :remarked? do
      exposes_protected_field? true
    end

    column :assignee
    # reaches through the relationship that the aggregate below is over
    column :assignee_role

    # read apart from the row for that, and neither sorted nor filtered by
    column :assignee_name do
      sortable? false
      filterable? false
    end

    relationship :remarks
    relationship :remarks_by_keyset
    relationship :latest_remark
    relationship :tags
  end

  actions do
    read :read do
      primary? true
      pagination offset?: true, keyset?: true, countable: true, default_limit: 5, required?: false
      prepare build(sort: [title: :asc, id: :asc])
    end

    update :update do
      primary? true
      accept [:title]
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :estimate_hours, :decimal, public?: true
    attribute :organization_id, :uuid, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :assignee, Demo.Support.Ledger.Person, public?: true

    has_many :remarks, Demo.Support.Ledger.Remark do
      destination_attribute :task_id
      public? true
    end

    has_many :remarks_by_keyset, Demo.Support.Ledger.Remark do
      destination_attribute :task_id
      read_action :by_keyset
      public? true
    end

    has_one :latest_remark, Demo.Support.Ledger.Remark do
      destination_attribute :task_id
      from_many? true
      sort inserted_at: :desc
      public? true
    end

    many_to_many :tags, Demo.Support.Ledger.Tag do
      through Demo.Support.Ledger.Tagging
      source_attribute_on_join_resource :task_id
      destination_attribute_on_join_resource :label_id
      public? true
    end
  end

  calculations do
    # over an aggregate
    calculate :remarked?, :boolean, expr(remark_count > 0), public?: true
    # over the relationship the `first` aggregate below is over
    calculate :assignee_role, :atom, expr(assignee.role), public?: true
  end

  aggregates do
    count :remark_count, :remarks, public?: true
    count :tag_count, :tags, public?: true
    first :assignee_name, :assignee, :name, public?: true
  end
end

defmodule Demo.Support.Ledger.Errand do
  @moduledoc """
  A task under yet another name: its assignee as a reference cell beside the
  `first` aggregate over the same relationship, and no calculation over it.
  The aggregate is read with the others, and sorted and filtered by.
  """
  use Ash.Resource,
    domain: Demo.Support.Ledger,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  postgres do
    table "tasks"
    repo Demo.Repo
    migrate? false
  end

  table do
    column :title
    column :assignee
    column :assignee_name
  end

  actions do
    read :read do
      primary? true
      pagination offset?: true, countable: true, default_limit: 5, required?: false
      prepare build(sort: [title: :asc, id: :asc])
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  relationships do
    belongs_to :assignee, Demo.Support.Ledger.Person, public?: true
  end

  aggregates do
    first :assignee_name, :assignee, :name, public?: true
  end
end

defmodule Demo.Support.Ledger.Remark do
  @moduledoc """
  A comment under another name, read by everybody, three to a page: by
  offset through its primary read, by keyset through another.

  Its body is seen by an admin and by the remark's own author: by a member
  on some records only. Its table shows an aggregate.
  """
  use Ash.Resource,
    domain: Demo.Support.Ledger,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  postgres do
    table "comments"
    repo Demo.Repo
    migrate? false
  end

  field_policies do
    field_policy :body do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(author_id == ^actor(:id))
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    column :body
    column :inserted_at
    column :tagging_count
    column :tagged?
  end

  actions do
    read :read do
      primary? true
      pagination offset?: true, countable: true, default_limit: 3, required?: false
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :by_keyset do
      pagination keyset?: true, countable: true, default_limit: 3, required?: false
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true
    attribute :author_id, :uuid, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :job, Demo.Support.Ledger.Job, source_attribute: :task_id, public?: true

    has_many :taggings, Demo.Support.Ledger.Tagging do
      source_attribute :task_id
      destination_attribute :task_id
    end
  end

  calculations do
    # over an aggregate
    calculate :tagged?, :boolean, expr(tagging_count > 0), public?: true
  end

  aggregates do
    # the labels of the remark's job
    count :tagging_count, :taggings, public?: true
  end
end

defmodule Demo.Support.Ledger.Tag do
  @moduledoc """
  A label under another name, read by everybody by a read that is not
  paginated. Its colour is seen by an admin, and by anybody on the label
  called "open": by a member on some records only. Its table shows an
  aggregate.
  """
  use Ash.Resource,
    domain: Demo.Support.Ledger,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  postgres do
    table "labels"
    repo Demo.Repo
    migrate? false
  end

  field_policies do
    field_policy :colour do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(name == "open")
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    column :name
    column :colour
    column :job_count
  end

  actions do
    read :read do
      primary? true
      prepare build(sort: [name: :asc])
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :colour, :string, public?: true
  end

  relationships do
    has_many :taggings, Demo.Support.Ledger.Tagging, destination_attribute: :label_id

    many_to_many :jobs, Demo.Support.Ledger.Job do
      through Demo.Support.Ledger.Tagging
      source_attribute_on_join_resource :label_id
      destination_attribute_on_join_resource :task_id
      public? true
    end
  end

  aggregates do
    count :job_count, :taggings, public?: true
  end
end

defmodule Demo.Support.Ledger.Tagging do
  @moduledoc "The join of jobs and tags, keyed on the pair."
  use Ash.Resource,
    domain: Demo.Support.Ledger,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "task_labels"
    repo Demo.Repo
    migrate? false
  end

  actions do
    defaults [:read]
  end

  attributes do
    attribute :task_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :label_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
  end
end
