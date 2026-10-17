defmodule DemoWeb.E2E.ImportsLive do
  @moduledoc """
  A page for the browser tests of uploads in two tables of one page, one
  nested in the other: the labels with their import
  (`Demo.Tracker.Label`, table `:imports`), each label's tasks under it,
  and under a task its labels, with their own import. It is compiled and
  routed in the e2e environment only.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, page_title: "Imports")}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <AshDataTable.table
        id="label"
        resource={Demo.Tracker.Label}
        table={:imports}
        heading={1}
        actor={@current_user}
        tenant={@current_tenant}
      />
    </Layouts.app>
    """
  end
end
