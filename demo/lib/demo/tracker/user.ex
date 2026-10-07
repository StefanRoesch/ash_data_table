defmodule Demo.Tracker.User do
  @moduledoc """
  A person, and the actor of the demo. Not multitenant itself: it is looked up
  by id before the tenant is known, and its `organization_id` becomes the tenant.

  Its table is mounted nowhere: it is only ever seen nested, under the row of
  a task (its assignee, its reporter) or of a comment (its author). A viewer
  may not read people at all, so those lines are not there for a viewer.
  """
  use Ash.Resource,
    otp_app: :demo,
    domain: Demo.Tracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    # The default sort of a table lives on its read action, on purpose.
    primary_read_warning?: false

  postgres do
    table "users"
    repo Demo.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  field_policies do
    field_policy :assigned_hours do
      description "As the estimates it adds up: admins. (A task's own assignee sees its estimate too, which a sum cannot follow.)"
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  # Read-only, and its rows never expand: `max_depth 0` switches off the
  # assigned and the reported tasks a row would otherwise offer, wherever
  # this table is shown.
  table do
    max_depth 0
    # What a person is called where a table shows them as one value: in the
    # "Assignee" and "Reported by" columns of /tasks.
    label_field :name

    column :name
    column :email
    column :role

    # An aggregate over a field that a field policy protects on the tasks
    # (`estimate_hours`): Ash does not apply that policy to an aggregate, so
    # the aggregate has a field policy of its own, below.
    column :assigned_hours
  end

  actions do
    defaults [
      :destroy,
      create: [:name, :email, :role, :organization_id],
      update: [:name, :email, :role]
    ]

    read :read do
      primary? true
      pagination offset?: true, countable: true, default_limit: 25, required?: false
      prepare build(sort: [name: :asc, id: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      description "Refused outright, not filtered, for a viewer."
      access_type :strict
      forbid_if actor_attribute_equals(:role, :viewer)
      authorize_if always()
    end

    policy action_type(:read) do
      description "Users see the people of their own organization."
      authorize_if expr(organization_id == ^actor(:organization_id))
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints max_length: 80
    end

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :role, Demo.Tracker.Role do
      allow_nil? false
      default :member
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Demo.Tracker.Organization do
      allow_nil? false
      public? true
      attribute_public? true
    end

    has_many :assigned_tasks, Demo.Tracker.Task do
      destination_attribute :assignee_id
      public? true
    end

    has_many :reported_tasks, Demo.Tracker.Task do
      destination_attribute :reporter_id
      public? true
    end
  end

  aggregates do
    sum :assigned_hours, :assigned_tasks, :estimate_hours, public?: true
  end

  identities do
    identity :unique_email, [:email]
  end
end
