defmodule DemoWeb.Support.AttachedLive do
  @moduledoc """
  A LiveView of a host's own with two tables attached to it
  (`AshDataTable.attach/4`): the bulletins, whose state is in the URL, and
  the scans, whose actions take files. Beside them the host has a stream of
  its own named `"rows"`, and an event, a message, an async result and a
  `handle_params/3` of its own, each of which it notes in `heard`.

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
  # an id that is taken, a name whose assign is the host's own
  def handle_event("swap", _params, socket),
    do: {:noreply, AshDataTable.attach(socket, :bulletins, Reply)}

  def handle_event("twin", _params, socket),
    do: {:noreply, AshDataTable.attach(socket, :twin, Bulletin)}

  def handle_event("over", _params, socket),
    do: {:noreply, AshDataTable.attach(socket, :heard, Bulletin, id: "other")}

  @impl true
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
