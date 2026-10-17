defmodule DemoWeb.Kits.DefaultKitTest do
  @moduledoc """
  The library's own kit passes `AshDataTable.KitCase`: every state, both
  presentations.
  """
  use AshDataTable.KitCase, kit: AshDataTable.Kit.Default, endpoint: DemoWeb.Endpoint
end
