defmodule Pg.Domain do
  use Ash.Domain, validate_config_inclusion?: false
  resources do
    resource Pg.Project
    resource Pg.Comment
    resource Pg.CommentFP
    resource Pg.CommentPol
    resource Pg.TaskNone
    resource Pg.LinkNone
    resource Pg.ULinkNone
    resource Pg.TaskRec
    resource Pg.LinkRec
    resource Pg.ULinkRec
    resource Pg.TaskRecOnly
    resource Pg.LinkRecOnly
    resource Pg.ULinkRecOnly
    resource Pg.TaskAct
    resource Pg.LinkAct
    resource Pg.ULinkAct
    resource Pg.TaskRecAgg
    resource Pg.LinkRecAgg
    resource Pg.ULinkRecAgg
    resource Pg.TaskFilt
    resource Pg.LinkFilt
    resource Pg.ULinkFilt
  end
end

defmodule Pg.Project do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "projects"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:name]]
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end
  relationships do
    has_many :tasks_none, Pg.TaskNone, destination_attribute: :project_id, public?: true
    many_to_many :m2m_none, Pg.TaskNone, through: Pg.LinkNone, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    many_to_many :m2mu_none, Pg.TaskNone, through: Pg.ULinkNone, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    has_one :first_none, Pg.TaskNone, destination_attribute: :project_id, from_many?: true, sort: [points: :asc], public?: true
    has_many :tasks_rec, Pg.TaskRec, destination_attribute: :project_id, public?: true
    many_to_many :m2m_rec, Pg.TaskRec, through: Pg.LinkRec, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    many_to_many :m2mu_rec, Pg.TaskRec, through: Pg.ULinkRec, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    has_one :first_rec, Pg.TaskRec, destination_attribute: :project_id, from_many?: true, sort: [points: :asc], public?: true
    has_many :tasks_reconly, Pg.TaskRecOnly, destination_attribute: :project_id, public?: true
    many_to_many :m2m_reconly, Pg.TaskRecOnly, through: Pg.LinkRecOnly, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    many_to_many :m2mu_reconly, Pg.TaskRecOnly, through: Pg.ULinkRecOnly, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    has_one :first_reconly, Pg.TaskRecOnly, destination_attribute: :project_id, from_many?: true, sort: [points: :asc], public?: true
    has_many :tasks_act, Pg.TaskAct, destination_attribute: :project_id, public?: true
    many_to_many :m2m_act, Pg.TaskAct, through: Pg.LinkAct, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    many_to_many :m2mu_act, Pg.TaskAct, through: Pg.ULinkAct, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    has_one :first_act, Pg.TaskAct, destination_attribute: :project_id, from_many?: true, sort: [points: :asc], public?: true
    has_many :tasks_recagg, Pg.TaskRecAgg, destination_attribute: :project_id, public?: true
    many_to_many :m2m_recagg, Pg.TaskRecAgg, through: Pg.LinkRecAgg, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    many_to_many :m2mu_recagg, Pg.TaskRecAgg, through: Pg.ULinkRecAgg, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    has_one :first_recagg, Pg.TaskRecAgg, destination_attribute: :project_id, from_many?: true, sort: [points: :asc], public?: true
    has_many :tasks_filt, Pg.TaskFilt, destination_attribute: :project_id, public?: true
    many_to_many :m2m_filt, Pg.TaskFilt, through: Pg.LinkFilt, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    many_to_many :m2mu_filt, Pg.TaskFilt, through: Pg.ULinkFilt, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    has_one :first_filt, Pg.TaskFilt, destination_attribute: :project_id, from_many?: true, sort: [points: :asc], public?: true
  end
end

defmodule Pg.Comment do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "comments"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:body, :score, :task_id, :author_id]]
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true
    attribute :score, :integer, public?: true
    attribute :task_id, :uuid, public?: true
    attribute :author_id, :uuid, public?: true
  end
end

# The same comments, with a record-dependent field policy on `score`.
defmodule Pg.CommentFP do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "comments"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:body, :score, :task_id, :author_id]]
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  field_policies do
    field_policy :score do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(author_id == ^actor(:id))
    end
    field_policy :* do
      authorize_if always()
    end
  end
  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true
    attribute :score, :integer, public?: true
    attribute :task_id, :uuid, public?: true
    attribute :author_id, :uuid, public?: true
  end
end
# The same comments, with a FILTER read policy: only the actor's own.
defmodule Pg.CommentPol do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "comments"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:body, :score, :task_id, :author_id]]
  end
  policies do
    policy action_type(:read) do
      authorize_if expr(author_id == ^actor(:id))
    end
  end
  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true
    attribute :score, :integer, public?: true
    attribute :task_id, :uuid, public?: true
    attribute :author_id, :uuid, public?: true
  end
end

defmodule Pg.LinkNone do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "links"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:project_id, :task_id]]
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  attributes do
    uuid_primary_key :id
    attribute :project_id, :uuid, public?: true
    attribute :task_id, :uuid, public?: true
  end
end

# a join resource whose primary key is the pair: the usual shape, and the one Ash can lateral-join through
defmodule Pg.ULinkNone do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "ulinks"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:project_id, :task_id]]
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  attributes do
    attribute :project_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :task_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
  end
end

defmodule Pg.TaskNone do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer], primary_read_warning?: false
  postgres do
    table "tasks"
    repo Bug.Repo
  end
  actions do
    defaults [:destroy, create: [:title, :secret, :points, :assignee_id, :project_id]]
    read :read do
      primary? true
      pagination offset?: true, keyset?: true, countable: true, required?: false, default_limit: 25
    end
    read :unpaginated
    read :sorted do
      pagination offset?: true, keyset?: true, countable: true, required?: false, default_limit: 25
      prepare build(sort: [points: :desc, id: :desc])
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
    attribute :secret, :string, public?: true
    attribute :points, :integer, public?: true
    attribute :assignee_id, :uuid, public?: true
    attribute :project_id, :uuid, public?: true
  end
  relationships do
    has_many :comments, Pg.Comment, destination_attribute: :task_id, public?: true
    has_many :pol_comments, Pg.CommentPol, destination_attribute: :task_id, public?: true
    has_many :fp_comments, Pg.CommentFP, destination_attribute: :task_id, public?: true
  end
  calculations do
    calculate :double_points, :integer, expr(points * 2), public?: true
    calculate :secret_calc, :string, expr(secret <> "!"), public?: true
    calculate :agg_count_calc, :integer, expr(agg_count), public?: true
    calculate :elixir_calc, :string, Bug.TitleCalc, public?: true
  end
  aggregates do
    count :agg_count, :comments, public?: true
    first :agg_first, :comments, :body do
      sort score: :asc
      public? true
    end
    list :agg_list, :comments, :body do
      sort score: :asc
      public? true
    end
    max :agg_max, :comments, :score, public?: true
    sum :agg_sum, :comments, :score, public?: true
    exists :agg_exists, :comments, public?: true
    count :agg_count_filtered, :comments do
      filter expr(score > 1)
      public? true
    end
    # over a resource that itself has a record-dependent field policy, aggregating the protected field
    max :agg_max_protected, :fp_comments, :score, public?: true
    count :agg_count_fp, :fp_comments, public?: true
    # over comments whose read policy is a filter
    count :agg_count_pol, :pol_comments, public?: true
  end
end

defmodule Pg.LinkRec do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "links"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:project_id, :task_id]]
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  attributes do
    uuid_primary_key :id
    attribute :project_id, :uuid, public?: true
    attribute :task_id, :uuid, public?: true
  end
end

# a join resource whose primary key is the pair: the usual shape, and the one Ash can lateral-join through
defmodule Pg.ULinkRec do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "ulinks"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:project_id, :task_id]]
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  attributes do
    attribute :project_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :task_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
  end
end

defmodule Pg.TaskRec do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer], primary_read_warning?: false
  postgres do
    table "tasks"
    repo Bug.Repo
  end
  actions do
    defaults [:destroy, create: [:title, :secret, :points, :assignee_id, :project_id]]
    read :read do
      primary? true
      pagination offset?: true, keyset?: true, countable: true, required?: false, default_limit: 25
    end
    read :unpaginated
    read :sorted do
      pagination offset?: true, keyset?: true, countable: true, required?: false, default_limit: 25
      prepare build(sort: [points: :desc, id: :desc])
    end
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  field_policies do
    field_policy :secret do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(assignee_id == ^actor(:id))
    end
    field_policy :* do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :secret, :string, public?: true
    attribute :points, :integer, public?: true
    attribute :assignee_id, :uuid, public?: true
    attribute :project_id, :uuid, public?: true
  end
  relationships do
    has_many :comments, Pg.Comment, destination_attribute: :task_id, public?: true
    has_many :pol_comments, Pg.CommentPol, destination_attribute: :task_id, public?: true
    has_many :fp_comments, Pg.CommentFP, destination_attribute: :task_id, public?: true
  end
  calculations do
    calculate :double_points, :integer, expr(points * 2), public?: true
    calculate :secret_calc, :string, expr(secret <> "!"), public?: true
    calculate :agg_count_calc, :integer, expr(agg_count), public?: true
    calculate :elixir_calc, :string, Bug.TitleCalc, public?: true
  end
  aggregates do
    count :agg_count, :comments, public?: true
    first :agg_first, :comments, :body do
      sort score: :asc
      public? true
    end
    list :agg_list, :comments, :body do
      sort score: :asc
      public? true
    end
    max :agg_max, :comments, :score, public?: true
    sum :agg_sum, :comments, :score, public?: true
    exists :agg_exists, :comments, public?: true
    count :agg_count_filtered, :comments do
      filter expr(score > 1)
      public? true
    end
    # over a resource that itself has a record-dependent field policy, aggregating the protected field
    max :agg_max_protected, :fp_comments, :score, public?: true
    count :agg_count_fp, :fp_comments, public?: true
    # over comments whose read policy is a filter
    count :agg_count_pol, :pol_comments, public?: true
  end
end

defmodule Pg.LinkRecOnly do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "links"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:project_id, :task_id]]
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  attributes do
    uuid_primary_key :id
    attribute :project_id, :uuid, public?: true
    attribute :task_id, :uuid, public?: true
  end
end

# a join resource whose primary key is the pair: the usual shape, and the one Ash can lateral-join through
defmodule Pg.ULinkRecOnly do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "ulinks"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:project_id, :task_id]]
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  attributes do
    attribute :project_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :task_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
  end
end

defmodule Pg.TaskRecOnly do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer], primary_read_warning?: false
  postgres do
    table "tasks"
    repo Bug.Repo
  end
  actions do
    defaults [:destroy, create: [:title, :secret, :points, :assignee_id, :project_id]]
    read :read do
      primary? true
      pagination offset?: true, keyset?: true, countable: true, required?: false, default_limit: 25
    end
    read :unpaginated
    read :sorted do
      pagination offset?: true, keyset?: true, countable: true, required?: false, default_limit: 25
      prepare build(sort: [points: :desc, id: :desc])
    end
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  field_policies do
    field_policy :secret do
      authorize_if expr(assignee_id == ^actor(:id))
    end
    field_policy :* do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :secret, :string, public?: true
    attribute :points, :integer, public?: true
    attribute :assignee_id, :uuid, public?: true
    attribute :project_id, :uuid, public?: true
  end
  relationships do
    has_many :comments, Pg.Comment, destination_attribute: :task_id, public?: true
    has_many :pol_comments, Pg.CommentPol, destination_attribute: :task_id, public?: true
    has_many :fp_comments, Pg.CommentFP, destination_attribute: :task_id, public?: true
  end
  calculations do
    calculate :double_points, :integer, expr(points * 2), public?: true
    calculate :secret_calc, :string, expr(secret <> "!"), public?: true
    calculate :agg_count_calc, :integer, expr(agg_count), public?: true
    calculate :elixir_calc, :string, Bug.TitleCalc, public?: true
  end
  aggregates do
    count :agg_count, :comments, public?: true
    first :agg_first, :comments, :body do
      sort score: :asc
      public? true
    end
    list :agg_list, :comments, :body do
      sort score: :asc
      public? true
    end
    max :agg_max, :comments, :score, public?: true
    sum :agg_sum, :comments, :score, public?: true
    exists :agg_exists, :comments, public?: true
    count :agg_count_filtered, :comments do
      filter expr(score > 1)
      public? true
    end
    # over a resource that itself has a record-dependent field policy, aggregating the protected field
    max :agg_max_protected, :fp_comments, :score, public?: true
    count :agg_count_fp, :fp_comments, public?: true
    # over comments whose read policy is a filter
    count :agg_count_pol, :pol_comments, public?: true
  end
end

defmodule Pg.LinkAct do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "links"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:project_id, :task_id]]
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  attributes do
    uuid_primary_key :id
    attribute :project_id, :uuid, public?: true
    attribute :task_id, :uuid, public?: true
  end
end

# a join resource whose primary key is the pair: the usual shape, and the one Ash can lateral-join through
defmodule Pg.ULinkAct do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "ulinks"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:project_id, :task_id]]
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  attributes do
    attribute :project_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :task_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
  end
end

defmodule Pg.TaskAct do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer], primary_read_warning?: false
  postgres do
    table "tasks"
    repo Bug.Repo
  end
  actions do
    defaults [:destroy, create: [:title, :secret, :points, :assignee_id, :project_id]]
    read :read do
      primary? true
      pagination offset?: true, keyset?: true, countable: true, required?: false, default_limit: 25
    end
    read :unpaginated
    read :sorted do
      pagination offset?: true, keyset?: true, countable: true, required?: false, default_limit: 25
      prepare build(sort: [points: :desc, id: :desc])
    end
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  field_policies do
    field_policy :secret do
      authorize_if actor_attribute_equals(:role, :admin)
    end
    field_policy :* do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :secret, :string, public?: true
    attribute :points, :integer, public?: true
    attribute :assignee_id, :uuid, public?: true
    attribute :project_id, :uuid, public?: true
  end
  relationships do
    has_many :comments, Pg.Comment, destination_attribute: :task_id, public?: true
    has_many :pol_comments, Pg.CommentPol, destination_attribute: :task_id, public?: true
    has_many :fp_comments, Pg.CommentFP, destination_attribute: :task_id, public?: true
  end
  calculations do
    calculate :double_points, :integer, expr(points * 2), public?: true
    calculate :secret_calc, :string, expr(secret <> "!"), public?: true
    calculate :agg_count_calc, :integer, expr(agg_count), public?: true
    calculate :elixir_calc, :string, Bug.TitleCalc, public?: true
  end
  aggregates do
    count :agg_count, :comments, public?: true
    first :agg_first, :comments, :body do
      sort score: :asc
      public? true
    end
    list :agg_list, :comments, :body do
      sort score: :asc
      public? true
    end
    max :agg_max, :comments, :score, public?: true
    sum :agg_sum, :comments, :score, public?: true
    exists :agg_exists, :comments, public?: true
    count :agg_count_filtered, :comments do
      filter expr(score > 1)
      public? true
    end
    # over a resource that itself has a record-dependent field policy, aggregating the protected field
    max :agg_max_protected, :fp_comments, :score, public?: true
    count :agg_count_fp, :fp_comments, public?: true
    # over comments whose read policy is a filter
    count :agg_count_pol, :pol_comments, public?: true
  end
end

defmodule Pg.LinkRecAgg do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "links"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:project_id, :task_id]]
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  attributes do
    uuid_primary_key :id
    attribute :project_id, :uuid, public?: true
    attribute :task_id, :uuid, public?: true
  end
end

# a join resource whose primary key is the pair: the usual shape, and the one Ash can lateral-join through
defmodule Pg.ULinkRecAgg do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "ulinks"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:project_id, :task_id]]
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  attributes do
    attribute :project_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :task_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
  end
end

defmodule Pg.TaskRecAgg do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer], primary_read_warning?: false
  postgres do
    table "tasks"
    repo Bug.Repo
  end
  actions do
    defaults [:destroy, create: [:title, :secret, :points, :assignee_id, :project_id]]
    read :read do
      primary? true
      pagination offset?: true, keyset?: true, countable: true, required?: false, default_limit: 25
    end
    read :unpaginated
    read :sorted do
      pagination offset?: true, keyset?: true, countable: true, required?: false, default_limit: 25
      prepare build(sort: [points: :desc, id: :desc])
    end
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  field_policies do
    field_policy [:agg_count, :double_points] do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(assignee_id == ^actor(:id))
    end
    field_policy :* do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :secret, :string, public?: true
    attribute :points, :integer, public?: true
    attribute :assignee_id, :uuid, public?: true
    attribute :project_id, :uuid, public?: true
  end
  relationships do
    has_many :comments, Pg.Comment, destination_attribute: :task_id, public?: true
    has_many :pol_comments, Pg.CommentPol, destination_attribute: :task_id, public?: true
    has_many :fp_comments, Pg.CommentFP, destination_attribute: :task_id, public?: true
  end
  calculations do
    calculate :double_points, :integer, expr(points * 2), public?: true
    calculate :secret_calc, :string, expr(secret <> "!"), public?: true
    calculate :agg_count_calc, :integer, expr(agg_count), public?: true
    calculate :elixir_calc, :string, Bug.TitleCalc, public?: true
  end
  aggregates do
    count :agg_count, :comments, public?: true
    first :agg_first, :comments, :body do
      sort score: :asc
      public? true
    end
    list :agg_list, :comments, :body do
      sort score: :asc
      public? true
    end
    max :agg_max, :comments, :score, public?: true
    sum :agg_sum, :comments, :score, public?: true
    exists :agg_exists, :comments, public?: true
    count :agg_count_filtered, :comments do
      filter expr(score > 1)
      public? true
    end
    # over a resource that itself has a record-dependent field policy, aggregating the protected field
    max :agg_max_protected, :fp_comments, :score, public?: true
    count :agg_count_fp, :fp_comments, public?: true
    # over comments whose read policy is a filter
    count :agg_count_pol, :pol_comments, public?: true
  end
end

defmodule Pg.LinkFilt do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "links"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:project_id, :task_id]]
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  attributes do
    uuid_primary_key :id
    attribute :project_id, :uuid, public?: true
    attribute :task_id, :uuid, public?: true
  end
end

# a join resource whose primary key is the pair: the usual shape, and the one Ash can lateral-join through
defmodule Pg.ULinkFilt do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]
  postgres do
    table "ulinks"
    repo Bug.Repo
  end
  actions do
    defaults [:read, :destroy, create: [:project_id, :task_id]]
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  attributes do
    attribute :project_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :task_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
  end
end

defmodule Pg.TaskFilt do
  use Ash.Resource, domain: Pg.Domain, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer], primary_read_warning?: false
  postgres do
    table "tasks"
    repo Bug.Repo
  end
  actions do
    defaults [:destroy, create: [:title, :secret, :points, :assignee_id, :project_id]]
    read :read do
      primary? true
      pagination offset?: true, keyset?: true, countable: true, required?: false, default_limit: 25
    end
    read :unpaginated
    read :sorted do
      pagination offset?: true, keyset?: true, countable: true, required?: false, default_limit: 25
      prepare build(sort: [points: :desc, id: :desc])
    end
  end
  policies do
    policy action_type(:read) do
      authorize_if expr(points < 100)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :secret, :string, public?: true
    attribute :points, :integer, public?: true
    attribute :assignee_id, :uuid, public?: true
    attribute :project_id, :uuid, public?: true
  end
  relationships do
    has_many :comments, Pg.Comment, destination_attribute: :task_id, public?: true
    has_many :pol_comments, Pg.CommentPol, destination_attribute: :task_id, public?: true
    has_many :fp_comments, Pg.CommentFP, destination_attribute: :task_id, public?: true
  end
  calculations do
    calculate :double_points, :integer, expr(points * 2), public?: true
    calculate :secret_calc, :string, expr(secret <> "!"), public?: true
    calculate :agg_count_calc, :integer, expr(agg_count), public?: true
    calculate :elixir_calc, :string, Bug.TitleCalc, public?: true
  end
  aggregates do
    count :agg_count, :comments, public?: true
    first :agg_first, :comments, :body do
      sort score: :asc
      public? true
    end
    list :agg_list, :comments, :body do
      sort score: :asc
      public? true
    end
    max :agg_max, :comments, :score, public?: true
    sum :agg_sum, :comments, :score, public?: true
    exists :agg_exists, :comments, public?: true
    count :agg_count_filtered, :comments do
      filter expr(score > 1)
      public? true
    end
    # over a resource that itself has a record-dependent field policy, aggregating the protected field
    max :agg_max_protected, :fp_comments, :score, public?: true
    count :agg_count_fp, :fp_comments, public?: true
    # over comments whose read policy is a filter
    count :agg_count_pol, :pol_comments, public?: true
  end
end

