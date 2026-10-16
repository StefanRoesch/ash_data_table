defmodule DemoWeb.E2E.AttachedLive do
  @moduledoc """
  A page for the browser tests of tables attached to a LiveView
  (`AshDataTable.attach/4`, stage 4): the labels with their import, whose
  sort, filters and page are in the URL, under a label its tasks and under
  a task its labels, with their import too; and the tasks, which keep their
  state themselves. Beside them a stream of the page's own with a button
  that adds to it, a button that attaches the tasks again as the viewer,
  one that detaches them, and one that attaches them again. It is compiled
  and routed in the e2e environment only.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Attached", notes: 0)
     |> stream(:notes, [])
     |> AshDataTable.attach(:labels, Demo.Tracker.Label,
       id: "label",
       table: :imports,
       heading: 2,
       url: true,
       actor: socket.assigns.current_user,
       tenant: socket.assigns.current_tenant
     )
     |> tasks(socket.assigns.current_user)}
  end

  defp tasks(socket, actor) do
    AshDataTable.attach(socket, :tasks, Demo.Tracker.Task,
      heading: 2,
      actor: actor,
      tenant: socket.assigns.current_tenant
    )
  end

  # the labels patch the URL: LiveView calls this on every patch
  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("note", _params, socket) do
    notes = socket.assigns.notes + 1

    {:noreply,
     socket
     |> assign(notes: notes)
     |> stream_insert(:notes, %{id: notes, text: "Note #{notes}"})}
  end

  def handle_event("become", _params, socket),
    do: {:noreply, tasks(socket, Demo.Actors.fetch(Demo.Actors.id(:viewer)))}

  def handle_event("detach", _params, socket),
    do: {:noreply, AshDataTable.detach(socket, :tasks)}

  def handle_event("again", _params, socket),
    do: {:noreply, tasks(socket, socket.assigns.current_user)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-2xl font-semibold">Attached</h1>
      <div class="flex gap-2">
        <button id="note" type="button" class="btn" phx-click="note">Add a note</button>
        <button id="become" type="button" class="btn" phx-click="become">Become the viewer</button>
        <button id="detach" type="button" class="btn" phx-click="detach">Detach the tasks</button>
        <button id="again" type="button" class="btn" phx-click="again">Attach them again</button>
      </div>
      <ul id="notes" phx-update="stream">
        <li :for={{id, note} <- @streams.notes} id={id}>{note.text}</li>
      </ul>
      <AshDataTable.attached table={@labels} streams={@streams} uploads={assigns[:uploads]} />
      <AshDataTable.attached table={@tasks} streams={@streams} uploads={assigns[:uploads]} />
    </Layouts.app>
    """
  end
end
