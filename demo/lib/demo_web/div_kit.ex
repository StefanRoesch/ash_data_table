defmodule DemoWeb.DivKit do
  @moduledoc """
  A kit of the demo's own (`AshDataTable.Kit`): the grid drawn with `div`s
  in place of a `<table>`, its rows, cells and footer too, and the action
  panel, the picker and the question opened in the page, not over it. It is what a kit of
  one's own looks like, and what the library's tests check a kit with: its
  markup is not the default's, and the table's hooks find everything by
  the markers alone (`AshDataTable.KitCase`, `e2e/kit.spec.ts`).

  The `div`s are laid out as a table is (`display: table` and its kin), so
  the columns line up; what is not a grid part is the default kit's. It
  only draws: each part draws its projection (`AshDataTable.Kit.Projection`),
  the bundles, numbers and texts the table gives it, in the person's
  language.
  """
  use AshDataTable.Kit, contract: 6

  alias AshDataTable.Ids
  alias AshDataTable.Kit

  def presentation(_thing), do: :inline

  def grid(assigns) do
    ~H"""
    <form :if={@filter_form} {@filter_form}></form>
    <div {@sender}></div>
    <a {@skip} class="link absolute z-30 bg-base-100 not-focus:sr-only">
      {@texts.skip_table}
    </a>
    <div {@grid} class={@kit.class(:grid, %{nested?: @nested?})}>
      <div {@table} class="table w-full border-collapse text-sm" data-kit="div">
        <div id={Ids.head(@id)} role="rowgroup" class="table-header-group font-semibold">
          <div {@head.row} class="table-row">
            <div :if={@head.select} {@head.select.element} class="table-cell w-0 px-2 py-1">
              <input
                :if={@head.select.page?}
                type="checkbox"
                aria-label={@head.texts.select_page}
                class="checkbox checkbox-xs"
              />
              <span :if={!@head.select.page?} class="sr-only">{@head.texts.select_row}</span>
            </div>
            <div :if={@head.expander} {@head.expander} class="table-cell w-0 px-2 py-1">
              <span class="sr-only">{@texts.related_records}</span>
            </div>
            <Kit.part :for={cell <- @head.cells} part={:header_cell} kit={@kit} {cell} />
            <div :if={@head.actions} {@head.actions} class="table-cell px-2 py-1">
              {@texts.actions}
            </div>
          </div>
          <div :if={@filters} {@filters.row} class="table-row">
            <div :if={@filters.select} {@filters.select} class="table-cell"></div>
            <div :if={@filters.expander} {@filters.expander} class="table-cell"></div>
            <Kit.part :for={cell <- @filters.cells} part={:filter_cell} kit={@kit} {cell} />
            <div :if={@filters.actions} {@filters.actions} class="table-cell"></div>
          </div>
        </div>
        <div
          :for={{dom_id, row} <- @rows}
          id={dom_id}
          role="rowgroup"
          {row.attrs}
          class="table-row-group"
          phx-no-format
        ><Kit.part
              :if={Map.get(row, :detail) && row.lines}
              part={:detail}
              kit={@kit}
              id={@id}
              row={row}
              relationships={@row.relationships}
              colspan={@row.colspan}
            /><Kit.part
              :if={!Map.get(row, :detail)}
              part={:row}
              kit={@kit}
              row={row}
              {@row}
            /></div>
        <Kit.part :if={@footer} part={:footer} kit={@kit} id={@id} {@footer} />
      </div>
      <%!-- the editors are the default kit's, in the same templates --%>
      <template :for={editor <- @editors} {editor.template}>
        <Kit.editor kit={@kit} editor={editor} />
      </template>
      <template :if={@failure} {@failure.template} phx-no-format><Kit.part part={:failure} kit={@kit} id={nil} message={@failure.message} text={@failure.text} /></template>
    </div>
    <div {@scrollbar} class="fixed z-10 overflow-x-scroll overflow-y-hidden">
      <div class="h-px"></div>
    </div>
    """
  end

  def header_cell(assigns) do
    ~H"""
    <div
      {@element}
      role="columnheader"
      class="relative table-cell px-2 py-1 text-start whitespace-nowrap"
      phx-no-format
    ><button :if={@button} {@button} class="font-semibold">{@label}</button><%= if !@button do %>{@label}<% end %><Kit.part part={:resizer} kit={@kit} {@resizer} /></div>
    """
  end

  def filter_cell(assigns) do
    ~H"""
    <div {@element} role="cell" class="table-cell px-2 py-1">
      <Kit.part :if={@filter} part={:filter} kit={@kit} {@filter} />
    </div>
    """
  end

  def row(assigns) do
    ~H"""
    <div
      id={Ids.record(@row.dom_id)}
      role="row"
      aria-rowindex={@row.rowindex}
      class="table-row"
      phx-no-format
    ><div
      :if={@selecting}
      id={Ids.selector(@row.dom_id)}
      role="cell"
      aria-colindex="1"
      data-selector
      class="table-cell px-2 py-1"
    ><input :if={@selecting == :multi} type="checkbox" aria-label={@texts.select_row} class="checkbox checkbox-xs" /><input :if={@selecting == :single} type="radio" name={@radio} aria-label={@texts.select_row} class="radio radio-xs" /></div><div
      :if={@expandable?}
      id={Ids.expander(@row.dom_id)}
      role="cell"
      aria-colindex={@lead}
      data-expander
      class="table-cell px-2 py-1"
    ><button type="button" aria-expanded={to_string(@row.open)} aria-label={@texts.related_records}></button></div><div
      :for={column <- @columns}
      id={Ids.cell(@row.dom_id, column.name)}
      role={if column.header?, do: "rowheader", else: "cell"}
      aria-colindex={column.colindex}
      {Map.merge(column.attrs, @row.cells[column.name].attrs)}
      class="table-cell px-2 py-1"
    ><Kit.cell kit={@kit} id={Ids.cell(@row.dom_id, column.name)} column={column} cell={@row.cells[column.name]} /></div><Kit.part
      :if={@actions}
      part={:actions_cell}
      kit={@kit}
      id={Ids.actions_cell(@row.dom_id)}
      row={@row}
      {@actions}
    /></div>
    """
  end

  def actions_cell(assigns) do
    ~H"""
    <div
      id={@id}
      role="cell"
      aria-colindex={@colindex}
      data-actions
      data-failed={!!@row.failure}
      aria-describedby={@row.failure && Ids.error(@id)}
      class="table-cell px-2 py-1 whitespace-nowrap"
      phx-no-format
    ><button
      :if={@open}
      type="button"
      id={Ids.open(@id)}
      data-open
      class="btn btn-xs me-1"
    >{@open}</button><button
      :for={action <- @buttons}
      type="button"
      id={Ids.action(@id, action.name)}
      data-action={action.name}
      {action.attrs}
      class="btn btn-xs me-1"
    >{action.label}</button><Kit.part :if={@row.failure} part={:failure} kit={@kit} id={Ids.error(@id)} message={@row.failure.message} text={@row.failure.text} /></div>
    """
  end

  def detail(assigns) do
    ~H"""
    <Kit.part
      :for={{relationship, line} <- Enum.zip(@relationships, @row.lines)}
      part={:line}
      kit={@kit}
      id={Ids.row(@id, @row.key)}
      relationship={relationship}
      line={line}
      colspan={@colspan}
      table={Ids.nested_table(Ids.row(@id, @row.key), relationship.name)}
    />
    """
  end

  # A line spans the grid: a `div` laid out as a table cannot span
  # columns, so the line's cell is one of its own row, and says so
  # (`colspan`) for the hook.
  def line(assigns) do
    ~H"""
    <div id={Ids.line(@id, @relationship.name)} role="row" class="table-row">
      <div
        id={Ids.line_cell(@id, @relationship.name)}
        role="cell"
        colspan={@colspan}
        aria-colindex="1"
        {@relationship.cell}
        class="table-cell px-2 py-1"
      >
        <div class="flex flex-wrap items-center gap-2">
          <button
            type="button"
            id={Ids.line_button(@id, @relationship.name)}
            aria-expanded={to_string(@line.open)}
            class="font-medium"
          >
            {@relationship.label}
          </button>
          <%!-- where the nested table's heading line goes --%>
          <div :if={@line.open} id={Ids.line_heading(@id, @relationship.name)} class="grow"></div>
        </div>
      </div>
    </div>
    <div :if={@line.open} id={Ids.nested_row(@id, @relationship.name)} role="row" class="table-row">
      <div
        id={Ids.nested_cell(@id, @relationship.name)}
        role="cell"
        colspan={@colspan}
        aria-colindex="1"
        data-nested
        data-line-cell={Ids.line_cell(@id, @relationship.name)}
        data-expander-cell={Ids.expander(@id)}
        class="table-cell p-0"
      >
      </div>
    </div>
    """
  end

  def footer(assigns) do
    ~H"""
    <div {@element} role="rowgroup" class="table-footer-group">
      <div :if={@summaries} {@summaries.row} class="table-row">
        <div :if={@summaries.select} {@summaries.select} class="table-cell"></div>
        <div :if={@summaries.expander} {@summaries.expander} class="table-cell"></div>
        <Kit.part :for={cell <- @summaries.cells} part={:summary_cell} kit={@kit} {cell} />
        <div :if={@summaries.actions} {@summaries.actions} class="table-cell"></div>
      </div>
      <div :if={@pager} {@pager.row} class="table-row">
        <div {@pager.cell} class="table-cell px-2 py-1">
          <Kit.part part={:pagination} kit={@kit} id={@id} {@pager.pagination} />
        </div>
      </div>
      <Kit.part :if={@full_view} part={:full_view} kit={@kit} id={@id} {@full_view} />
    </div>
    """
  end

  # The summary of a column, as a cell of the footer row: what it is and
  # the number, both as the table says them in the person's language.
  def summary_cell(assigns) do
    ~H"""
    <div {@element} role="cell" class="table-cell whitespace-nowrap">
      <span :if={@summary?}>{@texts.kind}{@text && " " <> @text}</span>
    </div>
    """
  end

  # The link to a nested table's full view, as the last row of its grid.
  def full_view(assigns) do
    ~H"""
    <div {@row} class="table-row">
      <div {@cell} class="table-cell px-2 py-1">
        <.link id={@link.id} navigate={@link.path} aria-label={@texts.full_view_of} class="link">
          {@texts.full_view}
        </.link>
      </div>
    </div>
    """
  end
end
