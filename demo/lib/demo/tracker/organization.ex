defmodule Demo.Tracker.Organization do
  @moduledoc """
  The tenant. Every other tracker resource except `User` is multitenant on
  `organization_id`.
  """
  use Ash.Resource,
    otp_app: :demo,
    domain: Demo.Tracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    # The default sort of a table lives on its read action, on purpose.
    primary_read_warning?: false

  postgres do
    table "organizations"
    repo Demo.Repo
  end

  actions do
    defaults [:destroy, create: [:name, :slug], update: [:name, :slug]]

    read :read do
      primary? true
      prepare build(sort: [name: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      description "A user sees their own organization only."
      authorize_if expr(id == ^actor(:organization_id))
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
      constraints min_length: 1, max_length: 80
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
      constraints match: ~r/^[a-z0-9-]+$/, max_length: 40
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :users, Demo.Tracker.User, public?: true
    has_many :projects, Demo.Tracker.Project, public?: true
  end

  aggregates do
    count :user_count, :users, public?: true
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
