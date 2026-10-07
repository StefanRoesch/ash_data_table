defmodule Phx.Domain do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Phx.Thing
  end
end

defmodule Phx.Thing do
  use Ash.Resource, domain: Phx.Domain, data_layer: Ash.DataLayer.Ets, authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :secret, :string, public?: true
  end

  actions do
    defaults [:read]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :secret do
      authorize_if actor_attribute_equals(:admin, true)
    end

    field_policy :* do
      authorize_if always()
    end
  end
end

defmodule Phx.ProbeController do
  use Phoenix.Controller, formats: [:html]

  def show(conn, _params) do
    loaded = :code.is_loaded(Ash.Policy.Authorizer) != false
    result = Ash.can_see_fields({Phx.Thing, :read}, %{admin: false}, [:name, :secret])
    text(conn, "mode=#{:code.get_mode()} authorizer_loaded_before=#{loaded} member can_see_fields=#{inspect(result)}\n")
  end
end

defmodule Phx.Router do
  use Phoenix.Router

  get "/probe", Phx.ProbeController, :show
end

defmodule Phx.Endpoint do
  use Phoenix.Endpoint, otp_app: :phx

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Phx.Router
end

defmodule Phx.Application do
  use Application

  def start(_type, _args) do
    Supervisor.start_link([Phx.Endpoint], strategy: :one_for_one, name: Phx.Supervisor)
  end
end
# changed 1791364085
