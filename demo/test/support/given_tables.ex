defmodule Demo.Support.Given do
  @moduledoc """
  A domain for the tests of what a page gives a table and hears of it
  (stage 6): its resources tell the test whose pid the page's `context`
  holds (`test`) what each read and write was given, as messages:

    * `{:read, resource, ref, secret}` from a read, `ref` being the
      `table_ref` the page's `context` function was told;
    * `{:write, resource, action, arguments, ref}` from a create, an update
      or a destroy, when it runs.

  `secret` is an argument their actions declare `public?: false`. Their
  records are kept in memory.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

  resources do
    resource Demo.Support.Given.Card
    resource Demo.Support.Given.Remark
  end
end

defmodule Demo.Support.Given.Heard do
  @moduledoc "What tells the test what a read or a write of the domain was given."

  @doc "A preparation that tells the test what a read was given."
  def read(query, _context) do
    with %{test: test, ref: ref} <- query.context,
         do: send(test, {:read, query.resource, ref, Ash.Query.get_argument(query, :secret)})

    # a read the page's context says to fail
    if query.context[:fail],
      do: Ash.Query.add_error(query, Ash.Error.Invalid.exception(errors: [])),
      else: query
  end

  @doc "A change that tells the test what a write was given, when it runs."
  def write(changeset, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      with %{test: test, ref: ref} <- changeset.context,
           do:
             send(
               test,
               {:write, changeset.resource, changeset.action.name, changeset.arguments, ref}
             )

      changeset
    end)
  end
end

defmodule Demo.Support.Given.Card do
  @moduledoc "A card, with remarks; a page fills in whom it is assigned to."
  use Ash.Resource,
    domain: Demo.Support.Given,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  table do
    label_field :title
    update_action :update
    create_action :create

    column :title
    column :assignee
    column :code

    relationship :remarks

    action :assign do
      page_argument :to
    end

    action :rename

    action :destroy do
      confirm "Delete this card?"
    end

    action :count_cards
  end

  actions do
    read :read do
      primary? true
      argument :secret, :string, public?: false
      prepare build(sort: [title: :asc])
      prepare &Demo.Support.Given.Heard.read/2
    end

    create :create do
      accept [:title, :code]
      argument :note, :string
      argument :pin, :string, sensitive?: true
    end

    destroy :destroy

    update :rename do
      require_atomic? false
      accept [:title]
      argument :reason, :string, allow_nil?: false
    end

    action :count_cards, :integer do
      run fn _input, _context -> {:ok, 3} end
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:title]
      argument :secret, :string, public?: false
      change &Demo.Support.Given.Heard.write/2
    end

    update :assign do
      require_atomic? false
      argument :to, :string, allow_nil?: false
      argument :secret, :string, public?: false
      change set_attribute(:assignee, arg(:to))
      change &Demo.Support.Given.Heard.write/2
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :assignee, :string, public?: true
    attribute :code, :string, public?: true, sensitive?: true
  end

  relationships do
    has_many :remarks, Demo.Support.Given.Remark, public?: true
  end
end

defmodule Demo.Support.Given.Remark do
  @moduledoc "A remark on a card, which points at a card."
  use Ash.Resource,
    domain: Demo.Support.Given,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  table do
    update_action :update

    column :body
    column :card
  end

  actions do
    defaults create: [:body, :card_id]

    read :read do
      primary? true
      argument :secret, :string, public?: false
      prepare &Demo.Support.Given.Heard.read/2
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:body, :card_id]
      argument :secret, :string, public?: false
      change &Demo.Support.Given.Heard.write/2
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true
  end

  relationships do
    belongs_to :card, Demo.Support.Given.Card, public?: true, attribute_writable?: true
  end
end

defmodule DemoWeb.Support.GivenLive do
  @moduledoc """
  A host LiveView whose cards are attached with what it gives them: a
  `context` that holds the test's pid and which table asks, a private
  argument, the page arguments of the session (`"page"`, else the
  assignee), the events the session's `"notify"` names, the "Open" its
  `"open"` labels, what the host draws itself (`"controlled"`), a read that
  fails where the session says `"fail"`, and a veto that tells the test
  what it was asked, with which assigns, and answers as the assign `answer`
  says (the session's `"answer"`, else `:cont`). `"context"` in the session replaces the
  context function. Everything the page hears it hands to the test, but
  `{:run, fun}`: a command of the test's, run here.

  Mounted with `Phoenix.LiveViewTest.live_isolated/3`.
  """
  use Phoenix.LiveView

  alias Demo.Support.Given.Card

  @impl true
  def mount(_params, session, socket) do
    test = Map.fetch!(session, "test")
    fail? = Map.get(session, "fail", false)

    context =
      Map.get(session, "context", fn assigns, ref ->
        %{test: assigns.test, ref: ref, fail: fail?}
      end)

    socket =
      socket
      |> assign(test: test, answer: Map.get(session, "answer", :cont))
      |> AshDataTable.attach(:cards, Card,
        context: context,
        private_arguments: %{secret: "s3", to: "browser"},
        page_arguments: Map.get(session, "page", %{to: "ann"}),
        before_action: fn request, assigns ->
          send(assigns.test, {:asked, request, Map.has_key?(assigns, :cards)})
          assigns.answer
        end,
        notify: Map.get(session, "notify"),
        open: Map.get(session, "open"),
        controlled: Map.get(session, "controlled", [])
      )

    {:ok, socket}
  end

  # a command the test gives, in this process: `{:run, fun}`, `fun` taking
  # the socket and returning the socket and what to tell the test
  @impl true
  def handle_info({:run, fun}, socket) do
    {socket, told} = fun.(socket)
    send(socket.assigns.test, {:ran, told})
    {:noreply, socket}
  end

  def handle_info(message, socket) do
    send(socket.assigns.test, {:heard, message})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AshDataTable.attached table={@cards} streams={@streams} />
    """
  end
end

defmodule DemoWeb.Support.GivenTagLive do
  @moduledoc """
  The cards placed with the tag, given the same as `DemoWeb.Support.GivenLive`
  gives them, and the page's assigns as `assigns`; told reads and saves.
  """
  use Phoenix.LiveView

  @impl true
  def mount(_params, session, socket),
    do: {:ok, assign(socket, test: Map.fetch!(session, "test"), answer: :cont)}

  @impl true
  def handle_info({:run, fun}, socket) do
    {socket, told} = fun.(socket)
    send(socket.assigns.test, {:ran, told})
    {:noreply, socket}
  end

  def handle_info(message, socket) do
    send(socket.assigns.test, {:heard, message})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AshDataTable.table
      resource={Demo.Support.Given.Card}
      assigns={%{test: @test, answer: @answer}}
      context={fn assigns, ref -> %{test: assigns.test, ref: ref} end}
      private_arguments={%{secret: "s3"}}
      page_arguments={%{to: "ann"}}
      before_action={
        fn request, assigns ->
          send(assigns.test, {:asked, request, Enum.sort(Map.keys(assigns))})
          assigns.answer
        end
      }
      notify={[:read, :row_saved]}
    />
    """
  end
end
