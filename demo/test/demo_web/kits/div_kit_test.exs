defmodule DemoWeb.Kits.DivKitTest do
  @moduledoc """
  The demo's kit of `div`s, whose panel and picker open in the page, passes
  `AshDataTable.KitCase` (the design note of stage 7, D12; test group Z).
  """
  use AshDataTable.KitCase, kit: DemoWeb.DivKit, endpoint: DemoWeb.Endpoint
end
