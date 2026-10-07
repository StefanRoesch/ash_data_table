defmodule Demo.Tracker.Project do
  @moduledoc """
  A project of an organization, holding tasks.

  Its read is refused outright for an anonymous visitor (a strict policy),
  where the other resources merely return nothing.
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
    table "projects"
    repo Demo.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  resource do
    plural_name :projects
  end

  # `estimated_hours` adds up a field that a field policy protects on the
  # tasks, and Ash does not apply that policy to an aggregate: it is
  # protected here.
  field_policies do
    field_policy :estimated_hours do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  # No `column`: the table shows the public attributes, and edits those its
  # `update` action accepts. A project is called by its name where a table
  # shows it as one value: in the "Project" column of /tasks.
  table do
    update_action :update
    label_field :name
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      pagination offset?: true, countable: true, default_limit: 10, required?: false
      prepare build(sort: [name: :asc, id: :asc])
    end

    create :create do
      primary? true
      accept [:name, :description, :status, :starts_on, :budget]
    end

    update :update do
      primary? true
      accept [:name, :description, :status, :starts_on, :budget]
    end

    update :set_status do
      accept [:status]
    end
  end

  policies do
    policy action_type(:read) do
      description "Refused outright, not filtered, when nobody is logged in."
      access_type :strict
      authorize_if actor_present()
    end

    policy action_type(:read) do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end

    policy action_type([:create, :destroy]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action_type(:update) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :member)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
    global? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 2, max_length: 80
    end

    attribute :description, :string, public?: true

    attribute :status, Demo.Tracker.ProjectStatus do
      allow_nil? false
      default :planned
      public? true
    end

    attribute :starts_on, :date, public?: true

    attribute :budget, :decimal do
      public? true
      constraints min: 0
    end

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Demo.Tracker.Organization, allow_nil?: false

    has_many :tasks, Demo.Tracker.Task, public?: true
  end

  aggregates do
    count :task_count, :tasks, public?: true

    count :open_task_count, :tasks do
      public? true
      filter expr(status in [:backlog, :todo, :in_progress, :in_review])
    end

    sum :estimated_hours, :tasks, :estimate_hours, public?: true
    max :next_due_on, :tasks, :due_on, public?: true
  end

  identities do
    identity :unique_name, [:name]
  end
end
