defmodule DemoWeb.E2E.SelectLive do
  @moduledoc """
  A page for the browser tests of row selection by itself: two tables whose
  rows can be selected though the page has nothing to run on a selection,
  one row at a time and several. This is how the library's own code shows a
  table for a person to choose from: the table component, given `select`.

  The labels are read as whoever the actor switcher says is asking: as the
  member, who can run no action on a label, the tables have nothing to run
  on a selection. It is compiled and routed in the e2e environment only.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Selecting")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-2xl font-semibold">Selecting</h1>
      <.selecting
        id="one"
        label="One label"
        select={:single}
        current_user={@current_user}
        current_tenant={@current_tenant}
      />
      <.selecting
        id="several"
        label="Several labels"
        select={:multi}
        current_user={@current_user}
        current_tenant={@current_tenant}
      />
    </Layouts.app>
    """
  end

  defp selecting(assigns) do
    ~H"""
    <.live_component
      module={AshTable.Live.TableComponent}
      id={@id}
      resource={Demo.Tracker.Label}
      select={@select}
      label={@label}
      heading={2}
      scope={nil}
      actor={@current_user}
      tenant={@current_tenant}
      authorize?={nil}
      url={nil}
      mounted?={false}
    />
    """
  end
end
