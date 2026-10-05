defmodule Demo.Tracker.TaskLabel do
  @moduledoc "The join between tasks and labels."
  use Ash.Resource,
    otp_app: :demo,
    domain: Demo.Tracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "task_labels"
    repo Demo.Repo

    references do
      reference :organization, on_delete: :delete
      reference :task, on_delete: :delete
      reference :label, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, create: [:task_id, :label_id]]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end

    policy action_type([:create, :destroy]) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :member)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
    global? true
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
