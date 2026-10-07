defmodule Demo.Tracker.Label do
  @moduledoc "A label tasks can carry. Its read is not paginated."
  use Ash.Resource,
    otp_app: :demo,
    domain: Demo.Tracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    # The default sort of a table lives on its read action, on purpose.
    primary_read_warning?: false

  postgres do
    table "labels"
    repo Demo.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  resource do
    plural_name :labels
  end

  # No `column`: the table shows the public attributes. A label is called by
  # its name: over the tasks of one label, in their full view.
  table do
    label_field :name
  end

  actions do
    defaults [:destroy, create: [:name, :colour], update: [:name, :colour]]

    read :read do
      primary? true
      prepare build(sort: [name: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end

    policy action_type([:create, :update, :destroy]) do
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
      constraints min_length: 1, max_length: 30
    end

    attribute :colour, :string do
      allow_nil? false
      default "#64748b"
      public? true
      constraints match: ~r/^#[0-9a-f]{6}$/
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Demo.Tracker.Organization, allow_nil?: false

    many_to_many :tasks, Demo.Tracker.Task do
      through Demo.Tracker.TaskLabel
      source_attribute_on_join_resource :label_id
      destination_attribute_on_join_resource :task_id
      public? true
    end
  end

  aggregates do
    count :task_count, :tasks, public?: true
  end

  identities do
    identity :unique_name, [:name]
  end
end
