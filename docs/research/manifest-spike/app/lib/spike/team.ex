defmodule Spike.Accounts.Team do
  use Ash.Resource, domain: Spike.Accounts, data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true, allow_nil?: false
    # RELOAD-MARKER
  end

  actions do
    defaults [:read, :destroy, create: [:name], update: [:name]]
  end
end
