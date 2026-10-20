defmodule AshDataTable.Parts.Summary do
  @moduledoc false
  # The footer of the grid: the row of the summaries, and in a nested table
  # the row of its pages and the row of its link to the full view. The
  # parts `footer` and `summary_cell` of `AshDataTable.Kit.Default`.
  use Phoenix.Component

  alias AshDataTable.Attrs
  alias AshDataTable.Geometry
  alias AshDataTable.Kit
  alias AshDataTable.Kit.Words
  alias AshDataTable.Parts

  # The summary of a column in the footer row: what it is ("Sum") and the
  # number, as a cell of the column shows a value. The space between them is
  # part of the name's text, so that the two are read as two words. Nothing after the name
  # while there is no answer yet, and for a sum, an average, a minimum or a
  # maximum of no values. A dash, read out as "Not available", for a number
  # that cannot be shown to this person: the column's field is hidden from
  # them on some records, or the summary could not be computed.
  attr :summary, :any, required: true
  attr :texts, :map, required: true
  attr :text, :any, required: true

  defp summary(assigns) do
    ~H"""
    <span data-summary-kind class="text-xs">{@texts.kind <> " "}</span><span
      :if={@summary == :unavailable}
      data-summary-unavailable
    ><span aria-hidden="true">–</span><span class="sr-only">{@texts.not_available}</span></span><span
      :if={match?({:ok, _value}, @summary)}
      data-summary-value
      class="font-medium"
    >{@text}</span>
    """
  end

  # The cell of a column in the footer row: what varies of it is
  # `AshDataTable.Attrs.summary/2`'s; its id, place and role are
  # written here, as the row is sent again while its summaries are on their
  # way and once more when they are there.
  attr :id, :string, required: true
  attr :column, :map, required: true
  attr :colindex, :integer, required: true
  attr :summary, :any, required: true
  attr :summing?, :boolean, required: true
  attr :time_zone, :string, required: true
  attr :texts, :map, required: true
  attr :text, :any, required: true

  def summary_cell(assigns) do
    ~H"""
    <td
      id={@id}
      role="cell"
      aria-colindex={@colindex}
      {Attrs.summary(@column, @summing?)}
      class="whitespace-nowrap"
      phx-no-format
    ><.summary :if={@column.summary} summary={@summary} texts={@texts} text={@text} /></td>
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
  attr :expandable?, :any, required: true
  attr :full_view, :any, required: true
  # where the columns and rows stand (`AshDataTable.Geometry`)
  attr :geometry, :map, required: true
  attr :id, :any, required: true
  attr :kit, :atom, required: true
  attr :label, :any, required: true
  attr :model, :any, required: true
  attr :myself, :any, required: true
  attr :nested?, :any, required: true
  attr :page, :any, required: true
  attr :pages?, :boolean, required: true
  attr :row_count, :any, required: true
  attr :selecting, :any, required: true
  attr :state, :any, required: true
  attr :summary, :any, required: true
  attr :summing?, :any, required: true
  attr :time_zone, :any, required: true

  def footer(assigns) do
    ~H"""
    <tfoot
      id={"#{@id}-foot"}
      class="font-normal text-base-content"
      hidden={
        not (@geometry.summary? and not is_nil(@page)) and
          not (@nested? and (@pages? or Parts.Related.full_view?(@page, @full_view)))
      }
    >
      <.summaries
        expandable?={@expandable?}
        geometry={@geometry}
        id={@id}
        kit={@kit}
        model={@model}
        page={@page}
        selecting={@selecting}
        summary={@summary}
        summing?={@summing?}
        time_zone={@time_zone}
      />
      <tr
        :if={@nested? and @pages?}
        {Attrs.row("#{@id}-foot-row")}
      >
        <td {Attrs.spanning("#{@id}-pager", @geometry, %{"data-pager" => true})}>
          <Kit.part
            part={:pagination}
            kit={@kit}
            id={@id}
            nested?={true}
            page={@page}
            model={@model}
            state={@state}
            row_count={@row_count}
            label={@label}
            target={@myself}
            pages={Words.value(:pagination, %{page: @page, state: @state})}
            texts={
              Words.texts(:pagination, %{
                page: @page,
                row_count: @row_count,
                state: @state,
                label: @label
              })
            }
            messages={
              Words.messages(:pagination, %{
                page: @page,
                row_count: @row_count,
                state: @state,
                label: @label
              })
            }
          />
        </td>
      </tr>
      <Kit.part
        :if={@nested? and Parts.Related.full_view?(@page, @full_view)}
        part={:full_view}
        kit={@kit}
        full_view={@full_view}
        geometry={@geometry}
        id={@id}
        label={@label}
        model={@model}
        texts={Words.texts(:full_view, %{label: @label})}
        messages={Words.messages(:full_view, %{label: @label})}
      />
    </tfoot>
    """
  end

  attr :expandable?, :any, required: true
  attr :geometry, :map, required: true
  attr :id, :any, required: true
  attr :kit, :atom, required: true
  attr :model, :any, required: true
  attr :page, :any, required: true
  attr :selecting, :any, required: true
  attr :summary, :any, required: true
  attr :summing?, :any, required: true
  attr :time_zone, :any, required: true

  defp summaries(assigns) do
    ~H"""
    <%!-- The summaries: one more row of the grid after the last record,
    with a cell under every column, so that each number stands under its
    column and is hidden and resized with it. No Tab stops: a screen reader
    reads it with its table keys. A cell under a column without a summary is
    empty. See "Footer summaries" at the top. --%>
    <tr
      :if={@geometry.summary? and @page}
      {Attrs.summaries(@id, @geometry, @page)}
    >
      <td
        :if={@selecting}
        id={"#{@id}-summaries-select"}
        role="cell"
        aria-colindex="1"
      >
      </td>
      <td
        :if={@expandable?}
        id={"#{@id}-summaries-expander"}
        role="cell"
        aria-colindex={@geometry.lead}
      >
      </td>
      <Kit.part
        :for={{column, index} <- Enum.with_index(@model.columns)}
        part={:summary_cell}
        kit={@kit}
        id={"#{@id}-summary-#{column.name}"}
        column={column}
        colindex={Geometry.colindex(@geometry, index)}
        summary={@summary && @summary[column.name]}
        summing?={@summing?}
        time_zone={@time_zone}
        texts={Words.texts(:summary_cell, %{column: column})}
        messages={Words.messages(:summary_cell, %{column: column})}
        value={Words.value(:summary_cell, %{summary: @summary && @summary[column.name]})}
        text={
          Words.text(:summary_cell, %{
            column: column,
            summary: @summary && @summary[column.name],
            time_zone: @time_zone
          })
        }
        locale={Words.locale()}
      />
      <td
        :if={@geometry.trail == 1}
        id={"#{@id}-summaries-actions"}
        role="cell"
        aria-colindex={@geometry.colcount}
      >
      </td>
    </tr>
    """
  end
end
