defmodule Demo.Support.Switch do
  @moduledoc """
  What the read of `Demo.Support.Plain.Report` does next, set by a test while
  a page is open or before it is opened: `:ok`, or one of the ways a read
  fails.
  """
  def set(mode), do: :persistent_term.put(__MODULE__, mode)
  def get, do: :persistent_term.get(__MODULE__, :ok)
end

defmodule Demo.Support.Plain do
  @moduledoc """
  A domain without the extension `AshTable.Domain`: its tables authorize and
  find who is asking under the conventional assigns. Its resources exist for
  the tests only and keep their records in memory.
  """
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Demo.Support.Plain.Memo
    resource Demo.Support.Plain.Report
    resource Demo.Support.Plain.Entry
    resource Demo.Support.Plain.Ticket
    resource Demo.Support.Plain.Order
    resource Demo.Support.Plain.Customer
    resource Demo.Support.Plain.Visit
  end
end

defmodule Demo.Support.Plain.Customer do
  @moduledoc """
  A customer that only its keeper reads, with visits anybody may create: for
  what a nested table does when the row it creates under is no longer the
  person's to read.
  """
  use Ash.Resource,
    domain: Demo.Support.Plain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  actions do
    defaults [:read, create: [:name, :keeper]]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(keeper == ^actor(:name))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :keeper, :string, public?: true
  end

  relationships do
    has_many :visits, Demo.Support.Plain.Visit, public?: true
  end
end

defmodule Demo.Support.Plain.Visit do
  @moduledoc false
  use Ash.Resource,
    domain: Demo.Support.Plain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  table do
    max_depth 0
    create_action :create
  end

  actions do
    defaults [:read, create: [:note, :customer_id]]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :note, :string, public?: true
  end

  relationships do
    belongs_to :customer, Demo.Support.Plain.Customer, public?: true, attribute_public?: true
  end
end

defmodule Demo.Support.Plain.OwnOrder do
  @moduledoc """
  Whether the order that is being created is the actor's own. It looks at
  what the action is given, so it has no answer before there is an order:
  asked in advance, Ash says "maybe", and the table offers the button.
  """
  use Ash.Policy.Check

  @impl true
  def describe(_opts), do: "the order is the actor's own"

  @impl true
  def strict_check(actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    case Ash.Changeset.get_attribute(changeset, :owner) do
      nil -> {:ok, :unknown}
      owner -> {:ok, owner == actor[:name]}
    end
  end

  def strict_check(_actor, _authorizer, _opts), do: {:ok, :unknown}

  @impl true
  def check(_actor, _data, _authorizer, _opts), do: []
end

defmodule Demo.Support.Plain.Order do
  @moduledoc """
  An order, for what row actions and row create do with fields that are
  hidden and with actions that fail in every way: `code` is seen by an admin
  only, `amount` by an admin and by the order's owner. Everybody may change
  every order, so that it is the table, and not a policy, that keeps a
  hidden field from being written. A person who is no admin creates orders
  of their own only.
  """
  use Ash.Resource,
    domain: Demo.Support.Plain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  field_policies do
    field_policy :code do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :amount do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(owner == ^actor(:name))
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    column :title
    column :note
    column :amount
    column :code
    column :owner

    # opens the panel: every attribute it accepts
    action :revise
    # run straight away, and fail: about a field, about none, and underneath
    action :stamp
    action :check
    action :jam
    # opens the panel, and fails about what is no field of it
    action :settle
    # one attribute that can be empty and has a default
    action :rerank

    create_action :create
  end

  actions do
    defaults [:read]

    create :create do
      accept [:title, :note, :amount, :code, :owner]
      validate string_length(:title, min: 3)
    end

    update :revise do
      accept [:title, :note, :amount, :code]
      require_atomic? false
    end

    update :rerank do
      accept [:rank]
      require_atomic? false
    end

    update :stamp do
      accept []
      require_atomic? false
      validate string_length(:note, min: 3)
    end

    update :check do
      accept []
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.add_error(
          changeset,
          Ash.Error.Changes.InvalidChanges.exception(message: "the books are closed")
        )
      end
    end

    update :jam do
      accept []
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.add_error(
          changeset,
          Ash.Error.Framework.AssumptionFailed.exception(
            message: "the vault at 10.0.0.7 did not answer"
          )
        )
      end
    end

    update :settle do
      accept []
      require_atomic? false
      argument :paid, :integer, allow_nil?: false, constraints: [min: 0]

      # about a column that is no field of the panel, about a private field,
      # and about no field at all
      validate string_length(:note, min: 3)
      validate present(:grade)

      change fn changeset, _context ->
        Ash.Changeset.add_error(
          changeset,
          Ash.Error.Changes.InvalidChanges.exception(message: "the books are closed")
        )
      end
    end
  end

  policies do
    policy action_type([:read, :update]) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if Demo.Support.Plain.OwnOrder
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :note, :string, public?: true
    attribute :amount, :integer, public?: true
    attribute :code, :string, public?: true
    attribute :owner, :string, public?: true
    attribute :grade, :integer
    attribute :rank, :integer, default: 5, public?: true
  end
end

defmodule Demo.Support.Plain.Memo do
  @moduledoc """
  A memo whose update action has validations on fields other than the one a
  cell edits: on `body`, which everybody has a column for; on `code`, whose
  column only an admin has; and on `grade`, which is private and so no column
  of the table at all. `code` is saved through an action that fails
  underneath.
  """
  use Ash.Resource,
    domain: Demo.Support.Plain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  field_policies do
    field_policy :code do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    update_action :update

    column :title
    column :body

    column :code do
      update_action :jam
    end
  end

  actions do
    defaults [:read, create: [:title, :body, :code, :grade]]

    update :update do
      accept [:title, :body]
      require_atomic? false

      validate string_length(:body, min: 3)
      validate string_length(:code, min: 3)
      validate present(:grade)
    end

    # fails underneath: an error that is not of the action's making, though
    # it has a message
    update :jam do
      accept [:code]
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.add_error(
          changeset,
          Ash.Error.Framework.AssumptionFailed.exception(
            message: "the vault at 10.0.0.7 did not answer"
          )
        )
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
    attribute :code, :string, public?: true
    attribute :grade, :integer
  end
end

defmodule Demo.Support.Plain.Report do
  @moduledoc """
  A report whose read does what `Demo.Support.Switch` says: it succeeds, it
  returns an error on purpose (with or without a field), or it fails
  underneath.
  """
  use Ash.Resource,
    domain: Demo.Support.Plain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  alias Ash.Error.Query.InvalidArgument
  alias Ash.Error.Query.InvalidQuery

  table do
    column :title
  end

  actions do
    defaults create: [:title, :secret]

    read :read do
      primary? true

      prepare fn query, _context ->
        case Demo.Support.Switch.get() do
          :ok ->
            query

          :invalid ->
            Ash.Query.add_error(
              query,
              InvalidQuery.exception(message: "is closed until %{day}", vars: [day: "Monday"])
            )

          {:invalid_field, field} ->
            Ash.Query.add_error(
              query,
              InvalidArgument.exception(
                field: field,
                message: "must be before %{max}",
                vars: [max: 3]
              )
            )

          # with the message of one of Ash's own constraints
          :invalid_max ->
            Ash.Query.add_error(
              query,
              InvalidArgument.exception(
                field: :title,
                message: "must be less than or equal to %{max}",
                vars: [max: 3]
              )
            )

          # one of each: an error of the action's making and one that is not
          :mixed ->
            query
            |> Ash.Query.add_error(InvalidQuery.exception(message: "is closed"))
            |> Ash.Query.add_error(
              Ash.Error.Framework.AssumptionFailed.exception(
                message: "the vault at 10.0.0.7 did not answer"
              )
            )

          :unknown ->
            Ash.Query.add_error(query, "the vault at 10.0.0.7 did not answer")

          # when the records are fetched, not when Ash is merely asked what a
          # person may see
          :crash ->
            Ash.Query.before_action(query, fn _query ->
              raise "the vault at 10.0.0.7 did not answer"
            end)
        end
      end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :secret, :string, public?: true
  end
end

defmodule Demo.Support.Plain.Entry do
  @moduledoc """
  An entry with a rank: read five to a page by offset, in the order of the
  ranks, and counted.
  """
  use Ash.Resource,
    domain: Demo.Support.Plain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  table do
    column :title
    column :rank
  end

  actions do
    defaults create: [:title, :rank]

    read :read do
      primary? true
      pagination offset?: true, default_limit: 5, countable: true
      prepare build(sort: [rank: :asc])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :rank, :integer, public?: true
  end
end

defmodule Demo.Support.Plain.Ticket do
  @moduledoc """
  A ticket: read five to a page by keyset, by an action that does not count.
  """
  use Ash.Resource,
    domain: Demo.Support.Plain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  table do
    column :title
  end

  actions do
    defaults create: [:title]

    read :read do
      primary? true
      pagination keyset?: true, default_limit: 5, countable: false
      prepare build(sort: [title: :asc])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end
end

defmodule DemoWeb.Support.UrlLive do
  @moduledoc """
  A LiveView of a host's own whose tables keep their sort, filters and page
  in the page's URL: it assigns the URL that `handle_params/3` receives and
  hands it to each table.
  """
  use Phoenix.LiveView

  alias Demo.Support.Plain

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(_params, url, socket) do
    {:noreply, assign(socket, :url, url)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>A page of the host's, with its tables in its URL</h1>
      <AshTable.table id="entries" resource={Plain.Entry} url={@url} />
      <AshTable.table id="tickets" resource={Plain.Ticket} url={@url} />
    </main>
    """
  end
end

defmodule DemoWeb.Support.EmbeddedLive do
  @moduledoc """
  A LiveView of a host's own with tables of the test-only resources placed in
  it, each given what a test wants to see the effect of.
  """
  use Phoenix.LiveView

  alias Demo.Support.Guarded
  alias Demo.Support.Unguarded

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>A page of the host's</h1>
      <%!-- a domain with `authorize? false`, and the table told nothing --%>
      <AshTable.table id="open" resource={Unguarded.Note} />
      <%!-- the same resource, the table told to authorize --%>
      <AshTable.table id="checked" resource={Unguarded.Note} authorize?={true} />
      <%!-- who is asking as a scope --%>
      <AshTable.table id="scoped" resource={Guarded.Note} scope={assigns[:viewer_scope]} />
      <p id="after">After the tables</p>
    </main>
    """
  end
end
