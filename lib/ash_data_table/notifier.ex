defmodule AshDataTable.Notifier do
  @moduledoc false
  # A facade for the duration of the refactor. The notifier moved into the
  # declaration, as `AshDataTable.Resource.Notifier` (stage 1), and a
  # resource that says `live? true` is given that one. The tests still ask
  # this module for the topic of a resource (`test/live_updates_test.exs`
  # and the demo's). It goes when the tests may ask the declaration.

  defdelegate topic(resource, tenant), to: AshDataTable.Resource.Notifier
end
