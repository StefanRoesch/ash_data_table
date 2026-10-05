defmodule Host.Work do
  @moduledoc "THROWAWAY PROTOTYPE (#11). Demo domain: tasks with comments, in ETS."
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Host.Work.Task
    resource Host.Work.Comment
  end

  @doc "The table configs the prototype page hands to the grid."
  def task_table do
    %{
      resource: Host.Work.Task,
      label: "Tasks",
      # table level: every column this action accepts is editable
      update_action: :update,
      # column level: overrides the table-level action
      column_actions: %{price: :reprice, status: :set_status},
      nested: %{relationship: :comments, cfg: comment_table()}
    }
  end

  def comment_table do
    %{
      resource: Host.Work.Comment,
      label: "Comments",
      update_action: :update,
      column_actions: %{},
      page_size: 25,
      nested: nil
    }
  end
end

defmodule Host.Work.Status do
  use Ash.Type.Enum, values: [:todo, :in_progress, :review, :done, :blocked]
end

defmodule Host.Work.Priority do
  use Ash.Type.Enum, values: [:low, :medium, :high, :urgent]
end

defmodule Host.Work.Task do
  use Ash.Resource, domain: Host.Work, data_layer: Ash.DataLayer.Ets

  ets do
    private? false
  end

  # The first ten cover every editor type, so `cols=10` is representative.
  @editable [
    :title,
    :priority,
    :progress,
    :done,
    :due_on,
    :assignee,
    :starts_at,
    :description,
    :estimate_hours,
    :spent_hours,
    :billable,
    :budget,
    :team,
    :sprint,
    :story_points,
    :reviewed,
    :reviewer,
    :started_on,
    :finished_on,
    :last_touched_at,
    :notes,
    :label,
    :component,
    :severity,
    :archived,
    :score
  ]

  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true
    attribute :title, :string, public?: true, allow_nil?: false, constraints: [min_length: 3, max_length: 80]
    attribute :status, Host.Work.Status, public?: true, allow_nil?: false, default: :todo
    attribute :priority, Host.Work.Priority, public?: true, allow_nil?: false, default: :medium
    attribute :progress, :integer, public?: true, allow_nil?: false, default: 0, constraints: [min: 0, max: 100]
    attribute :done, :boolean, public?: true, allow_nil?: false, default: false
    attribute :due_on, :date, public?: true
    attribute :price, :decimal, public?: true
    attribute :assignee, :string, public?: true
    attribute :starts_at, :utc_datetime, public?: true
    attribute :description, :string, public?: true
    attribute :estimate_hours, :integer, public?: true, constraints: [min: 0]
    attribute :spent_hours, :integer, public?: true, constraints: [min: 0]
    attribute :billable, :boolean, public?: true, default: true
    attribute :budget, :decimal, public?: true
    attribute :team, :string, public?: true
    attribute :sprint, :integer, public?: true
    attribute :story_points, :integer, public?: true
    attribute :reviewed, :boolean, public?: true, default: false
    attribute :reviewer, :string, public?: true
    attribute :started_on, :date, public?: true
    attribute :finished_on, :date, public?: true
    attribute :last_touched_at, :utc_datetime, public?: true
    attribute :notes, :string, public?: true
    attribute :label, :string, public?: true
    attribute :component, :string, public?: true
    attribute :severity, :integer, public?: true, constraints: [min: 1, max: 5]
    # Not accepted by any update action: a read-only column.
    attribute :external_ref, :string, public?: true
    attribute :archived, :boolean, public?: true, default: false
    attribute :score, :decimal, public?: true
  end

  relationships do
    has_many :comments, Host.Work.Comment, public?: true
  end

  actions do
    defaults [:read]

    create :seed do
      accept [:id, :status, :price, :external_ref | @editable]
    end

    update :update do
      primary? true
      accept @editable
    end

    # Per-column action: only the price.
    update :reprice do
      accept [:price]
      require_atomic? false

      validate compare(:price, greater_than_or_equal_to: 0),
        message: "a price cannot be negative"

      # An error that carries no field at all.
      validate fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :price) do
          %Decimal{} = price ->
            if Decimal.gt?(price, 100_000),
              do: {:error, "repricing above 100000 needs approval"},
              else: :ok

          _ ->
            :ok
        end
      end
    end

    # Per-column action whose validation is about ANOTHER field.
    update :set_status do
      accept [:status]

      validate compare(:progress, greater_than_or_equal_to: 100),
        where: [attribute_equals(:status, :done)],
        message: "must be 100 before the task can be done"
    end
  end
end

defmodule Host.Work.Comment do
  use Ash.Resource, domain: Host.Work, data_layer: Ash.DataLayer.Ets

  ets do
    private? false
  end

  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true
    attribute :body, :string, public?: true, allow_nil?: false, constraints: [min_length: 2]
    attribute :author, :string, public?: true
    attribute :rating, :integer, public?: true, constraints: [min: 1, max: 5]
    attribute :resolved, :boolean, public?: true, allow_nil?: false, default: false
    attribute :posted_on, :date, public?: true
  end

  relationships do
    belongs_to :task, Host.Work.Task, attribute_type: :integer, public?: true, attribute_public?: true
  end

  actions do
    defaults [:read]

    create :seed do
      accept [:id, :body, :author, :rating, :resolved, :posted_on, :task_id]
    end

    update :update do
      primary? true
      accept [:body, :author, :rating, :resolved, :posted_on]
    end
  end
end
