defmodule DemoWeb.Kits.DefaultKitTest do
  @moduledoc """
  The library's own kit passes `AshDataTable.KitCase` (the design note of
  stage 7, D12; test group Z): every state, both presentations.
  """
  use AshDataTable.KitCase, kit: AshDataTable.Kit.Default, endpoint: DemoWeb.Endpoint
end
