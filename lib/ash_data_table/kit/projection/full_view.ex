defmodule AshDataTable.Kit.Projection.FullView do
  @moduledoc false
  # The projection of the `full_view` part (`AshDataTable.Kit.Projection`):
  # a nested table's link to its full view, the last row of its grid.

  alias AshDataTable.Attrs
  alias AshDataTable.Kit.Projection.Said

  @doc false
  def keys, do: [:row, :cell, :link, :texts, :messages]

  @doc false
  # `full_view` is the link's path; `geometry` where the columns stand (the
  # link's cell spans them all).
  def of(%{id: id, full_view: full_view, label: label, geometry: geometry}) do
    Map.merge(
      %{
        row: Attrs.row("#{id}-view-row"),
        cell: Attrs.spanning("#{id}-view", geometry, %{"data-view" => true}),
        # the link (a navigation to `path`)
        link: %{id: "#{id}-full-view", path: full_view}
      },
      Said.words(full_view: Said.t(:full_view), full_view_of: Said.t(:full_view_of, table: label))
    )
  end
end
