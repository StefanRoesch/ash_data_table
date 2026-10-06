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
