defmodule DemoWeb.Support.ControlledTasksLive do
  @moduledoc """
  The demo's tasks attached with what the session says the page draws
  itself (`"controlled"`, else `[:picker, :panel]`), as the
  session's actor (`"actor"`, a user's id) in that actor's organization:
  for the tests of controlled mode against a resource with policies (the
  people of another organization are not the actor's to read). It tells
  the test (`"test"`) what it hears, and `{:run, fun}` runs a command of
  the test's here.
  """
  use Phoenix.LiveView

  @impl true
  def mount(_params, %{"actor" => id, "test" => test} = session, socket) do
    actor = Ash.get!(Demo.Tracker.User, id, authorize?: false)

    {:ok,
     socket
     |> assign(test: test)
     |> AshDataTable.attach(:tasks, Demo.Tracker.Task,
       actor: actor,
       tenant: actor.organization_id,
       notify: [:requested, :request_ended],
       controlled: Map.get(session, "controlled", [:picker, :panel])
     )}
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

  @impl true
  def render(assigns) do
    ~H"""
    <AshDataTable.attached table={@tasks} streams={@streams} />
    """
  end
end
