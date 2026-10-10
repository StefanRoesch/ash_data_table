defmodule Demo.Support.Asked do
  @moduledoc """
  A domain for the tests of the argument line: a table whose read action
  takes an argument of every kind, calculation columns that fix and ask for
  their arguments, a nested table and a picker whose read actions take
  arguments too, and a relationship that reads through an action of its own
  with an argument it requires.
  Its resources exist for the tests only and keep their records in memory.

  The actors of these tests are maps: `%{role: :admin}`.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshTable.Domain]

  table do
    actor_assign :reader
  end

  resources do
    resource Demo.Support.Asked.Stock
    resource Demo.Support.Asked.Lot
    resource Demo.Support.Asked.Shelf
    resource Demo.Support.Asked.Vault
  end

  @doc "A default of an asked argument that looks at the assigns of the page."
  def rate(assigns), do: Map.get(assigns, :rate, 5)
end

defmodule Demo.Support.Asked.Kind do
  @moduledoc false
  use Ash.Type.Enum, values: [plain: [label: "Plain"], fancy: [label: "Fancy"]]
end

defmodule Demo.Support.Asked.Shelf do
  @moduledoc """
  Where a stock is kept: chosen in the picker, whose table reads through an
  action with two arguments. One narrows what is offered, the other widens
  it: a shelf that is closed is offered only when it is asked for.
  """
  use Ash.Resource,
    domain: Demo.Support.Asked,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  table do
    read_action :offered
    label_field :name

    column :name
    column :closed
  end

  actions do
    defaults [:read, create: [:name, :closed]]

    read :offered do
      argument :term, :string
      argument :closed_too?, :boolean, default: false

      filter expr(
               (is_nil(^arg(:term)) or contains(name, ^arg(:term))) and
                 (^arg(:closed_too?) or closed == false)
             )

      prepare build(sort: [name: :asc])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :closed, :boolean, default: false, public?: true
  end
end

defmodule Demo.Support.Asked.Lot do
  @moduledoc """
  A lot of a stock: the table nested under a stock's row. Its own read
  action takes an argument that may be left empty; `above` requires one.
  """
  use Ash.Resource,
    domain: Demo.Support.Asked,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  table do
    read_action :listed
    update_action :update

    column :code
    column :size
  end

  actions do
    defaults [:read, create: [:code, :size, :stock_id], update: [:code, :size]]

    read :listed do
      argument :code_like, :string
      filter expr(is_nil(^arg(:code_like)) or contains(code, ^arg(:code_like)))
      pagination offset?: true, countable: true, default_limit: 2, required?: false
      prepare build(sort: [code: :asc])
    end

    read :above do
      argument :size, :integer, allow_nil?: false
      filter expr(size > ^arg(:size))
      pagination offset?: true, countable: true, default_limit: 2, required?: false
      prepare build(sort: [code: :asc])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :code, :string, public?: true
    attribute :size, :integer, public?: true
  end

  relationships do
    belongs_to :stock, Demo.Support.Asked.Stock, public?: true, attribute_public?: true
  end
end

defmodule Demo.Support.Asked.Stock do
  @moduledoc """
  What is in stock. Its table reads through `search`, which takes an
  argument of every kind the argument line has an input for, one of which
  it requires; and three of its columns show one calculation, each with
  other arguments.
  """
  use Ash.Resource,
    domain: Demo.Support.Asked,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  alias Demo.Support.Asked.Kind

  table do
    read_action :search
    update_action :update
    label_field :name

    argument :term do
      label "Search for"
    end

    column :name
    column :amount
    column :shelf

    # fixed by the block
    column :amount_in do
      arguments rate: 2
    end

    # asked: one with a value to start with, one with the resource's default
    column :amount_in do
      as :amount_asked
      ask :rate, default: 3
      ask :currency
    end

    # asked, starting with what a function makes of the page's assigns
    column :amount_in do
      as :amount_fn
      label "Converted"
      arguments currency: :usd
      ask :rate, default: &Demo.Support.Asked.rate/1, label: "Exchange rate"
    end

    column :lot_count

    relationship :lots
    relationship :large_lots

    action :rename
    # its one input is the shelf, which is chosen in the picker
    action :move
    action :destroy, confirm: false
  end

  actions do
    defaults [:destroy, create: [:name, :amount, :kind, :shelf_id]]

    read :read do
      primary? true
    end

    update :update do
      primary? true
      accept [:name, :amount, :shelf_id]
    end

    update :rename do
      accept [:name]
    end

    update :move do
      accept [:shelf_id]
    end

    read :search do
      argument :term, :string

      argument :at_least, :integer do
        allow_nil? false
        constraints min: 0
      end

      argument :kind, Kind, default: :plain
      argument :any_kind?, :boolean
      argument :on, :date
      argument :at, :utc_datetime
      argument :key, :uuid
      argument :names, {:array, :string}
      argument :kinds, {:array, Kind}
      argument :secret, :string, public?: false
      argument :where, :map

      filter expr(
               amount >= ^arg(:at_least) and
                 (^arg(:any_kind?) or kind == ^arg(:kind)) and
                 (is_nil(^arg(:term)) or contains(name, ^arg(:term))) and
                 (is_nil(^arg(:names)) or name in ^arg(:names)) and
                 (is_nil(^arg(:kinds)) or kind in ^arg(:kinds)) and
                 is_nil(^arg(:secret))
             )

      pagination offset?: true, countable: true, default_limit: 2, required?: false
      prepare build(sort: [name: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      description "Refused outright for nobody."
      access_type :strict
      authorize_if actor_present()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :amount, :integer, public?: true
    attribute :kind, Kind, default: :plain, public?: true
  end

  relationships do
    belongs_to :shelf, Demo.Support.Asked.Shelf, public?: true, attribute_public?: true

    has_many :lots, Demo.Support.Asked.Lot, public?: true

    # through an action of its own, which requires an argument
    has_many :large_lots, Demo.Support.Asked.Lot do
      read_action :above
      public? true
    end
  end

  calculations do
    calculate :amount_in, :integer, expr(amount * ^arg(:rate)) do
      public? true

      argument :rate, :integer do
        allow_nil? false
        constraints min: 1
      end

      argument :currency, :atom do
        constraints one_of: [:eur, :usd]
        default :eur
      end
    end
  end

  aggregates do
    count :lot_count, :lots, public?: true
  end
end

defmodule Demo.Support.Asked.Vault do
  @moduledoc """
  A table over a read action that requires an argument, which nobody may
  run: its read is refused outright, and the page answers as one that does
  not exist before anything is filled in.
  """
  use Ash.Resource,
    domain: Demo.Support.Asked,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  table do
    read_action :coded
  end

  actions do
    defaults [:read, create: [:name]]

    read :coded do
      argument :code, :string, allow_nil?: false
    end
  end

  policies do
    policy action_type(:read) do
      access_type :strict
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end
end

defmodule DemoWeb.Support.AskedLive do
  @moduledoc """
  A LiveView of a host's own with the table of the stock placed in it twice:
  once keeping its state itself, and given the assigns that the default of
  an asked argument looks at; once with its state in the page's URL.
  """
  use Phoenix.LiveView

  alias Demo.Support.Asked.Stock

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(_params, url, socket), do: {:noreply, assign(socket, :url, url)}

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>A page of the host's</h1>
      <AshTable.table
        id="held"
        resource={Stock}
        actor={assigns[:reader]}
        assigns={%{rate: assigns[:rate]}}
      />
      <AshTable.table id="linked" resource={Stock} actor={assigns[:reader]} url={@url} />
    </main>
    """
  end
end
