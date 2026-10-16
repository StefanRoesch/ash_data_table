defmodule AshDataTable.Live.Embedded do
  @moduledoc false
  # What `<AshDataTable.table>` renders (target.md 4.6, Q1): one live
  # component per tag, a ready-made wiring of the same live core
  # (`AshDataTable.Live.Core`) that `AshDataTable.attach/4` wires into a
  # LiveView. It holds the `AshDataTable.Table` under its assign `table`,
  # hands each callback to the core, and draws the table with
  # `AshDataTable.attached/1`, inside the root element it draws itself: a
  # live component's root must be a static tag. The parts send their events
  # to it (`phx-target`), and a listener hands it its batches with
  # `send_update`.
  #
  # Use it through `AshDataTable.table/1`.
  use Phoenix.LiveComponent

  alias AshDataTable.Live.Core

  @impl true
  def mount(socket), do: Core.mount(socket)

  # A table that is a page of its own and whose first read is refused is
  # not there (`gone?`, `on_forbidden :not_found`). While the page is
  # mounted, an exception is how a LiveView says "not found": Phoenix
  # answers the request with 404, and over a live connection the browser is
  # told to ask for the page afresh, which gets that answer.
  @impl true
  def update(assigns, socket) do
    first? = is_nil(socket.assigns.table.entry.read)
    {:ok, socket} = Core.update(assigns, socket)

    if first? and socket.assigns.table.options.mounted? and socket.assigns.table.entry.gone?,
      do: raise(AshDataTable.NotFoundError)

    {:ok, socket}
  end

  @impl true
  def handle_event(event, params, socket), do: Core.handle_event(event, params, socket)

  @impl true
  def handle_async(name, result, socket), do: Core.handle_async(name, result, socket)

  @impl true
  def render(%{table: %{entry: %{gone?: true}}} = assigns) do
    ~H"""
    <div id={@table.entry.id} hidden></div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id={@table.entry.id} class="ash-data-table" data-read={not is_nil(@table.entry.page)}>
      <AshDataTable.attached
        table={@table}
        streams={@streams}
        uploads={assigns[:uploads]}
        root={false}
      />
    </div>
    """
  end
end
