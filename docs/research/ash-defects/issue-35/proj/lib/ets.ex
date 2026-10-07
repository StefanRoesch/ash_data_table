defmodule Ets.Domain do
  use Ash.Domain, validate_config_inclusion?: false
  resources do
    resource Ets.Project
    resource Ets.Comment
    resource Ets.CommentFP
    resource Ets.CommentPol
    resource Ets.TaskNone
    resource Ets.LinkNone
    resource Ets.ULinkNone
    resource Ets.TaskRec
    resource Ets.LinkRec
    resource Ets.ULinkRec
    resource Ets.TaskRecOnly
    resource Ets.LinkRecOnly
    resource Ets.ULinkRecOnly
    resource Ets.TaskAct
    resource Ets.LinkAct
    resource Ets.ULinkAct
    resource Ets.TaskRecAgg
    resource Ets.LinkRecAgg
    resource Ets.ULinkRecAgg
    resource Ets.TaskFilt
    resource Ets.LinkFilt
    resource Ets.ULinkFilt
  end
end

defmodule Ets.Project do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
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
    has_many :tasks_none, Ets.TaskNone, destination_attribute: :project_id, public?: true
    many_to_many :m2m_none, Ets.TaskNone, through: Ets.LinkNone, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    many_to_many :m2mu_none, Ets.TaskNone, through: Ets.ULinkNone, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    has_one :first_none, Ets.TaskNone, destination_attribute: :project_id, from_many?: true, sort: [points: :asc], public?: true
    has_many :tasks_rec, Ets.TaskRec, destination_attribute: :project_id, public?: true
    many_to_many :m2m_rec, Ets.TaskRec, through: Ets.LinkRec, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    many_to_many :m2mu_rec, Ets.TaskRec, through: Ets.ULinkRec, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    has_one :first_rec, Ets.TaskRec, destination_attribute: :project_id, from_many?: true, sort: [points: :asc], public?: true
    has_many :tasks_reconly, Ets.TaskRecOnly, destination_attribute: :project_id, public?: true
    many_to_many :m2m_reconly, Ets.TaskRecOnly, through: Ets.LinkRecOnly, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    many_to_many :m2mu_reconly, Ets.TaskRecOnly, through: Ets.ULinkRecOnly, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    has_one :first_reconly, Ets.TaskRecOnly, destination_attribute: :project_id, from_many?: true, sort: [points: :asc], public?: true
    has_many :tasks_act, Ets.TaskAct, destination_attribute: :project_id, public?: true
    many_to_many :m2m_act, Ets.TaskAct, through: Ets.LinkAct, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    many_to_many :m2mu_act, Ets.TaskAct, through: Ets.ULinkAct, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    has_one :first_act, Ets.TaskAct, destination_attribute: :project_id, from_many?: true, sort: [points: :asc], public?: true
    has_many :tasks_recagg, Ets.TaskRecAgg, destination_attribute: :project_id, public?: true
    many_to_many :m2m_recagg, Ets.TaskRecAgg, through: Ets.LinkRecAgg, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    many_to_many :m2mu_recagg, Ets.TaskRecAgg, through: Ets.ULinkRecAgg, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    has_one :first_recagg, Ets.TaskRecAgg, destination_attribute: :project_id, from_many?: true, sort: [points: :asc], public?: true
    has_many :tasks_filt, Ets.TaskFilt, destination_attribute: :project_id, public?: true
    many_to_many :m2m_filt, Ets.TaskFilt, through: Ets.LinkFilt, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    many_to_many :m2mu_filt, Ets.TaskFilt, through: Ets.ULinkFilt, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    has_one :first_filt, Ets.TaskFilt, destination_attribute: :project_id, from_many?: true, sort: [points: :asc], public?: true
  end
end

defmodule Ets.Comment do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    table :comments_shared
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
defmodule Ets.CommentFP do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    table :comments_shared
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
defmodule Ets.CommentPol do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    table :comments_shared
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

defmodule Ets.LinkNone do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    table :links_shared
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
defmodule Ets.ULinkNone do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    table :ulinks_shared
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

defmodule Ets.TaskNone do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer], primary_read_warning?: false
  ets do
    table :tasks_shared
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
    has_many :comments, Ets.Comment, destination_attribute: :task_id, public?: true
    has_many :pol_comments, Ets.CommentPol, destination_attribute: :task_id, public?: true
    has_many :fp_comments, Ets.CommentFP, destination_attribute: :task_id, public?: true
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

defmodule Ets.LinkRec do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    table :links_shared
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
defmodule Ets.ULinkRec do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    table :ulinks_shared
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

defmodule Ets.TaskRec do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer], primary_read_warning?: false
  ets do
    table :tasks_shared
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
    has_many :comments, Ets.Comment, destination_attribute: :task_id, public?: true
    has_many :pol_comments, Ets.CommentPol, destination_attribute: :task_id, public?: true
    has_many :fp_comments, Ets.CommentFP, destination_attribute: :task_id, public?: true
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

defmodule Ets.LinkRecOnly do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    table :links_shared
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
defmodule Ets.ULinkRecOnly do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    table :ulinks_shared
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

defmodule Ets.TaskRecOnly do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer], primary_read_warning?: false
  ets do
    table :tasks_shared
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
    has_many :comments, Ets.Comment, destination_attribute: :task_id, public?: true
    has_many :pol_comments, Ets.CommentPol, destination_attribute: :task_id, public?: true
    has_many :fp_comments, Ets.CommentFP, destination_attribute: :task_id, public?: true
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

defmodule Ets.LinkAct do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    table :links_shared
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
defmodule Ets.ULinkAct do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    table :ulinks_shared
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

defmodule Ets.TaskAct do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer], primary_read_warning?: false
  ets do
    table :tasks_shared
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
    has_many :comments, Ets.Comment, destination_attribute: :task_id, public?: true
    has_many :pol_comments, Ets.CommentPol, destination_attribute: :task_id, public?: true
    has_many :fp_comments, Ets.CommentFP, destination_attribute: :task_id, public?: true
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

defmodule Ets.LinkRecAgg do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    table :links_shared
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
defmodule Ets.ULinkRecAgg do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    table :ulinks_shared
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

defmodule Ets.TaskRecAgg do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer], primary_read_warning?: false
  ets do
    table :tasks_shared
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
    has_many :comments, Ets.Comment, destination_attribute: :task_id, public?: true
    has_many :pol_comments, Ets.CommentPol, destination_attribute: :task_id, public?: true
    has_many :fp_comments, Ets.CommentFP, destination_attribute: :task_id, public?: true
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

defmodule Ets.LinkFilt do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    table :links_shared
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
defmodule Ets.ULinkFilt do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    table :ulinks_shared
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

defmodule Ets.TaskFilt do
  use Ash.Resource, domain: Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer], primary_read_warning?: false
  ets do
    table :tasks_shared
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
    has_many :comments, Ets.Comment, destination_attribute: :task_id, public?: true
    has_many :pol_comments, Ets.CommentPol, destination_attribute: :task_id, public?: true
    has_many :fp_comments, Ets.CommentFP, destination_attribute: :task_id, public?: true
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

