defmodule AshDataTable.Parts.Common do
  @moduledoc false
  # The small helpers that several parts draw with: a column's component,
  # a table's root element and the message of a failure (`Kit.Default`'s
  # parts `root` and `failure`). It calls no other part by name, so that
  # the parts do not call each other in a circle, and it spreads `Attrs`'
  # bundles, which call nothing of the parts. Where a column or a row
  # stands is the table's geometry's (`AshDataTable.Geometry`).
  use Phoenix.Component

  alias AshDataTable.Attrs

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
  # it): the table (`inner_block`), after it the place "Skip table" jumps
  # to (`Attrs.skip_target/1`, after the pagination), and after that what
  # opens over it or in the page, the question, the action panel and the
  # picker (`opened`).
  # `nested?` says whether the table is shown inside another (nested in a
  # row, or a picker's); `look` is its look (`AshDataTable.Kit`), whose
  # heights the table on the page holds as custom properties.
  attr :id, :string, required: true
  attr :nested?, :boolean, required: true
  attr :page, :any, required: true
  attr :look, :map, required: true
  attr :kit, :atom, required: true
  slot :inner_block, required: true
  slot :opened, required: true

  def root(assigns) do
    ~H"""
    <div
      {Attrs.root(@id, @page)}
      class={@kit.class(:root, %{nested?: @nested?, look: @look})}
      {!@nested? && AshDataTable.Parts.Look.style(@look) || %{}}
    >
      {render_slot(@inner_block)}<span {Attrs.skip_target(@id)} class="outline-none"></span>{render_slot(
        @opened
      )}
    </div>
    """
  end

  # The message of a cell whose save failed, or of a row whose action
  # failed: in the cell, under what it shows, and the row as high as it
  # needs; in the text colour, as the error colour is too faint for small
  # text. The cell's ring and its mark say "failed" besides.
  # `id` is what the cell names in `aria-describedby`; nil in the template
  # the hook copies (`ID-failure`). Without whitespace: the hook copies it.
  attr :id, :string, default: nil
  attr :text, :string, required: true

  def failure(assigns) do
    ~H"""
    <span
      id={@id}
      class="mt-0.5 block max-w-xs text-xs whitespace-normal break-words text-base-content"
      phx-no-format
    >{@text}</span>
    """
  end
end
