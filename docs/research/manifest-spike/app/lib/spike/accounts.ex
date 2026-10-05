defmodule Spike.Accounts do
  use Ash.Domain, otp_app: :spike

  resources do
    resource Spike.Accounts.User
    resource Spike.Accounts.Team
  end
end

defmodule Spike.Accounts.User do
  use Ash.Resource, domain: Spike.Accounts, data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :ci_string, public?: true, allow_nil?: false
    attribute :role, :atom, public?: true, default: :staff, constraints: [one_of: [:staff, :admin]]
    attribute :born_on, :date, public?: true
  end

  relationships do
    has_many :products, Spike.Shop.Product, public?: true, destination_attribute: :owned_by_id
    has_many :reviews, Spike.Shop.Review, public?: true, destination_attribute: :author_id
  end

  actions do
    defaults [:read, :destroy, create: [:email, :role, :born_on], update: [:email, :born_on]]

    update :promote do
      accept []
      change set_attribute(:role, :admin)
    end
  end
end
