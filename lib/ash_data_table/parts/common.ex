defmodule AshDataTable.Parts.Common do
  @moduledoc false
  # The small helpers that several parts draw with: the place of a column
  # and of a row in the grid, a table's root element and the popover of a
  # failure (`Kit.Default`'s parts `root` and `failure`). It calls no other
  # part by name, so that the parts do not call each other in a circle. It
  # spreads `Attrs`' bundles, and `Attrs` names events and counts places
  # with it.
  use Phoenix.Component

  alias AshDataTable.Attrs
  alias AshDataTable.Present

  # A function of a column's component (`AshDataTable.Component`), which
  # is known at runtime only: called as LiveView's `Phoenix.Component` docs
  # say under "Dynamic Component Rendering", by a function component that
  # hands its assigns on with `apply/3`, so that LiveView tracks what
  # changes in them.
  def dynamic_component(assigns) do
    {module, assigns} = Map.pop(assigns, :module)
    {function, assigns} = Map.pop(assigns, :function)

    apply(module, function, [assigns])
  end

  # The root element of a table (`Attrs.root/2`, with the kit's class of
  # it): the table (`inner_block`), and after it what opens over it or in
  # the page, the question, the action panel and the picker (`opened`).
  # `nested?` says whether the table is shown inside another (nested in a
  # row, or a picker's).
  attr :id, :string, required: true
  attr :nested?, :boolean, required: true
  attr :page, :any, required: true
  attr :kit, :atom, required: true
  slot :inner_block, required: true
  slot :opened, required: true

  def root(assigns) do
    ~H"""
    <div {Attrs.root(@id, @page)} class={@kit.class(:root, %{nested?: @nested?})}>
      {render_slot(@inner_block)}{render_slot(@opened)}
    </div>
    """
  end

  # The columns after the last data column: the actions, when the rows have
  # them.
  def trail(true), do: 1
  def trail(false), do: 0

  # 1-based position of a data column among all columns of the grid.
  def colindex(index, lead), do: lead + index + 1

  # The footer row of the summaries is the last row of all: after the
  # records of every page. Where their number is not known it says nothing.
  def summary_rowindex(%{total: total}) when is_integer(total),
    do: total + Present.header_rows() + 1

  def summary_rowindex(_page), do: nil

  @doc """
  The name of the event `name` of the table `id`, as the browser sends it
  (target.md Q4): `ash_data_table:ID:NAME`. The live core takes only the
  events of its own table.
  """
  def event(id, name), do: "ash_data_table:" <> id <> ":" <> name

  # The message of a cell whose save failed, or of a row whose action
  # failed: a popover the hook opens while the cell has the focus or the
  # pointer, so that the row keeps its height; in the text colour on the
  # page's background, as the error colour is too faint for small text.
  # `id` is what the cell names in `aria-describedby`; nil in the template
  # the hook copies (`ID-failure`). Without whitespace: the hook copies it.
  attr :id, :string, default: nil
  attr :text, :string, required: true

  def failure(assigns) do
    ~H"""
    <span
      id={@id}
      {Attrs.failure()}
      class="inset-auto m-0 max-w-xs rounded border border-[color-mix(in_oklab,var(--color-error)_70%,var(--color-base-content))] bg-base-100 px-2 py-1 text-xs whitespace-normal text-base-content shadow"
      phx-no-format
    >{@text}</span>
    """
  end
end
