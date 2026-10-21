defmodule AshDataTable.Kit.Projection.Status do
  @moduledoc false
  # The projection of the `status` part (`AshDataTable.Kit.Projection`):
  # the live region and what a run on the selection came to.

  alias AshDataTable.Attrs
  alias AshDataTable.Kit.Projection.Said

  @doc false
  def of(%{id: id, announcement: announcement, announcements: announcements, result: result}) do
    Map.merge(
      %{
        region: Attrs.status(id),
        # a live region is read out when what it holds changes: every other
        # announcement ends in a no-break space
        again?: rem(announcements, 2) == 1,
        result: result && %{id: "#{id}-result"}
      },
      Said.words(
        announcement: announcement,
        summary: result && result.summary,
        failures: (result && result.failures) || []
      )
    )
  end
end
