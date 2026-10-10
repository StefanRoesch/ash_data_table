defmodule Demo.Tracker.Deadline do
  @moduledoc """
  What is due by a day: the tasks once more, as a resource of its own over
  the same table, read through an action that requires an argument.

  Its table cannot read until it is told the day, which it asks for in its
  argument line. The second argument has a default, and its input starts
  with it; the third is a list, which is given value by value.
  """
  use Ash.Resource,
    otp_app: :demo,
    domain: Demo.Tracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  alias Demo.Tracker.TaskStatus

  # The table is the tasks'; `Demo.Tracker.Task` owns its migrations.
  postgres do
    table "tasks"
    repo Demo.Repo
    migrate? false
  end

  resource do
    plural_name :deadlines
  end

  table do
    # Requires `by`: until a person has given it, the table says "Fill in Due
    # by to see records." in place of its rows.
    read_action :due

    # What an argument of the read action is called. Without this it is its
    # name in words: "By".
    argument :by do
      label "Due by"
    end

    # A new date that is after the day asked for takes the task out of what
    # the action returns; its row stays until the table reads again.
    update_action :reschedule
    label_field :title

    column :title
    column :status
    column :due_on
    column :tags
    column :assignee

    column :comment_count do
      label "Comments"
    end

    relationship :comments
  end

  actions do
    read :read do
      primary? true
      pagination offset?: true, countable: true, default_limit: 25, required?: false
    end

    read :due do
      # the table cannot read without it
      argument :by, :date, allow_nil?: false
      # has a default, which its input starts with
      argument :include_done?, :boolean, allow_nil?: false, default: false
      # a list, given value by value: the tasks that have one of these tags
      argument :tags, {:array, :string}

      filter expr(
               due_on <= ^arg(:by) and
                 (^arg(:include_done?) or status in ^TaskStatus.open()) and
                 (is_nil(^arg(:tags)) or
                    fragment("? && ?", tags, type(^arg(:tags), {:array, :string})))
             )

      pagination offset?: true, countable: true, default_limit: 25, required?: false
      prepare build(sort: [due_on: :asc, id: :asc])
    end

    update :reschedule do
      accept [:due_on]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end

    policy action_type(:update) do
      forbid_if actor_attribute_equals(:role, :viewer)
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(assignee_id == ^actor(:id) or reporter_id == ^actor(:id))
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
    global? true
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :status, TaskStatus do
      allow_nil? false
      public? true
    end

    attribute :due_on, :date, public?: true
    attribute :tags, {:array, :string}, public?: true
    attribute :reporter_id, :uuid
  end

  relationships do
    belongs_to :organization, Demo.Tracker.Organization, allow_nil?: false

    belongs_to :assignee, Demo.Tracker.User do
      public? true
      attribute_public? true
    end

    has_many :comments, Demo.Tracker.Comment do
      destination_attribute :task_id
      public? true
    end
  end

  aggregates do
    count :comment_count, :comments, public?: true
  end
end
