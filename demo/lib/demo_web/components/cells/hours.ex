defmodule DemoWeb.Cells.Hours do
  @moduledoc """
  A component of the demo's own, as a host application writes one: a number
  of hours, shown with its unit and edited in an input that carries the unit
  and knows the field's minimum.

  It is the `component` of the "Estimate hours" column of
  `Demo.Tracker.Task`. It decides how the value looks and what it is typed
  into, and nothing else: the table saves what is typed through the column's
  update action, and never calls the component for an estimate that the
  person may not see.
  """
  use AshTable.Component

  # How a cell shows the value. `@text` is what the table itself would show.
  # Written on one line: a template that ends in text keeps the line break
  # after it, and a cell's markup is sent again with every row.
  @impl true
  def cell(assigns), do: ~H"{@text} h"

  # What the value is edited with: in a cell (`@place` is `:grid`), where it
  # stands in the place of the cell's text and has no edge of its own, and in
  # the action panel (`:panel`), where it is a field of a form. `@control`
  # goes on the one control whose value is saved.
  #
  # How the control looks is the component's to see to. In the panel its edge
  # is the text colour at half strength while it is at rest, as the edges of
  # the table's own fields are: daisyUI's is too faint to show where an
  # empty input is.
  @impl true
  def editor(assigns) do
    ~H"""
    <span class="flex items-center gap-1">
      <input
        type="number"
        min={@column.constraints[:min]}
        step="0.5"
        value={@value}
        class={
          if @place == :grid,
            do: "block h-5 w-20 bg-transparent p-0 text-sm outline-none",
            else:
              "input w-full not-focus:[--input-color:color-mix(in_oklab,var(--color-base-content)_50%,transparent)]"
        }
        {@control}
      />
      <span aria-hidden="true">h</span>
    </span>
    """
  end
end
