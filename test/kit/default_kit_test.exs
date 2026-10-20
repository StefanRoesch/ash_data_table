defmodule AshDataTable.Kit.DefaultKitTest do
  @moduledoc """
  The library's own kit passes `AshDataTable.KitCase`: every state, all
  four presentations (`AshDataTable.KitCase.presentations/0`), on the
  endpoint of the tests' own LiveView (`AshDataTable.Test.LiveHost`).
  """
  use AshDataTable.KitCase,
    kit: AshDataTable.Kit.Default,
    endpoint: AshDataTable.Test.LiveHost.Endpoint
end
