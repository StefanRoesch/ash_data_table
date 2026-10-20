defmodule DemoWeb.E2E.KitTenant do
  @moduledoc """
  The tenant of `AshDataTable.Test.Resource`'s records a page of the kit
  check shows (`?tenant=`, `e2e/kit_check.spec.ts`): an `on_mount` hook of
  the router line of its parts, which the full view of a nested table of
  parts links to.
  """
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, params, _session, socket),
    do: {:cont, assign(socket, :current_tenant, params["tenant"])}
end
