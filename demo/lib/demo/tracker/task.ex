defmodule Demo.Tracker.Task do
  @moduledoc """
  The resource the demo's main table shows. It deliberately carries one of
  everything a table has to cope with; see the demo's README for the list.
  """
  use Ash.Resource,
    otp_app: :demo,
    domain: Demo.Tracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    # The default sort of a table lives on its read action, on purpose.
    primary_read_warning?: false

  alias Demo.Tracker.TaskStatus

  postgres do
    table "tasks"
    repo Demo.Repo

    references do
      reference :organization, on_delete: :delete
      reference :project, on_delete: :delete
      reference :assignee, on_delete: :nilify
      reference :reporter, on_delete: :delete
    end

    # The tenant attribute is put in front of each index by ash_postgres.
    custom_indexes do
      index [:inserted_at, :id]
      index [:due_on, :id]
      index [:project_id]
      index [:assignee_id]
    end
  end

  resource do
    plural_name :tasks
  end

  field_policies do
    field_policy :external_ref do
      description "Actor only: admins."
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :estimate_hours do
      description "Record-dependent: admins, or the task's own assignee."
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(assignee_id == ^actor(:id))
    end

    field_policy :* do
      description "Everything else is visible to whoever can read the record."
      authorize_if always()
    end
  end

  # The table at /tasks: chosen columns in a chosen order. Its page size and
  # default sort are those of the primary read action. Every column the
  # resource allows to be filtered has a filter, unless switched off here.
  table do
    # Inline editing: every column whose attribute `update` accepts can be
    # edited in place, unless the column says otherwise.
    update_action :update

    # What a task is called where a table shows it as one value.
    label_field :title

    # text
    column :title

    # enums, each shown as a badge. A change of state asks first.
    column :status do
      label "State"
      confirm "Change the state of this task?"
      component AshTable.Components.Badge
    end

    # edited through an action of its own
    column :priority do
      update_action :reprioritise
      component AshTable.Components.Badge
    end

    # numbers: one that is always there and one that can be empty. Progress
    # has its own action, which also starts a task that is still to do. It
    # is shown as a bar and edited with a slider.
    column :progress do
      update_action :set_progress
      component DemoWeb.Cells.Progress
    end

    # the demo's own component: the number with its unit
    column :estimate_hours do
      component DemoWeb.Cells.Hours
    end

    # a boolean
    column :billable?
    # a date and a datetime, both of which can be empty
    column :due_on
    column :completed_at
    # an expression calculation: sortable and filterable, never editable
    column :overdue?

    # an aggregate: sortable and filterable, never editable
    column :comment_count do
      label "Comments"
    end

    # a calculation computed in Elixir: the resource can neither sort nor
    # filter by it
    column :headline

    # A calculation that takes an argument, twice. The first column fixes
    # the argument. The second asks the person for it, in the argument line
    # above the rows, and starts with 30; being the second column of the same
    # calculation, it has a name of its own (`as`). Each is sorted and
    # filtered by with its own argument.
    column :due_within? do
      label "Due within 7 days"
      arguments days: 7
    end

    column :due_within? do
      as :due_within
      ask :days, default: 30
    end

    # `update` accepts it, the table does not offer it
    column :external_ref do
      update_action false
    end

    # long text, with sorting and filtering switched off
    column :description do
      sortable? false
      filterable? false
    end

    # Arrays, shown as their values and edited as a whole: text value by
    # value, and enum values as multiple choice. Neither sorted nor
    # filtered by.
    column :tags
    column :checks

    # A map that declares its fields: shown on one line, and edited in the
    # side panel, field by field. Neither sorted nor filtered by. A change
    # asks first, when Save is used.
    column :recurrence do
      label "Repeats"
      confirm "Change how often this task comes round?"
    end

    # no update action accepts it
    column :inserted_at

    # Reference cells: each names a belongs-to relationship and shows the
    # related record's label, the `label_field` of that resource's table, in
    # place of the key. Neither sorted nor filtered by.
    #
    # A reference cell is edited where the column's update action accepts
    # the relationship's foreign key: a person chooses the related record
    # from that resource's own table, in the picker. `update` accepts
    # `project_id` and `assignee_id`. Moving a task asks first.
    column :project do
      confirm "Move this task to another project?"
    end

    column :assignee

    # No update action accepts `reporter_id`: read-only.
    column :reporter do
      label "Reported by"
    end

    # What a row can be expanded into: these relationships, in this order,
    # each on a line of its own that opens the nested table of the related
    # records. Without any `relationship` here, a row would offer every public
    # relationship whose destination has a table, under its own name.
    relationship :comments

    # two has-ones that each pick one of many: the one their own sort puts first
    relationship :first_comment

    relationship :latest_comment do
      label "Newest comment"
    end

    # many-to-many, to a destination that is not paginated
    relationship :labels
    # belongs-to: a nested table of one row
    relationship :project
    relationship :assignee

    relationship :reporter do
      label "Reported by"
    end

    # Row actions: a button each, in this order, in the last column of the
    # table. `archive` has no inputs and runs when its button is used.
    action :archive

    # A required argument and an attribute: the button opens the action panel.
    action :reassign

    # One attribute, which the panel shows with the task's progress in it.
    action :set_progress

    # A destroy action asks first, or says that it does not (`confirm false`).
    action :destroy do
      confirm "Delete this task? This cannot be undone."
    end

    # An argument that the action hands to a relationship: the panel lists
    # the task's labels, and "Choose" opens the table of the labels, in which
    # any number of them is selected.
    action :set_labels

    # The "New task" button, on the line of the table's name.
    create_action :create
  end

  actions do
    # Offset AND keyset, countable. It takes an argument that may be left
    # empty: a search term, which a table of the tasks asks for in its
    # argument line, wherever it is shown.
    read :read do
      primary? true

      # case-insensitive, as a `:ci_string` compares; its input counts
      # what is typed, as every text with a `max_length` does
      argument :search, :ci_string, constraints: [max_length: 60]

      filter expr(
               is_nil(^arg(:search)) or contains(title, ^arg(:search)) or
                 contains(description, ^arg(:search))
             )

      pagination offset?: true,
                 keyset?: true,
                 countable: true,
                 default_limit: 25,
                 max_page_size: 100,
                 required?: false

      prepare build(sort: [inserted_at: :desc, id: :desc])
    end

    read :offset_only do
      pagination offset?: true, countable: true, default_limit: 25, max_page_size: 100
      prepare build(sort: [inserted_at: :desc, id: :desc])
    end

    read :keyset_only do
      pagination keyset?: true, default_limit: 25, max_page_size: 100
      prepare build(sort: [inserted_at: :desc, id: :desc])
    end

    # No pagination at all: a table on this action loads everything.
    read :unpaginated do
      prepare build(sort: [title: :asc, id: :asc])
    end

    # A table with its own page size and default sort gets its own read action.
    read :open do
      filter expr(status in ^TaskStatus.open())

      pagination offset?: true,
                 keyset?: true,
                 countable: true,
                 default_limit: 10,
                 max_page_size: 100

      prepare build(sort: [due_on: :asc_nils_last, id: :asc])
    end

    create :create do
      primary? true

      accept [
        :title,
        :description,
        :status,
        :priority,
        :progress,
        :estimate_hours,
        :billable?,
        :due_on,
        :external_ref,
        :project_id,
        :assignee_id,
        :tags,
        :checks,
        :recurrence
      ]

      change relate_actor(:reporter)
    end

    update :update do
      primary? true

      accept [
        :title,
        :description,
        :status,
        :priority,
        :progress,
        :estimate_hours,
        :billable?,
        :due_on,
        :completed_at,
        :external_ref,
        :project_id,
        :assignee_id,
        :tags,
        :checks,
        :recurrence
      ]
    end

    # Leaves a trace of its own, so that it can be told apart from `update`.
    update :reprioritise do
      accept [:priority]
      change set_attribute(:internal_note, "Reprioritised")
    end

    # Reporting progress on a task that is still to do starts it.
    update :set_progress do
      accept [:progress]

      change set_attribute(:status, :in_progress) do
        where attribute_equals(:status, :todo)
      end
    end

    # An action with a required argument: it cannot serve inline editing.
    update :reassign do
      accept [:assignee_id]

      argument :reason, :string do
        allow_nil? false
        constraints min_length: 3, max_length: 200
      end

      change set_attribute(:internal_note, arg(:reason))
    end

    update :archive do
      accept []
      change set_attribute(:status, :archived)
    end

    # The argument holds the keys of labels, and the change hands them to
    # the relationship: these labels and no others. A table lets a person
    # choose them from the table of the labels.
    update :set_labels do
      accept []
      require_atomic? false

      argument :labels, {:array, :uuid}, allow_nil?: false

      change manage_relationship(:labels, type: :append_and_remove)
    end

    destroy :destroy do
      primary? true
    end
  end

  policies do
    policy action_type(:read) do
      description """
      Filtered: everyone with an organization sees all its tasks, and
      nobody else's. Without an actor the filter matches nothing.
      """

      authorize_if expr(organization_id == ^actor(:organization_id))
    end

    policy action_type(:create) do
      description "Depends on the actor only: admins and members."
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :member)
    end

    policy action_type([:update, :destroy]) do
      description """
      Admins may run every action and viewers none (actor only). A member may
      change only the tasks they are assigned to or reported (record-dependent).
      """

      forbid_if actor_attribute_equals(:role, :viewer)
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(assignee_id == ^actor(:id) or reporter_id == ^actor(:id))
    end
  end

  validations do
    validate compare(:progress, greater_than_or_equal_to: 100) do
      on [:create, :update]
      where attribute_equals(:status, :done)
      message "must be 100 when the task is done"
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
      constraints min_length: 3, max_length: 120
    end

    # Long text.
    attribute :description, :string, public?: true

    attribute :status, Demo.Tracker.TaskStatus do
      allow_nil? false
      default :todo
      public? true
    end

    attribute :priority, Demo.Tracker.TaskPriority do
      allow_nil? false
      default :medium
      public? true
    end

    attribute :progress, :integer do
      allow_nil? false
      default 0
      public? true
      constraints min: 0, max: 100
    end

    attribute :estimate_hours, :decimal do
      public? true
      constraints min: 0
    end

    attribute :billable?, :boolean do
      source :billable
      allow_nil? false
      default false
      public? true
    end

    attribute :due_on, :date, public?: true
    attribute :completed_at, :utc_datetime, public?: true

    # Public, and an admin's alone by its field policy. Not `sensitive?`:
    # a table masks the cells of a sensitive column and neither sorts nor
    # filters by it (see `budget` on the project), and this column is here
    # to be sorted and filtered by those who may see it.
    attribute :external_ref, :string do
      public? true
      constraints max_length: 40
    end

    # An array of text: at most five tags, each of two to twenty characters.
    attribute :tags, {:array, :string} do
      allow_nil? false
      default []
      public? true
      constraints max_length: 5, items: [min_length: 2, max_length: 20]
    end

    # An array of enum values.
    attribute :checks, {:array, Demo.Tracker.TaskCheck} do
      allow_nil? false
      default []
      public? true
    end

    # A map that declares its fields: how often a task comes round again.
    attribute :recurrence, :map do
      public? true

      constraints fields: [
                    every: [type: :integer, allow_nil?: false, constraints: [min: 1, max: 365]],
                    unit: [
                      type: :atom,
                      allow_nil?: false,
                      constraints: [one_of: [:day, :week, :month]]
                    ],
                    until: [type: :date]
                  ]
    end

    # Private on purpose: never a column.
    attribute :internal_note, :string

    # A timestamp made public, and one left private.
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Demo.Tracker.Organization, allow_nil?: false

    belongs_to :project, Demo.Tracker.Project do
      allow_nil? false
      public? true
      attribute_public? true
    end

    belongs_to :assignee, Demo.Tracker.User do
      public? true
      attribute_public? true
    end

    belongs_to :reporter, Demo.Tracker.User do
      allow_nil? false
      public? true
      attribute_public? true
    end

    has_many :comments, Demo.Tracker.Comment, public?: true

    has_one :latest_comment, Demo.Tracker.Comment do
      from_many? true
      sort inserted_at: :desc
      public? true
    end

    # The other end: its sort is the opposite of the one the comments' read
    # action prepares.
    has_one :first_comment, Demo.Tracker.Comment do
      from_many? true
      sort inserted_at: :asc
      public? true
    end

    has_many :task_labels, Demo.Tracker.TaskLabel

    many_to_many :labels, Demo.Tracker.Label do
      through Demo.Tracker.TaskLabel
      source_attribute_on_join_resource :task_id
      destination_attribute_on_join_resource :label_id
      public? true
    end
  end

  calculations do
    # An expression without arguments: sortable and filterable in the database.
    calculate :overdue?,
              :boolean,
              expr(not is_nil(due_on) and due_on < today() and status in ^TaskStatus.open()),
              public?: true

    # A module calculation, computed in Elixir.
    calculate :headline, :string, Demo.Tracker.Calculations.Headline, public?: true

    # A calculation with a required argument: a column of it has to say what
    # the argument is, or ask for it.
    calculate :due_within?,
              :boolean,
              expr(not is_nil(due_on) and due_on <= date_add(today(), ^arg(:days), :day)) do
      public? true

      argument :days, :integer do
        allow_nil? false
        constraints min: 0
      end
    end

    # Private on purpose.
    calculate :stale?, :boolean, expr(updated_at < ago(90, :day))
  end

  aggregates do
    count :comment_count, :comments, public?: true
    max :last_commented_at, :comments, :inserted_at, public?: true
    count :label_count, :labels, public?: true
  end
end
