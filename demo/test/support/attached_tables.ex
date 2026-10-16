defmodule DemoWeb.Support.AttachedLive do
  @moduledoc """
  A LiveView of a host's own with two tables attached to it
  (`AshDataTable.attach/4`): the bulletins, whose state is in the URL, and
  the scans, whose actions take files. Beside them the host has a stream of
  its own named `"rows"`, and an event, a message, an async result and a
  `handle_params/3` of its own, each of which it notes in `heard`, and a
  command a test gives it (`{:run, fun}`).

  The session says how: `"url"` false keeps the bulletins' state in their
  table, `"uploads"` false draws the scans without the page's uploads. Its
  events attach the bulletins again as another person, detach them, attach
  them again, and attach what may not be attached.
  """
  use Phoenix.LiveView

  alias Demo.Support.Files.Scan
  alias Demo.Support.Live.Bulletin
  alias Demo.Support.Live.Reply

  @impl true
  def mount(_params, session, socket) do
    url? = Map.get(session, "url", true)

    socket =
      socket
      |> assign(heard: [], url: nil, url?: url?, uploads?: Map.get(session, "uploads", true))
      |> stream_configure("rows", dom_id: &"own-#{&1.id}")
      |> stream("rows", [%{id: 1, text: "First of the host's"}, %{id: 2, text: "Second"}])
      |> AshDataTable.attach(:bulletins, Bulletin, actor: socket.assigns[:reader], url: url?)
      |> AshDataTable.attach(:scans, Scan)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, url, socket), do: {:noreply, assign(socket, url: url)}

  @impl true
  def handle_event("say", %{"what" => what}, socket),
    do: {:noreply, heard(socket, {:event, what})}

  def handle_event("later", _params, socket),
    do: {:noreply, start_async(socket, :own, fn -> :done end)}

  def handle_event("as", %{"role" => role}, socket) do
    actor = %{role: String.to_existing_atom(role)}

    {:noreply,
     AshDataTable.attach(socket, :bulletins, Bulletin, actor: actor, url: socket.assigns.url?)}
  end

  def handle_event("detach", _params, socket),
    do: {:noreply, AshDataTable.detach(socket, :bulletins)}

  def handle_event("again", _params, socket) do
    {:noreply,
     AshDataTable.attach(socket, :bulletins, Bulletin,
       actor: socket.assigns[:reader],
       url: socket.assigns.url?
     )}
  end

  # what may not be attached: another resource under a name that is taken,
  # an id that is taken, a name whose assign is the host's own, an id that
  # a table the bulletins show may have
  def handle_event("swap", _params, socket),
    do: {:noreply, AshDataTable.attach(socket, :bulletins, Reply)}

  def handle_event("twin", _params, socket),
    do: {:noreply, AshDataTable.attach(socket, :twin, Bulletin)}

  def handle_event("over", _params, socket),
    do: {:noreply, AshDataTable.attach(socket, :heard, Bulletin, id: "other")}

  def handle_event("inside", _params, socket),
    do: {:noreply, AshDataTable.attach(socket, :inside, Bulletin, id: "bulletin-row-1")}

  # a command a test gives, in this process: `fun` takes the socket and
  # returns it
  @impl true
  def handle_info({:run, fun}, socket), do: {:noreply, fun.(socket)}

  def handle_info(message, socket), do: {:noreply, heard(socket, {:info, message})}

  @impl true
  def handle_async(:own, {:ok, result}, socket), do: {:noreply, heard(socket, {:async, result})}

  defp heard(socket, what), do: assign(socket, heard: socket.assigns.heard ++ [what])

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p id="heard">{inspect(@heard)}</p>
      <p id="url">{@url}</p>
      <ul id="own" phx-update="stream">
        <li :for={{id, row} <- @streams["rows"]} id={id}>{row.text}</li>
      </ul>
      <AshDataTable.attached table={@bulletins} streams={@streams} uploads={assigns[:uploads]} />
      <AshDataTable.attached
        table={@scans}
        streams={@streams}
        uploads={if @uploads?, do: assigns[:uploads]}
      />
    </main>
    """
  end
end

defmodule DemoWeb.Support.ParamlessLive do
  @moduledoc """
  A LiveView of a host's own without `handle_params/3`, whose table keeps
  its state in the URL (`url: true`): the table's hook is all that hears a
  patch.
  """
  use Phoenix.LiveView

  alias Demo.Support.Live.Bulletin

  @impl true
  def mount(_params, _session, socket),
    do:
      {:ok,
       AshDataTable.attach(socket, :bulletins, Bulletin,
         actor: socket.assigns[:reader],
         url: true
       )}

  @impl true
  def render(assigns) do
    ~H"""
    <AshDataTable.attached table={@bulletins} streams={@streams} />
    """
  end
end

defmodule DemoWeb.Support.Switch do
  @moduledoc """
  An `on_mount` hook for the tests: on the message `{:switch, assigns}` it
  assigns them to the socket and halts it, as a host's hook does that
  hears that another person is logged in, or that their scope changed.

  On `{:hold, pid}` it tells `pid` `:held` and waits for `:go`, so that a
  test can have messages wait in the page's mailbox in the order it wants.
  """
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     attach_hook(socket, :switch, :handle_info, fn
       {:switch, assigns}, socket ->
         {:halt, Phoenix.Component.assign(socket, assigns)}

       {:hold, pid}, socket ->
         send(pid, :held)

         receive do
           :go -> {:halt, socket}
         end

       _other, socket ->
         {:cont, socket}
     end)}
  end
end
