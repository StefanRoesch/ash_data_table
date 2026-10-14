defmodule AshDataTable.Test.Guarded do
  @moduledoc """
  A resource for the tests of what a table shows and lets edit, person by
  person: fields nobody but an admin sees, a field seen on a person's own
  records only, and update actions a person may always, sometimes or never
  run.

  The actors of these tests are maps: `%{id: 1, role: :admin}`.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    # admins only
    attribute :secret, :string, public?: true
    # admins, and the owner of the record
    attribute :salary, :integer, public?: true
    attribute :rating, :integer, public?: true
    attribute :flagged, :boolean, public?: true
    attribute :owner_id, :integer, public?: true
  end

  calculations do
    # admins only, as the field it is computed from
    calculate :secret_shouted, :string, expr(secret <> "!"), public?: true
  end

  actions do
    defaults [:read]

    update :update do
      primary? true
      accept [:title, :secret, :salary]
    end

    update :rate do
      accept [:rating]
    end

    update :flag do
      accept [:flagged]
    end

    create :create do
      accept [:title, :secret, :salary]
    end

    destroy :destroy
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:update) do
      description "Admins always, viewers never, anyone else on their own records."
      forbid_if actor_attribute_equals(:role, :viewer)
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(owner_id == ^actor(:id))
    end

    policy action(:rate) do
      description "Admins only."
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action(:flag) do
      description "Anyone, logged in or not."
      authorize_if always()
    end

    policy action(:create) do
      description "Admins and members."
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :member)
    end

    policy action(:destroy) do
      description "Admins only."
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  field_policies do
    field_policy [:secret, :secret_shouted] do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :salary do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(owner_id == ^actor(:id))
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    update_action :update

    column :title
    column :secret

    column :salary do
      confirm "Change the salary?"
    end

    column :rating do
      update_action :rate
    end

    column :flagged do
      update_action :flag
    end

    column :secret_shouted

    action :update
    action :rate
    action :flag

    action :destroy do
      confirm "Delete this?"
    end

    create_action(:create)
  end
end

defmodule AshDataTable.Test.Scope do
  @moduledoc "A scope, as a host application would define one."
  defstruct [:user, :tenant]

  defimpl Ash.Scope.ToOpts do
    def get_actor(%{user: user}), do: {:ok, user}
    def get_tenant(%{tenant: tenant}), do: {:ok, tenant}
    def get_context(_scope), do: :error
    def get_tracer(_scope), do: :error
    def get_authorize?(_scope), do: :error
  end
end
