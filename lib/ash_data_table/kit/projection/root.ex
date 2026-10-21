defmodule AshDataTable.Kit.Projection.Root do
  @moduledoc false
  # The projection of the `root` part (`AshDataTable.Kit.Projection`): the
  # root element of a table, of the table on the page, a nested table and a
  # picker's table. Each key of its own inputs (`key/2`).

  alias AshDataTable.Attrs

  @doc false
  def keys, do: [:element, :skip_target, :nested?, :look]

  @doc false
  # its bundle: `data-read` once its first read has been shown
  def key(:element, %{id: id, page: page}), do: Attrs.root(id, page)
  # where "Skip table" jumps to, after the table
  def key(:skip_target, %{id: id}), do: Attrs.skip_target(id)
  # whether the table is shown inside another (nested in a row, or a picker's)
  def key(:nested?, %{nested?: nested?}), do: nested?
  # the table's look, every option of it (`AshDataTable.Kit.look/2`)
  def key(:look, %{look: look}), do: look
end
