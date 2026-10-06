defmodule Demo.Support.Gate do
  @moduledoc """
  A policy check a test can flip while a page is open: it passes while the
  gate is open. It stands for whatever a resource's policies look at besides
  the actor, which can change under a session.
  """
  use Ash.Policy.SimpleCheck

  def open, do: :persistent_term.put(__MODULE__, true)
  def close, do: :persistent_term.put(__MODULE__, false)

  @impl true
  def describe(_opts), do: "the gate is open"

  @impl true
  def match?(_actor, _context, _opts), do: :persistent_term.get(__MODULE__, true)
end

defmodule Demo.Support.Scope do
  @moduledoc "A scope, as a host application would define one."
  defstruct [:user, :organization]

  defimpl Ash.Scope.ToOpts do
    def get_actor(%{user: user}), do: {:ok, user}
    def get_tenant(%{organization: organization}), do: {:ok, organization}
    def get_context(_scope), do: :error
    def get_tracer(_scope), do: :error
    def get_authorize?(_scope), do: :error
  end
end

defmodule Demo.Support.Guarded do
  @moduledoc """
  A domain whose tables find who is asking under names of its own. Its
  resources exist for the tests only and keep their records in memory.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshTable.Domain]

  table do
    scope_assign :viewer_scope
    actor_assign :reader
    tenant_assign :reader_organization
  end

  resources do
    resource Demo.Support.Guarded.Note
  end
end

defmodule Demo.Support.Guarded.Note do
  @moduledoc """
  A note of one person in one organization. People read their own notes only,
  and nobody reads any while the gate is closed: that read is refused
  outright.
  """
  use Ash.Resource,
    domain: Demo.Support.Guarded,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  table do
    update_action :update

    column :title
    column :owner
  end

  actions do
    defaults [:read, create: [:title, :owner, :organization], update: [:title]]
  end

  policies do
    policy action_type(:read) do
      access_type :strict
      authorize_if Demo.Support.Gate
    end

    policy action_type(:read) do
      authorize_if expr(owner == ^actor(:name))
    end

    policy action_type(:update) do
      authorize_if actor_present()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization
    global? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :owner, :string, public?: true
    attribute :organization, :string, public?: true
  end
end

defmodule Demo.Support.Unguarded do
  @moduledoc """
  A domain whose tables do not authorize. Its resource exists for the tests
  only and keeps its records in memory.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshTable.Domain]

  table do
    authorize? false
  end

  resources do
    resource Demo.Support.Unguarded.Note
  end
end

defmodule Demo.Support.Unguarded.Note do
  @moduledoc """
  A note whose policies allow nobody anything: no read, no field, no update.
  """
  use Ash.Resource,
    domain: Demo.Support.Unguarded,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  field_policies do
    field_policy :* do
      forbid_if always()
    end
  end

  table do
    update_action :update

    column :title
    column :secret
  end

  actions do
    defaults [:read, create: [:title, :secret], update: [:title, :secret]]
  end

  policies do
    policy always() do
      access_type :strict
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :secret, :string, public?: true
  end
end

defmodule DemoWeb.Support.Assigns do
  @moduledoc """
  An `on_mount` hook for the tests: it assigns to the socket what the session
  holds under `"assigns"`, so that a test decides which assigns a mounted
  table finds, and under which names.
  """
  def on_mount(:default, _params, session, socket) do
    {:cont, Phoenix.Component.assign(socket, Map.get(session, "assigns", %{}))}
  end
end
