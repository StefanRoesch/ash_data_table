defmodule DemoWeb.Support.MarkedKit do
  @moduledoc """
  A kit for the tests of the kit's part `cell/1`: it draws what the
  default kit draws, inside an element that
  says what the part was given: the cell's state, and whether it was given
  a value or its text.
  """
  use AshDataTable.Kit, contract: 4

  def cell(assigns) do
    ~H"""
    <span
      data-kit-cell={@state}
      data-given={if is_nil(@value) and is_nil(@text), do: "none", else: "value"}
    >{super(assigns)}</span>
    """
  end
end

defmodule DemoWeb.Support.KitTagLive do
  @moduledoc "A page of the host's with a table placed by the tag and given a kit."
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <AshDataTable.table
      id="tagged"
      resource={Demo.Support.Plain.Memo}
      actor={assigns[:current_user]}
      kit={DemoWeb.DivKit}
    />
    """
  end
end

defmodule DemoWeb.Support.GermanKitLive do
  @moduledoc """
  The table `AshDataTable.KitCase` draws, in German: a table of
  `AshDataTable.Test.Resource` in the tenant of the session, drawn with
  the demo's kit of `div`s (`DemoWeb.DivKit`), in a LiveView whose locale
  is `de`.
  """
  use Phoenix.LiveView

  @impl true
  def mount(_params, %{"tenant" => tenant}, socket) do
    Gettext.put_locale(DemoWeb.Gettext, "de")

    {:ok,
     AshDataTable.attach(socket, :table, AshDataTable.Test.Resource,
       id: "kit",
       tenant: tenant,
       kit: DemoWeb.DivKit
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AshDataTable.attached table={@table} streams={@streams} uploads={assigns[:uploads]} />
    """
  end
end

defmodule DemoWeb.Support.ControlledKitLive do
  @moduledoc """
  The table `AshDataTable.KitCase` draws, attached with what the session
  says the page draws itself (`"controlled"`) and how what opens is
  presented (`"presentation"`), in the session's tenant: for the tests of
  controlled mode widened. It tells the
  test (`"test"`) what it hears and what its veto was asked
  (`{:asked, request}`), and answers the veto as the assign `answer` says;
  `{:run, fun}` runs a command of the test's here.
  """
  use Phoenix.LiveView

  @impl true
  def mount(_params, %{"tenant" => tenant, "test" => test} = session, socket) do
    socket =
      socket
      |> assign(test: test, answer: :cont)
      |> AshDataTable.attach(:table, AshDataTable.Test.Resource,
        id: "kit",
        tenant: tenant,
        notify: [:requested, :request_ended],
        presentation: Map.get(session, "presentation", []),
        controlled: Map.get(session, "controlled", []),
        before_action: fn request, assigns ->
          send(assigns.test, {:asked, request})
          assigns.answer
        end
      )

    {:ok, socket}
  end

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

  # the page's own form of a panel it draws: the file inputs, sent as the
  # table's panel sends them
  @impl true
  def handle_event("host_validate", params, socket),
    do:
      {:noreply,
       by_request(socket, &AshDataTable.validate_request(&1, :table, &2, params["panel"] || %{}))}

  def handle_event("host_submit", params, socket),
    do:
      {:noreply,
       by_request(socket, &AshDataTable.submit_request(&1, :table, &2, params["panel"] || %{}))}

  # the panel the page draws: the first request of the kind, of whichever
  # table holds it
  defp by_request(socket, fun) do
    case Enum.find(AshDataTable.requests(socket.assigns.table), &(&1.kind == :panel)) do
      %{ref: ref} -> fun.(socket, ref)
      nil -> socket
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        request: Enum.find(AshDataTable.requests(assigns.table), &(&1.kind == :panel))
      )

    ~H"""
    <AshDataTable.attached table={@table} streams={@streams} uploads={assigns[:uploads]} />
    <form
      :if={match?(%{kind: :panel}, @request)}
      id="host-form"
      phx-change="host_validate"
      phx-submit="host_submit"
    >
      <.live_file_input
        :for={%{upload: upload} <- @request.fields}
        upload={@uploads[upload]}
      />
    </form>
    """
  end
end

defmodule DemoWeb.Support.ItemsKit do
  @moduledoc """
  A kit for the measurement of the stream's items as JSON
  (`item_bytes_test.exs`, M2 of the React kit's note): it draws what the
  default kit draws, and after the grid every item of its stream as JSON,
  as a kit that hands the stream to the browser sends it, one script each.
  """
  use AshDataTable.Kit, contract: 4

  def grid(assigns) do
    ~H"""
    {super(assigns)}
    <script
      :for={{dom_id, item} <- @rows}
      id={"#{dom_id}-json"}
      type="application/json"
      data-item
    >
      <%= Phoenix.HTML.raw(Jason.encode!(item)) %>
    </script>
    """
  end
end
