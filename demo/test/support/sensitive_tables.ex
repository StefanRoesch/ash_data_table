defmodule Demo.Support.Secrets do
  @moduledoc """
  A domain for the tests of sensitive columns, where the demo's own tables
  do not have the case: a sensitive column of every kind, a sensitive input
  of an action, and a sensitive field inside a value. Its resources exist
  for the tests only and keep their records in memory.

  The actors of these tests are maps: `%{role: :admin}`.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshTable.Domain]

  table do
    actor_assign :reader
  end

  resources do
    resource Demo.Support.Secrets.Safe
  end
end

defmodule Demo.Support.Secrets.Combination do
  @moduledoc "An embedded resource with a sensitive attribute that nobody gives."
  use Ash.Resource, data_layer: :embedded

  actions do
    defaults [:read, :destroy, create: [:dial], update: [:dial]]
  end

  attributes do
    attribute :dial, :string, public?: true
    attribute :digits, :string, public?: true, sensitive?: true
  end
end

defmodule Demo.Support.Secrets.Safe do
  @moduledoc """
  A safe. Its token and its PIN are sensitive and edited; whether it is
  locked is sensitive and not edited, as a box cannot hide what it holds.
  The PIN is an admin's, and everybody's on the safe called "open"; the
  seal is an admin's alone.
  """
  use Ash.Resource,
    domain: Demo.Support.Secrets,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  alias Demo.Support.Secrets.Combination

  field_policies do
    field_policy :seal do
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

  table do
    update_action :update
    create_action :create

    column :name
    column :token
    column :pin
    column :locked
    column :seal
    column :token_length
    column :combination

    action :rotate

    action :destroy do
      confirm false
    end
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      pagination offset?: true, countable: true, default_limit: 5, required?: false
      prepare build(sort: [name: :asc])
    end

    create :create do
      accept [:name, :token, :pin]
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:name, :token, :pin, :locked, :seal, :combination]

      validate match(:token, ~r/^[a-z0-9-]*$/) do
        message "must be lower case"
      end
    end

    # a sensitive attribute and a sensitive argument, beside a plain one
    update :rotate do
      require_atomic? false
      accept [:token]
      argument :passphrase, :string, sensitive?: true, allow_nil?: false
      argument :note, :string

      validate fn changeset, _context ->
        if Ash.Changeset.get_argument(changeset, :passphrase) == "wrong",
          do: {:error, field: :passphrase, message: "is not the passphrase"},
          else: :ok
      end

      change fn changeset, _context ->
        case Ash.Changeset.get_argument(changeset, :note) do
          nil -> changeset
          note -> Ash.Changeset.force_change_attribute(changeset, :name, note)
        end
      end
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :token, :string, public?: true, sensitive?: true
    attribute :pin, :integer, public?: true, sensitive?: true
    attribute :locked, :boolean, public?: true, sensitive?: true
    attribute :seal, :string, public?: true, sensitive?: true
    attribute :combination, Combination, public?: true
  end

  calculations do
    calculate :token_length, :integer, expr(string_length(token)) do
      public? true
      sensitive? true
    end
  end
end
