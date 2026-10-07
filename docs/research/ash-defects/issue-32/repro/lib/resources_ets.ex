defmodule V32.Ets.Domain do
  use Ash.Domain, validate_config_inclusion?: false
  resources do
    resource V32.Ets.User
    resource V32.Ets.Badge
    resource V32.Ets.Seal
    resource V32.Ets.Comment
    resource V32.Ets.Task
  end
end

# The three related resources share ONE read policy: admin reads all, anyone else only visible == true.
defmodule V32.Ets.User do
  use Ash.Resource, domain: V32.Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    private? false
  end
  actions do
    defaults [:read, create: :*]
    read :read_alt
  end
  policies do
    policy action_type(:create) do
      authorize_if always()
    end
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(visible == true)
    end
  end
  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :name, :string, public?: true
    attribute :visible, :boolean, public?: true, default: true
    attribute :manager_id, :integer, public?: true
  end
  relationships do
    belongs_to :manager, V32.Ets.User, public?: true, define_attribute?: false, source_attribute: :manager_id
  end
end

defmodule V32.Ets.Badge do
  use Ash.Resource, domain: V32.Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    private? false
  end
  actions do
    defaults [:read, create: :*]
  end
  policies do
    policy action_type(:create) do
      authorize_if always()
    end
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(visible == true)
    end
  end
  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :label, :string, public?: true
    attribute :visible, :boolean, public?: true, default: true
    attribute :task_id, :integer, public?: true
  end
end

defmodule V32.Ets.Seal do
  use Ash.Resource, domain: V32.Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    private? false
  end
  actions do
    defaults [:read, create: :*]
  end
  policies do
    policy action_type(:create) do
      authorize_if always()
    end
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(visible == true)
    end
  end
  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :label, :string, public?: true
    attribute :visible, :boolean, public?: true, default: true
    attribute :task_id, :integer, public?: true
  end
  identities do
    identity :one_per_task, [:task_id], pre_check_with: V32.Ets.Domain
  end
end

defmodule V32.Ets.Comment do
  use Ash.Resource, domain: V32.Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    private? false
  end
  actions do
    defaults [:read, create: :*]
  end
  policies do
    policy action_type(:create) do
      authorize_if always()
    end
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(visible == true)
    end
  end
  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :body, :string, public?: true
    attribute :visible, :boolean, public?: true, default: true
    attribute :task_id, :integer, public?: true
  end
end

defmodule V32.Ets.Task do
  use Ash.Resource, domain: V32.Ets.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]
  ets do
    private? false
  end
  actions do
    defaults [:read, create: :*]
    read :paged do
      pagination offset?: true, keyset?: true, required?: false
    end
  end
  policies do
    policy always() do
      authorize_if always()
    end
  end
  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :title, :string, public?: true
    attribute :assignee_id, :integer, public?: true
  end
  relationships do
    belongs_to :assignee, V32.Ets.User, public?: true, define_attribute?: false, source_attribute: :assignee_id
    has_one :badge, V32.Ets.Badge, public?: true, destination_attribute: :task_id
    has_one :seal, V32.Ets.Seal, public?: true, destination_attribute: :task_id
    has_many :comments, V32.Ets.Comment, public?: true, destination_attribute: :task_id
  end
  calculations do
    calculate :assignee_name_calc, :string, expr(assignee.name), public?: true
    calculate :badge_label_calc, :string, expr(badge.label), public?: true
    calculate :agg_wrapped_calc, :string, expr(assignee_name_agg), public?: true
  end
  aggregates do
    # the aggregate under test: first over a belongs_to
    first :assignee_name_agg, :assignee, :name, public?: true
    first :assignee_name_agg_filtered, :assignee, :name do
      public? true
      filter expr(name != "zzz")
    end
    count :assignee_count, :assignee, public?: true
    exists :assignee_exists, :assignee, public?: true
    list :assignee_names, :assignee, :name, public?: true
    max :assignee_name_max, :assignee, :name, public?: true
    first :assignee_not_alice, :assignee, :name do
      public? true
      filter expr(name != "Alice")
    end
    first :manager_name_agg, [:assignee, :manager], :name, public?: true
    # author-side workaround candidates: make the aggregate ineligible for the simple-join optimisation
    first :assignee_name_agg_jf, :assignee, :name do
      public? true
      join_filter :assignee, expr(not is_nil(id))
    end
    first :assignee_name_agg_ra, :assignee, :name do
      public? true
      read_action :read_alt
    end
    # has_one
    first :seal_label_agg, :seal, :label, public?: true
    first :badge_label_agg, :badge, :label, public?: true
    # to-many
    first :first_comment_agg, :comments, :body do
      public? true
      sort body: :asc
    end
    count :comment_count, :comments, public?: true
  end
end
