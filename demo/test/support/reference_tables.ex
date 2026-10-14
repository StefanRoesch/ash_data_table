defmodule Demo.Support.Desk do
  @moduledoc """
  A domain for the tests of what a reference cell shows when the related
  record's label is not the person's to see. Its resources exist for the
  tests only and keep their records in memory.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

  table do
    actor_assign :reader
  end

  resources do
    resource Demo.Support.Desk.Clerk
    resource Demo.Support.Desk.Docket
  end
end

defmodule Demo.Support.Desk.Clerk do
  @moduledoc """
  A clerk, called by a name that a person sees on the clerks of their own
  office only. Nobody reads any clerk while the gate (`Demo.Support.Gate`)
  is closed: that read is refused outright.

  The actors of these tests are maps: `%{office: "north"}`.
  """
  use Ash.Resource,
    domain: Demo.Support.Desk,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  field_policies do
    field_policy :name do
      authorize_if expr(office == ^actor(:office))
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    label_field :name

    column :name
  end

  actions do
    defaults [:read, create: [:name, :office]]
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
    attribute :name, :string, public?: true
    attribute :office, :string, public?: true
  end

  # A clerk has no page of their own: their table is only ever nested, under
  # a docket, and its rows expand into the clerk's dockets.
  relationships do
    has_many :dockets, Demo.Support.Desk.Docket, public?: true
  end
end

defmodule Demo.Support.Desk.Docket do
  @moduledoc "A docket anybody may read and retitle, with the clerk it is with as a reference cell."
  use Ash.Resource,
    domain: Demo.Support.Desk,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  table do
    update_action :update

    column :title
    column :clerk
  end

  actions do
    defaults [:read, create: [:title, :clerk_id], update: [:title]]
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  relationships do
    belongs_to :clerk, Demo.Support.Desk.Clerk, public?: true, attribute_writable?: true
  end
end

defmodule DemoWeb.Support.DocketsLive do
  @moduledoc """
  A LiveView of a host's own that holds the table of the dockets and gives
  it the page's URL, where the table keeps its state and what it is limited
  to.
  """
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(_params, url, socket), do: {:noreply, assign(socket, :url, url)}

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>A page of the host's, with the dockets in its URL</h1>
      <AshDataTable.table
        id="held"
        resource={Demo.Support.Desk.Docket}
        actor={assigns[:reader]}
        url={@url}
      />
    </main>
    """
  end
end
