defmodule Demo.Support.Bulk do
  @moduledoc """
  Resources for the tests of row selection and of actions on the selected
  rows, where the demo's own tables do not have the case: read actions that
  page in every way, a table without any action, and one whose records have
  no primary key. They exist for the tests only and keep their records in
  memory.
  """
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Demo.Support.Bulk.Parcel
    resource Demo.Support.Bulk.Crate
    resource Demo.Support.Bulk.Slot
    resource Demo.Support.Bulk.Letter
    resource Demo.Support.Bulk.Pouch
    resource Demo.Support.Bulk.Tally
  end
end

defmodule Demo.Support.Bulk.Heard do
  @moduledoc """
  A notifier that tells a test what it was notified of: the process
  registered under this module's name is sent each notification's action
  and the title of its record.
  """
  use Ash.Notifier

  @impl true
  def notify(%Ash.Notifier.Notification{action: action, data: record}) do
    with pid when is_pid(pid) <- Process.whereis(__MODULE__),
         do: send(pid, {:heard, action.name, record.title})

    :ok
  end
end

defmodule Demo.Support.Bulk.Parcel do
  @moduledoc """
  A parcel: read three to a page by keyset, by an action that does not
  count and gives no more than three at a time. `ship` runs on every
  parcel but the fragile ones, and the resource's notifier hears of each.
  """
  use Ash.Resource,
    domain: Demo.Support.Bulk,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource],
    simple_notifiers: [Demo.Support.Bulk.Heard],
    primary_read_warning?: false

  table do
    column :title
    column :shipped

    action :ship
  end

  actions do
    defaults create: [:title, :fragile]

    read :read do
      primary? true
      pagination keyset?: true, default_limit: 3, max_page_size: 3, countable: false
      prepare build(sort: [title: :asc])
    end

    update :ship do
      accept []
      require_atomic? false
      validate attribute_equals(:fragile, false), message: "is fragile"
      change set_attribute(:shipped, true)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :shipped, :boolean, default: false, public?: true
    attribute :fragile, :boolean, default: false, public?: true
  end
end

defmodule Demo.Support.Bulk.Crate do
  @moduledoc """
  A crate: read three to a page by offset alone, by an action that cannot
  be read without a page and gives no more than three at a time.
  """
  use Ash.Resource,
    domain: Demo.Support.Bulk,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  table do
    column :title
    column :sealed

    action :seal
    action :weigh
    action :topple
  end

  actions do
    defaults create: [:title]

    read :read do
      primary? true

      pagination offset?: true,
                 default_limit: 3,
                 max_page_size: 3,
                 countable: true,
                 required?: true

      prepare build(sort: [title: :asc])
    end

    update :seal do
      accept []
      change set_attribute(:sealed, true)
    end

    # brings down the process that runs it, as nothing an action returns does
    update :topple do
      accept []
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.before_action(changeset, fn _changeset -> exit(:toppled) end)
      end
    end

    # waits over every crate while a test holds it back (`Demo.Support.Barrier`),
    # so that the test can look at the table while it runs
    update :weigh do
      accept []
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          :ok = Demo.Support.Barrier.pass(:weigh)
          changeset
        end)
      end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :sealed, :boolean, default: false, public?: true
  end
end

defmodule Demo.Support.Bulk.Letter do
  @moduledoc """
  A letter, for what an action on the selected rows may reach. Everybody may
  file every letter: nothing but the reading stands between a person and a
  letter they are not shown. A sealed letter is nobody's to read (a policy),
  and the table reads through an action of its own, `inbox`, which leaves
  out the letters that are filed already (the action's filter); the
  primary read action returns those too.
  """
  use Ash.Resource,
    domain: Demo.Support.Bulk,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  table do
    read_action :inbox

    column :title
    column :stamps

    action :stamp
  end

  actions do
    defaults [:read, create: [:title, :sealed, :filed, :pouch_id]]

    read :inbox do
      filter expr(filed == false)
      prepare build(sort: [title: :asc])
    end

    update :stamp do
      accept []
      change atomic_update(:stamps, expr(stamps + 1))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(sealed == false)
    end

    policy action_type([:create, :update]) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :stamps, :integer, allow_nil?: false, default: 0, public?: true
    attribute :sealed, :boolean, allow_nil?: false, default: false, public?: true
    attribute :filed, :boolean, allow_nil?: false, default: false, public?: true
  end

  relationships do
    belongs_to :pouch, Demo.Support.Bulk.Pouch, public?: true, attribute_public?: true
  end
end

defmodule Demo.Support.Bulk.Pouch do
  @moduledoc "A pouch of letters: a row whose nested table is the letters' own."
  use Ash.Resource,
    domain: Demo.Support.Bulk,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  table do
    column :title
  end

  actions do
    defaults [:read, create: [:title]]
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  relationships do
    has_many :letters, Demo.Support.Bulk.Letter, public?: true
  end
end

defmodule Demo.Support.Bulk.Slot do
  @moduledoc "A slot: a table with nothing to run, on one row or on many."
  use Ash.Resource,
    domain: Demo.Support.Bulk,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  table do
    column :title
  end

  actions do
    defaults [:read, create: [:title]]
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end
end

defmodule Demo.Support.Bulk.Tally do
  @moduledoc "A tally: records without a primary key, which nothing can name."
  use Ash.Resource,
    domain: Demo.Support.Bulk,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  table do
    column :title
  end

  resource do
    require_primary_key? false
  end

  actions do
    defaults [:read, create: [:title]]
  end

  attributes do
    attribute :title, :string, public?: true
  end
end

defmodule DemoWeb.Support.SelectLive do
  @moduledoc """
  A page whose tables have no action to run on several rows: one of slots,
  and one of tallies, whose records have no primary key.
  """
  use Phoenix.LiveView

  alias Demo.Support.Bulk

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>Tables with nothing to run on a selection</h1>
      <AshDataTable.table id="plain" resource={Bulk.Slot} label="plain" heading={false} />
      <AshDataTable.table id="tally" resource={Bulk.Tally} label="tally" heading={false} />
    </main>
    """
  end
end
