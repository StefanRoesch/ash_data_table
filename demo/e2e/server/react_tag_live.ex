defmodule DemoWeb.E2E.ReactTagLive do
  @moduledoc """
  The tasks drawn with the demo's React kit and placed with the tag
  (`AshDataTable.table/1`): the table is a live component, whose events
  carry its `phx-target`, for `e2e/react.spec.ts`. It is compiled and
  routed in the e2e environment only.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: "Tasks (React, tag)")}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} time_zone={@time_zone}>
      <AshDataTable.table
        id="tagged"
        resource={Demo.Tracker.Task}
        kit={DemoWeb.ReactKit}
        heading={1}
        actor={@current_user}
        tenant={@current_tenant}
        time_zone={@time_zone}
      />
    </Layouts.app>
    """
  end
end
