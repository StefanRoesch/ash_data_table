defmodule Demo.Tracker.TaskLabel do
  @moduledoc "The join between tasks and labels."
  use Ash.Resource,
    otp_app: :demo,
    domain: Demo.Tracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    # the default sort is a preparation of the primary read action, on purpose
    primary_read_warning?: false

  postgres do
    table "task_labels"
    repo Demo.Repo

    references do
      reference :organization, on_delete: :delete
      reference :task, on_delete: :delete
      reference :label, on_delete: :delete
    end
  end

  resource do
    plural_name :task_labels
  end

  # No columns declared: the two parts of the key, and the note. Every row is
  # found, shown again and saved by both parts of its key together.
  table do
    update_action :update
  end

  actions do
    defaults [:destroy, create: [:task_id, :label_id, :note], update: [:note]]

    read :read do
      primary? true
      pagination offset?: true, default_limit: 25, countable: true
      prepare build(sort: [task_id: :asc, label_id: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end

    policy action_type([:create, :update, :destroy]) do
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
    # Why the task has the label; the one thing of a row that can be edited.
    attribute :note, :string, public?: true
  end

  relationships do
    belongs_to :organization, Demo.Tracker.Organization, allow_nil?: false

    belongs_to :task, Demo.Tracker.Task do
      primary_key? true
      allow_nil? false
      public? true
      attribute_public? true
    end

    belongs_to :label, Demo.Tracker.Label do
      primary_key? true
      allow_nil? false
      public? true
      attribute_public? true
    end
  end
end
