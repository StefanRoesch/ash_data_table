defmodule AshDataTable.Parts.Summary do
  @moduledoc false
  # The footer row of the summaries.
  # Moved out of `AshDataTable.Live.TableComponent` in stage 1 of the
  # refactor (docs/architecture/target.md); it still draws from the
  # component's assigns.
  use Phoenix.Component

  alias AshDataTable.Format
  alias AshDataTable.Parts
  alias AshDataTable.Text

  # The summary of a column in the footer row: what it is ("Sum") and the
  # number, as a cell of the column shows a value. The space between them is
  # part of the name's text, so that the two are read as two words. Nothing after the name
  # while there is no answer yet, and for a sum, an average, a minimum or a
  # maximum of no values. A dash, read out as "Not available", for a number
  # that cannot be shown to this person: the column's field is hidden from
  # them on some records, or the summary could not be computed.
  attr :column, :map, required: true
  attr :summary, :any, required: true
  attr :time_zone, :string, required: true

  defp summary(assigns) do
    ~H"""
    <span data-summary-kind class="text-xs">{Text.t(summary_text(@column.summary)) <> " "}</span><span
      :if={@summary == :unavailable}
      data-summary-unavailable
    ><span aria-hidden="true">–</span><span class="sr-only">{Text.t(:not_available)}</span></span><span
      :if={match?({:ok, _value}, @summary)}
      data-summary-value
      class="font-medium"
    >{Format.summary(@column, elem(@summary, 1), @time_zone)}</span>
    """
  end

  defp summary_text(:count), do: :summary_count
  defp summary_text(:sum), do: :summary_sum
  defp summary_text(:avg), do: :summary_avg
  defp summary_text(:min), do: :summary_min
  defp summary_text(:max), do: :summary_max

  # Part of the component's `render/1` until stage 1 of the refactor. Its
  # markup keeps the indentation it had there, held by `phx-no-format`, so
  # that the text in it, and with it the page, is the same byte for byte.
  attr :acting?, :any, required: true
  attr :expandable?, :any, required: true
  attr :id, :any, required: true
  attr :lead, :any, required: true
  attr :model, :any, required: true
  attr :page, :any, required: true
  attr :selecting, :any, required: true
  attr :summarised?, :any, required: true
  attr :summary, :any, required: true
  attr :summing?, :any, required: true
  attr :time_zone, :any, required: true

  def summaries(assigns) do
    ~H"""
    <%!-- The summaries: one more row of the grid after the last record,
    with a cell under every column, so that each number stands under its
    column, is hidden and resized with it, and is reached with the arrow keys
    as any cell is. A cell under a column without a summary is empty. See
    "Footer summaries" at the top. --%>
    <tr
      :if={@summarised? and @page}
      phx-no-format
      id={"#{@id}-summaries"}
      role="row"
      aria-rowindex={Parts.Common.summary_rowindex(@page)}
      data-summaries
    >
              <td
                :if={@selecting}
                id={"#{@id}-summaries-select"}
                role="gridcell"
                aria-colindex="1"
                tabindex="-1"
              >
              </td>
              <td
                :if={@expandable?}
                id={"#{@id}-summaries-expander"}
                role="gridcell"
                aria-colindex={@lead}
                tabindex="-1"
              >
              </td>
              <td
                :for={{column, index} <- Enum.with_index(@model.columns)}
                id={"#{@id}-summary-#{column.name}"}
                role="gridcell"
                aria-colindex={Parts.Common.colindex(index, @lead)}
                aria-busy={column.summary && @summing? && "true"}
                tabindex="-1"
                data-summary={column.summary}
                class="whitespace-nowrap"
                phx-no-format
              ><.summary :if={column.summary} column={column} summary={@summary && @summary[column.name]} time_zone={@time_zone} /></td>
              <td
                :if={@acting?}
                id={"#{@id}-summaries-actions"}
                role="gridcell"
                aria-colindex={length(@model.columns) + @lead + 1}
                tabindex="-1"
              >
              </td>
            </tr>
    """
  end
end
