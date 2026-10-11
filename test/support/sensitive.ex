defmodule AshTable.Test.Sensitive.Login do
  @moduledoc "An embedded resource with a sensitive attribute."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :user, :string, public?: true
    attribute :password, :string, public?: true, sensitive?: true
    attribute :pin, :integer, public?: true, sensitive?: true, writable?: false
  end
end

defmodule AshTable.Test.Sensitive.Shown do
  @moduledoc "An embedded resource whose sensitive attribute nobody gives."
  use Ash.Resource, data_layer: :embedded

  actions do
    defaults [:read, :destroy, create: [:user], update: [:user]]
  end

  attributes do
    attribute :user, :string, public?: true
    attribute :password, :string, public?: true, sensitive?: true
  end
end

defmodule AshTable.Test.Sensitive.Owner do
  @moduledoc "What a vault belongs to: called by its name."
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  table do
    label_field :name
  end

  actions do
    defaults [:read, create: [:name, :badge]]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :badge, :string, public?: true, sensitive?: true
  end
end

defmodule AshTable.Test.Sensitive do
  @moduledoc """
  A vault: one sensitive column per kind of field a table has a cell for,
  and actions with sensitive inputs. The actors of its tests are maps:
  `%{role: :admin}`.
  """
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  alias AshTable.Test.Sensitive.{Login, Owner, Shown}

  table do
    update_action :update
    create_action :create

    column :name
    column :token
    column :pin
    column :locked
    column :expires_on
    column :codes
    column :login
    column :shown
    column :sealed
    column :token_length
    column :shout
    column :owner

    column :shout do
      as :whisper
      arguments suffix: "?"
    end

    action :rotate
    action :stamp
    action :reissue

    action :destroy do
      confirm false
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :token, :pin, :locked]
      argument :passphrase, :string, sensitive?: true
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:name, :token, :pin, :locked, :expires_on, :codes, :login, :shown, :sealed]

      validate match(:token, ~r/^[a-z0-9-]*$/) do
        message "must be lower case"
      end
    end

    # an action that takes the token, and not without a value
    update :reissue do
      require_atomic? false
      accept [:token, :pin]
      require_attributes [:token]
    end

    # a sensitive attribute and sensitive arguments, of every kind of input
    update :rotate do
      require_atomic? false
      accept [:token, :locked]
      argument :passphrase, :string, sensitive?: true, allow_nil?: false
      argument :count, :integer, sensitive?: true
      argument :on, :date, sensitive?: true
      argument :note, :string

      validate fn changeset, _context ->
        if Ash.Changeset.get_argument(changeset, :passphrase) == "wrong",
          do: {:error, field: :passphrase, message: "is not the passphrase"},
          else: :ok
      end
    end

    # an action that cannot be run from a table: it requires a sensitive
    # input that cannot be typed hidden
    update :lock do
      require_atomic? false
      argument :until, :date, sensitive?: true, allow_nil?: false
    end

    update :stamp do
      require_atomic? false
      accept []
      change set_attribute(:name, "stamped")
    end
  end

  # a vault that is pinned does not give up its pin, whatever updates it
  validations do
    validate present(:pin) do
      on [:update]
      where attribute_equals(:name, "pinned")
      message "stays on a pinned vault"
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :sealed do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :pin do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(name == "open")
    end

    field_policy :* do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :token, :string, public?: true, sensitive?: true
    attribute :pin, :integer, public?: true, sensitive?: true
    attribute :locked, :boolean, public?: true, sensitive?: true
    attribute :expires_on, :date, public?: true, sensitive?: true
    attribute :codes, {:array, :string}, public?: true, sensitive?: true
    # a sensitive attribute made of fields, and plain ones with a sensitive field
    attribute :login, Login, public?: true, sensitive?: true
    attribute :shown, Shown, public?: true
    attribute :logins, {:array, Login}, public?: true
    attribute :sealed, :string, public?: true, sensitive?: true
  end

  relationships do
    belongs_to :owner, Owner, public?: true
  end

  calculations do
    calculate :token_length, :integer, expr(string_length(token)) do
      public? true
      sensitive? true
    end

    calculate :shout, :string, expr(token <> ^arg(:suffix)) do
      public? true
      sensitive? true
      argument :suffix, :string, default: "!"
    end
  end
end
