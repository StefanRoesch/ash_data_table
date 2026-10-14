defmodule AshDataTable.Notifier do
  @moduledoc false
  # A facade for the duration of the refactor. The notifier moved into the
  # declaration, as `AshDataTable.Resource.Notifier` (stage 1). A resource
  # that says `live? true` is still given this module, because what
  # `Ash.Resource.Info.notifiers/1` lists, and the tests that name it, stay
  # as they are until the owner says otherwise. Removed in a later stage.
  use Ash.Notifier

  alias AshDataTable.Resource.Notifier

  @impl Ash.Notifier
  def notify(notification), do: Notifier.notify(notification)

  defdelegate topic(resource, tenant), to: Notifier
end
