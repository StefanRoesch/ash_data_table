# Generates lib/pg.ex and lib/ets.ex from one template, so that the two data layers have identical resources.
tpl = ~S'''
defmodule <%= ns %>.Domain do
  use Ash.Domain, validate_config_inclusion?: false
  resources do
    resource <%= ns %>.Project
    resource <%= ns %>.Comment
    resource <%= ns %>.CommentFP
    resource <%= ns %>.CommentPol
<%= for {v, _} <- variants do %>    resource <%= ns %>.Task<%= v %>
    resource <%= ns %>.Link<%= v %>
    resource <%= ns %>.ULink<%= v %>
<% end %>  end
end

defmodule <%= ns %>.Project do
  use Ash.Resource, domain: <%= ns %>.Domain, data_layer: <%= dl %>, authorizers: [Ash.Policy.Authorizer]
<%= if pg do %>  postgres do
    table "projects"
    repo Bug.Repo
  end
<% end %>  actions do
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
<%= for {v, _} <- variants do %>    has_many :tasks_<%= String.downcase(v) %>, <%= ns %>.Task<%= v %>, destination_attribute: :project_id, public?: true
    many_to_many :m2m_<%= String.downcase(v) %>, <%= ns %>.Task<%= v %>, through: <%= ns %>.Link<%= v %>, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    many_to_many :m2mu_<%= String.downcase(v) %>, <%= ns %>.Task<%= v %>, through: <%= ns %>.ULink<%= v %>, source_attribute_on_join_resource: :project_id, destination_attribute_on_join_resource: :task_id, public?: true
    has_one :first_<%= String.downcase(v) %>, <%= ns %>.Task<%= v %>, destination_attribute: :project_id, from_many?: true, sort: [points: :asc], public?: true
<% end %>  end
end

defmodule <%= ns %>.Comment do
  use Ash.Resource, domain: <%= ns %>.Domain, data_layer: <%= dl %>, authorizers: [Ash.Policy.Authorizer]
<%= if pg do %>  postgres do
    table "comments"
    repo Bug.Repo
  end
<% else %>  ets do
    table :comments_shared
  end
<% end %>  actions do
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
defmodule <%= ns %>.CommentFP do
  use Ash.Resource, domain: <%= ns %>.Domain, data_layer: <%= dl %>, authorizers: [Ash.Policy.Authorizer]
<%= if pg do %>  postgres do
    table "comments"
    repo Bug.Repo
  end
<% else %>  ets do
    table :comments_shared
  end
<% end %>  actions do
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
defmodule <%= ns %>.CommentPol do
  use Ash.Resource, domain: <%= ns %>.Domain, data_layer: <%= dl %>, authorizers: [Ash.Policy.Authorizer]
<%= if pg do %>  postgres do
    table "comments"
    repo Bug.Repo
  end
<% else %>  ets do
    table :comments_shared
  end
<% end %>  actions do
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
<%= for {v, fp} <- variants do %>
defmodule <%= ns %>.Link<%= v %> do
  use Ash.Resource, domain: <%= ns %>.Domain, data_layer: <%= dl %>, authorizers: [Ash.Policy.Authorizer]
<%= if pg do %>  postgres do
    table "links"
    repo Bug.Repo
  end
<% else %>  ets do
    table :links_shared
  end
<% end %>  actions do
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
defmodule <%= ns %>.ULink<%= v %> do
  use Ash.Resource, domain: <%= ns %>.Domain, data_layer: <%= dl %>, authorizers: [Ash.Policy.Authorizer]
<%= if pg do %>  postgres do
    table "ulinks"
    repo Bug.Repo
  end
<% else %>  ets do
    table :ulinks_shared
  end
<% end %>  actions do
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

defmodule <%= ns %>.Task<%= v %> do
  use Ash.Resource, domain: <%= ns %>.Domain, data_layer: <%= dl %>, authorizers: [Ash.Policy.Authorizer], primary_read_warning?: false
<%= if pg do %>  postgres do
    table "tasks"
    repo Bug.Repo
  end
<% else %>  ets do
    table :tasks_shared
  end
<% end %>  actions do
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
<%= if v == "Filt" do %>    policy action_type(:read) do
      authorize_if expr(points < 100)
    end
<% else %>    policy always() do
      authorize_if always()
    end
<% end %>  end
<%= fp %>
  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :secret, :string, public?: true
    attribute :points, :integer, public?: true
    attribute :assignee_id, :uuid, public?: true
    attribute :project_id, :uuid, public?: true
  end
  relationships do
    has_many :comments, <%= ns %>.Comment, destination_attribute: :task_id, public?: true
    has_many :pol_comments, <%= ns %>.CommentPol, destination_attribute: :task_id, public?: true
    has_many :fp_comments, <%= ns %>.CommentFP, destination_attribute: :task_id, public?: true
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
<% end %>
'''
none = ""
rec = """
  field_policies do
    field_policy :secret do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(assignee_id == ^actor(:id))
    end
    field_policy :* do
      authorize_if always()
    end
  end
"""
rec_only = """
  field_policies do
    field_policy :secret do
      authorize_if expr(assignee_id == ^actor(:id))
    end
    field_policy :* do
      authorize_if always()
    end
  end
"""
act = """
  field_policies do
    field_policy :secret do
      authorize_if actor_attribute_equals(:role, :admin)
    end
    field_policy :* do
      authorize_if always()
    end
  end
"""
# record-dependent field policy on an AGGREGATE itself and on a calculation
recagg = """
  field_policies do
    field_policy [:agg_count, :double_points] do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(assignee_id == ^actor(:id))
    end
    field_policy :* do
      authorize_if always()
    end
  end
"""
variants = [{"None", none}, {"Rec", rec}, {"RecOnly", rec_only}, {"Act", act}, {"RecAgg", recagg}, {"Filt", none}]
for {ns, dl, pg} <- [{"Pg", "AshPostgres.DataLayer", true}, {"Ets", "Ash.DataLayer.Ets", false}] do
  File.write!("lib/#{String.downcase(ns)}.ex", EEx.eval_string(tpl, ns: ns, dl: dl, pg: pg, variants: variants))
end
