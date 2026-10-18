defmodule DemoWeb.Kits.DefaultKitTest do
  @moduledoc """
  The library's own kit passes `AshDataTable.KitCase`: every state, all
  four presentations (`AshDataTable.KitCase.presentations/0`).
  """
  use AshDataTable.KitCase, kit: AshDataTable.Kit.Default, endpoint: DemoWeb.Endpoint
end
