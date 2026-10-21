defmodule AshDataTable.Parts.Summary do
  @moduledoc false
  # The footer of the grid: the row of the summaries, and in a nested table
  # the row of its pages and the row of its link to the full view. The
  # parts `footer` and `summary_cell` of `AshDataTable.Kit.Default`.
  use Phoenix.Component

  alias AshDataTable.Kit

  # The summary of a column in the footer row: what it is ("Sum") and the
  # number, as a cell of the column shows a value. The space between them is
  # part of the name's text, so that the two are read as two words. Nothing after the name
  # while there is no answer yet, and for a sum, an average, a minimum or a
  # maximum of no values. A dash, read out as "Not available", for a number
  # that cannot be shown to this person: the column's field is hidden from
  # them on some records, or the summary could not be computed.
  attr :state, :atom, required: true
  attr :texts, :map, required: true
  attr :text, :any, required: true

  defp summary(assigns) do
    ~H"""
    <span data-summary-kind class="text-xs">{@texts.kind <> " "}</span><span
      :if={@state == :unavailable}
      data-summary-unavailable
    ><span aria-hidden="true">–</span><span class="sr-only">{@texts.not_available}</span></span><span
      :if={@state == :ok}
      data-summary-value
      class="font-medium"
    >{@text}</span>
    """
  end

  # The cell of a column in the footer row: its id, place and what varies
  # of it are its `element`; its role is written here, as the row is sent
  # again while its summaries are on their way and once more when they are
  # there. Its projection (`AshDataTable.Kit.Projection`, a cell of the
  # footer's `summaries`).
  attr :element, :map, required: true
  attr :summary?, :boolean, required: true
  attr :state, :atom, required: true
  attr :value, :any, required: true
  attr :text, :any, required: true
  attr :texts, :map, required: true
  attr :messages, :map, required: true
  attr :locale, :string, required: true

  def summary_cell(assigns) do
    ~H"""
    <td
      {@element}
      role="cell"
      class="whitespace-nowrap"
      phx-no-format
    ><.summary :if={@summary?} state={@state} texts={@texts} text={@text} /></td>
    """
  end

  # The footer of the grid. In the text of the table: the range reads as it
  # does under a table on a page, not as a footer's heading. What the two
  # rows of a nested table hold stays at the left edge of the table's
  # scroll area, as what a line holds does.
  #
  # The pages of a nested table are a last row of its grid, its buttons Tab
  # stops as a table's on the page are. The element stays where it is once
  # it is there, as every child of a stream's container with an id does.
  # Its projection (`AshDataTable.Kit.Projection`, `grid`'s `footer`).
  attr :id, :string, required: true
  attr :element, :map, required: true
  attr :summaries, :map, required: true
  attr :pager, :map, required: true
  attr :full_view, :map, required: true
  attr :kit, :atom, required: true

  def footer(assigns) do
    ~H"""
    <tfoot
      {@element}
      class="font-normal text-base-content"
    >
      <.summaries :if={@summaries} summaries={@summaries} kit={@kit} />
      <tr
        :if={@pager}
        {@pager.row}
      >
        <td {@pager.cell}>
          <Kit.part
            part={:pagination}
            kit={@kit}
            id={@id}
            {@pager.pagination}
          />
        </td>
      </tr>
      <Kit.part
        :if={@full_view}
        part={:full_view}
        kit={@kit}
        id={@id}
        {@full_view}
      />
    </tfoot>
    """
  end

  attr :summaries, :map, required: true
  attr :kit, :atom, required: true

  defp summaries(assigns) do
    ~H"""
    <%!-- The summaries: one more row of the grid after the last record,
    with a cell under every column, so that each number stands under its
    column and is hidden and resized with it. No Tab stops: a screen reader
    reads it with its table keys. A cell under a column without a summary is
    empty. See "Footer summaries" at the top. --%>
    <tr {@summaries.row}>
      <td
        :if={@summaries.select}
        {@summaries.select}
      >
      </td>
      <td
        :if={@summaries.expander}
        {@summaries.expander}
      >
      </td>
      <Kit.part
        :for={cell <- @summaries.cells}
        part={:summary_cell}
        kit={@kit}
        {cell}
      />
      <td
        :if={@summaries.actions}
        {@summaries.actions}
      >
      </td>
    </tr>
    """
  end
end
