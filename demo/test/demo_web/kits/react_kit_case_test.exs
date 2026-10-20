defmodule DemoWeb.Kits.ReactKitCaseTest do
  @moduledoc """
  The demo's React kit passes `AshDataTable.KitCase` as a kit that draws in
  the browser (`client: true`): in every state and presentation, every
  part is given its texts and messages, and no page holds the test
  resource's sensitive value, so the kit gave it in no island's props and
  no item of a stream. The markers, ids, element kinds and Tab stops of
  what the browser drew are `e2e/react_kit.spec.ts`'s.
  """
  use AshDataTable.KitCase, kit: DemoWeb.ReactKit, endpoint: DemoWeb.Endpoint, client: true
end
