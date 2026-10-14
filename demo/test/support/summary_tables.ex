defmodule Demo.Support.Sums do
  @moduledoc """
  A domain for the tests of footer summaries where the demo's own tables do
  not go: a table whose field policies depend on the read action it reads
  through, one whose read action requires an argument, one whose summary
  the database cannot compute, and the same tables mounted without
  authorization.

  Its resource exists for the tests only. It reads the demo's tasks in
  Postgres, under a name and policies of its own.

  The actors of these tests are the demo's users.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

  table do
    actor_assign :reader
  end

  resources do
    resource Demo.Support.Sums.Effort
  end
end

defmodule Demo.Support.Sums.Effort do
  @moduledoc """
  A task under another name, two to a page.

  Nobody reads an effort whose title starts with "Sealed". The estimate is
  seen on every effort through `:read`, the primary read action, and on a
  person's own only (those they are assigned to) through `:board` and
  `:above`; with the progress it is the other way round.

    * The default table reads through `:board`.
    * The table `:primary` reads through `:read`.
    * The table `:above` reads through an action that requires an argument.
    * The table `:broken` sums `ghost`, an attribute the database has no
      column for and that no read selects: its rows are read, and its
      summary fails.
  """
  use Ash.Resource,
    domain: Demo.Support.Sums,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  postgres do
    table "tasks"
    repo Demo.Repo
    migrate? false
  end

  field_policies do
    field_policy :estimate_hours, action(:read) do
      authorize_if always()
    end

    field_policy :estimate_hours, action([:board, :above]) do
      authorize_if expr(assignee_id == ^actor(:id))
    end

    field_policy :progress, action(:read) do
      authorize_if expr(assignee_id == ^actor(:id))
    end

    field_policy :progress, action([:board, :above]) do
      authorize_if always()
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    read_action :board
    update_action :update

    column :title do
      summary :count
    end

    column :estimate_hours do
      summary :sum
    end

    column :progress do
      summary :max
    end
  end

  tables do
    table :primary do
      column :title

      column :estimate_hours do
        summary :sum
      end

      column :progress do
        summary :avg
      end
    end

    table :above do
      read_action :above

      column :title

      column :progress do
        summary :sum
      end
    end

    table :broken do
      column :title

      column :ghost do
        summary :sum
      end
    end
  end

  actions do
    read :read do
      primary? true
      pagination offset?: true, countable: true, default_limit: 2, required?: false
      prepare build(sort: [title: :asc, id: :asc])
    end

    read :board do
      pagination offset?: true, countable: true, default_limit: 2, required?: false
      prepare build(sort: [title: :asc, id: :asc])
    end

    read :above do
      argument :least, :integer, allow_nil?: false
      filter expr(progress >= ^arg(:least))
      pagination offset?: true, countable: true, default_limit: 2, required?: false
      prepare build(sort: [title: :asc, id: :asc])
    end

    update :update do
      primary? true
      accept [:title, :estimate_hours, :progress]
    end
  end

  policies do
    policy action_type(:read) do
      forbid_if expr(contains(title, "Sealed"))
      authorize_if actor_present()
    end

    policy action_type(:update) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :estimate_hours, :decimal, public?: true
    attribute :progress, :integer, public?: true
    attribute :assignee_id, :uuid, public?: true

    # no column of the table: never selected, and so never read with a row
    attribute :ghost, :integer, public?: true, select_by_default?: false
  end
end
