defmodule Demo.Support.Long do
  @moduledoc """
  A domain for the tests of long text, where the demo's own tables do not
  have the case: a column that shows several lines and is edited, one of an
  array and one of a map, one that a field policy hides, and a sensitive
  column beside them. Its resource exists for the tests only and keeps its
  records in memory.

  The actors of these tests are maps: `%{role: :admin}`.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

  table do
    actor_assign :reader
  end

  resources do
    resource Demo.Support.Long.Essay
  end
end

defmodule Demo.Support.Long.Essay do
  @moduledoc """
  An essay. Its body shows up to three lines and is edited; its tags and its
  facts show up to two; its draft, which is an admin's alone on the essay called
  "Closed", shows up to two as well; its title is one line, and its token is sensitive.
  """
  use Ash.Resource,
    domain: Demo.Support.Long,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  field_policies do
    field_policy :draft do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(title != "Closed")
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    update_action :update

    column :title

    column :body do
      max_lines 3
    end

    column :tags do
      max_lines 2
    end

    column :facts do
      max_lines 2
    end

    column :draft do
      max_lines 2
    end

    column :token
    column :pages
  end

  actions do
    defaults [:read]

    update :update do
      primary? true
      require_atomic? false
      accept [:title, :body, :tags, :draft, :token]

      validate match(:body, ~r/\A[^!]*\z/) do
        message "must not shout"
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
    attribute :title, :string, public?: true
    attribute :body, :string, public?: true
    attribute :tags, {:array, :string}, public?: true
    attribute :facts, :map, public?: true
    attribute :draft, :string, public?: true
    attribute :token, :string, public?: true, sensitive?: true
    attribute :pages, :integer, public?: true
  end
end
