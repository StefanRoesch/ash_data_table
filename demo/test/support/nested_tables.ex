defmodule Demo.Support.Shelves do
  @moduledoc """
  A domain for the tests of what a nested table shows when its read is
  refused or fails. Its resources exist for the tests only and keep their
  records in memory.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshTable.Domain]

  # who is asking is found under a name the demo's own layout does not read
  table do
    actor_assign :reader
  end

  resources do
    resource Demo.Support.Shelves.Binder
    resource Demo.Support.Shelves.Paper
    resource Demo.Support.Shelves.Draft
    resource Demo.Support.Shelves.Sheet
    resource Demo.Support.Shelves.Slip
  end
end

defmodule Demo.Support.Shelves.Binder do
  @moduledoc """
  A binder anybody may read, whose rows expand into tables that are not
  always theirs to read: papers and drafts are refused outright while the
  gate (`Demo.Support.Gate`) is closed, and the read of the sheets does what
  `Demo.Support.Switch` says.
  """
  use Ash.Resource,
    domain: Demo.Support.Shelves,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  table do
    column :title

    relationship :papers
    relationship :sealed_papers
    relationship :drafts
    relationship :sheets
    relationship :slips
  end

  actions do
    defaults [:read, create: [:title]]
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  relationships do
    # A refusal of the destination comes back in place of the records
    # (the demo sets `allow_forbidden_field_for_relationships_by_default`).
    has_many :papers, Demo.Support.Shelves.Paper, public?: true

    # The same records; a refusal of the destination fails the whole read.
    has_many :sealed_papers, Demo.Support.Shelves.Paper do
      allow_forbidden_field? false
      public? true
    end

    has_many :drafts, Demo.Support.Shelves.Draft, public?: true
    has_many :sheets, Demo.Support.Shelves.Sheet, public?: true
    has_many :slips, Demo.Support.Shelves.Slip, public?: true
  end
end

defmodule Demo.Support.Shelves.Paper do
  @moduledoc """
  A paper, read only while the gate is open: its read is refused outright
  otherwise, and its table says so (`on_forbidden :message`).
  """
  use Ash.Resource,
    domain: Demo.Support.Shelves,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  table do
    on_forbidden :message

    column :title
  end

  actions do
    defaults [:read, create: [:title, :binder_id]]
  end

  policies do
    policy action_type(:read) do
      access_type :strict
      authorize_if Demo.Support.Gate
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  relationships do
    belongs_to :binder, Demo.Support.Shelves.Binder, public?: true, attribute_writable?: true
  end
end

defmodule Demo.Support.Shelves.Draft do
  @moduledoc """
  A draft, read only while the gate is open. Its table says nothing about a
  refused read: as a page it would not exist.
  """
  use Ash.Resource,
    domain: Demo.Support.Shelves,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  table do
    column :title
  end

  actions do
    defaults [:read, create: [:title, :binder_id]]
  end

  policies do
    policy action_type(:read) do
      access_type :strict
      authorize_if Demo.Support.Gate
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  relationships do
    belongs_to :binder, Demo.Support.Shelves.Binder, public?: true, attribute_writable?: true
  end
end

defmodule Demo.Support.Shelves.Sheet do
  @moduledoc """
  A sheet whose read does what `Demo.Support.Switch` says: it succeeds, it
  returns an error on purpose, or it fails underneath.
  """
  use Ash.Resource,
    domain: Demo.Support.Shelves,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  alias Ash.Error.Query.InvalidQuery

  table do
    column :title
  end

  actions do
    defaults create: [:title, :binder_id]

    read :read do
      primary? true

      prepare fn query, _context ->
        case Demo.Support.Switch.get() do
          :invalid ->
            Ash.Query.add_error(
              query,
              InvalidQuery.exception(message: "is closed until %{day}", vars: [day: "Monday"])
            )

          :unknown ->
            Ash.Query.add_error(query, "the vault at 10.0.0.7 did not answer")

          :crash ->
            Ash.Query.before_action(query, fn _query ->
              raise "the vault at 10.0.0.7 did not answer"
            end)

          _ok ->
            query
        end
      end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  relationships do
    belongs_to :binder, Demo.Support.Shelves.Binder, public?: true, attribute_writable?: true
  end
end

defmodule Demo.Support.Shelves.Slip do
  @moduledoc """
  A slip with an amount that a person sees on their own slips only, read by
  keyset in pages of five by an action that counts.

  The actors of these tests are maps: `%{name: "max"}`.
  """
  use Ash.Resource,
    domain: Demo.Support.Shelves,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  field_policies do
    field_policy :amount do
      authorize_if expr(owner == ^actor(:name))
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    column :title
    column :amount
  end

  actions do
    defaults create: [:title, :amount, :owner, :binder_id]

    read :read do
      primary? true
      pagination keyset?: true, default_limit: 5, countable: true
      prepare build(sort: [title: :asc])
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
    attribute :amount, :integer, public?: true
    attribute :owner, :string, public?: true
  end

  relationships do
    belongs_to :binder, Demo.Support.Shelves.Binder, public?: true, attribute_writable?: true
  end
end

defmodule DemoWeb.Support.SwitchLive do
  @moduledoc """
  A LiveView of a host's own whose tables are given an actor that changes
  while the page is open: the event `become` names the user who is asking
  from then on.
  """
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, become(socket, socket.assigns[:actor_id])}

  @impl true
  def handle_event("become", %{"id" => id}, socket), do: {:noreply, become(socket, id)}

  defp become(socket, id) do
    actor = Demo.Actors.fetch(id)
    assign(socket, actor: actor, tenant: Demo.Actors.tenant(actor))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <button id="become" phx-click="become">Become</button>
      <AshTable.table id="tasks" resource={Demo.Tracker.Task} actor={@actor} tenant={@tenant} />
      <AshTable.table id="projects" resource={Demo.Tracker.Project} actor={@actor} tenant={@tenant} />
    </main>
    """
  end
end
