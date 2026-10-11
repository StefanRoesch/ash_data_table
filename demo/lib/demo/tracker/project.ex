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

  require Ash.Query

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
  #
  # `budget` is for those who work on the project: admins and members. A
  # viewer has no "Budget" column. That is access. That the attribute is
  # `sensitive?` is something else: those who may see it see a mask, until
  # they ask for the value of one cell.
  field_policies do
    field_policy :estimated_hours do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :budget do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :member)
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

    # one input, a choice: the panel shows it with the project's state in it
    action :set_status

    # One input, which is sensitive: the panel hides what is typed and
    # starts empty. Left empty it changes nothing, so the panel has a button
    # that empties the budget of a project that has one: "Clear".
    action :set_budget

    # A project is deleted with all its tasks: one at a time, from its own
    # row. `bulk? false` keeps the action off the line of the selected rows.
    action :destroy do
      confirm "Delete this project, with all its tasks?"
      bulk? false
    end

    # A generic action with two key arguments. `record_argument` names the
    # one the table gives: the project of the row. Nothing in Ash says
    # which resource the other key belongs to, so `reference` says it: the
    # person chooses the assignee from the table of the people, in the
    # picker, and types no key.
    action :assign_open_tasks do
      record_argument :project_id
      reference :assignee, Demo.Tracker.User
    end

    # "New project"; and "New task" on the Tasks line of a project, where
    # the table gives `project_id` itself
    create_action :create
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
      accept [:name, :description, :status, :starts_on, :budget, :client, :milestones]
    end

    update :update do
      primary? true
      # An embedded resource is cast through its own actions, which is
      # nothing a single statement can do.
      require_atomic? false
      accept [:name, :description, :status, :starts_on, :budget, :client, :milestones]
    end

    update :set_status do
      accept [:status]
    end

    update :set_budget do
      accept [:budget]
    end

    # Gives the open tasks of a project that nobody has to one person, and
    # returns how many those were. It reads and writes as the person who
    # runs it, in their organization.
    action :assign_open_tasks, :integer do
      description "Gives the open tasks of a project that have no assignee to one person."
      transaction? true

      argument :project_id, :uuid, allow_nil?: false
      argument :assignee, :uuid, allow_nil?: false

      run fn input, context ->
        opts = Ash.Context.to_opts(context)
        %{project_id: project_id, assignee: assignee} = input.arguments

        tasks =
          Demo.Tracker.Task
          |> Ash.Query.for_read(:unpaginated, %{}, opts)
          |> Ash.Query.filter(
            project_id == ^project_id and is_nil(assignee_id) and
              status in ^Demo.Tracker.TaskStatus.open()
          )
          |> Ash.read!(opts)

        Enum.each(tasks, &Ash.update!(&1, %{assignee_id: assignee}, opts))

        {:ok, length(tasks)}
      end
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

    # A generic action takes no record, so its policy looks at the actor.
    policy action(:assign_open_tasks) do
      authorize_if actor_attribute_equals(:role, :admin)
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

    # Sensitive: its cells are masked ("••••••") until somebody asks for
    # one, and the table neither sorts nor filters by it.
    attribute :budget, :decimal do
      public? true
      sensitive? true
      constraints min: 0
    end

    # An embedded resource, with another one inside it: shown on one line,
    # edited in the side panel.
    attribute :client, Demo.Tracker.Client, public?: true

    # An array of embedded resources.
    attribute :milestones, {:array, Demo.Tracker.Milestone} do
      allow_nil? false
      default []
      public? true
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
