defmodule DemoWeb.DivKit do
  @moduledoc """
  A kit of the demo's own (`AshDataTable.Kit`): the grid drawn with `div`s
  in place of a `<table>`, its rows, cells and footer too, and the action
  panel, the picker and the question opened in the page, not over it. It is what a kit of
  one's own looks like, and what the library's tests check a kit with: its
  markup is not the default's, and the table's hooks find everything by
  the markers alone (`AshDataTable.KitCase`, `e2e/kit.spec.ts`).

  The `div`s are laid out as a table is (`display: table` and its kin), so
  the columns line up; what is not a grid part is the default kit's. What
  it says is what each part is given (`texts`), in the person's language.
  """
  use AshDataTable.Kit, contract: 6

  alias AshDataTable.Attrs
  alias AshDataTable.Ids
  alias AshDataTable.Kit
  alias AshDataTable.Kit.Words

  def presentation(_thing), do: :inline

  def grid(assigns) do
    ~H"""
    <form :if={@geometry.header_rows == 2} {Attrs.filters(@id, @myself)}></form>
    <div {Attrs.sender(@id)}></div>
    <a {Attrs.skip(@id)} class="link absolute z-30 bg-base-100 not-focus:sr-only">
      {@texts.skip_table}
    </a>
    <div
      {Attrs.grid(@id, @myself, @geometry, @selecting, @choose, @texts)}
      class={@kit.class(:grid, %{nested?: @nested?})}
    >
      <div
        {Attrs.table(@id, @label, @labelledby, @geometry, @page, @busy? or not is_nil(@running))}
        class="table w-full border-collapse text-sm"
        data-kit="div"
      >
        <div id={Ids.head(@id)} role="rowgroup" class="table-header-group font-semibold">
          <div {Attrs.head_row(@id, @geometry)} class="table-row">
            <div
              :if={@selecting}
              {Attrs.header("#{@id}-select-head", "1", %{"data-select-page" => @selecting == :multi})}
              class="table-cell w-0 px-2 py-1"
            >
              <input
                :if={@selecting == :multi}
                type="checkbox"
                aria-label={@texts.select_page}
                class="checkbox checkbox-xs"
              />
              <span :if={@selecting == :single} class="sr-only">{@texts.select_row}</span>
            </div>
            <div
              :if={@expandable?}
              {Attrs.header("#{@id}-expander-head", @geometry.lead)}
              class="table-cell w-0 px-2 py-1"
            >
              <span class="sr-only">{@texts.related_records}</span>
            </div>
            <Kit.part
              :for={{column, index} <- Enum.with_index(@model.columns)}
              part={:header_cell}
              kit={@kit}
              id={Ids.header_cell(@id, column.name)}
              column={column}
              colindex={@geometry.lead + index + 1}
              attrs={
                Attrs.column_header(
                  column,
                  @state.sort,
                  @model.sticky_label? and not is_nil(@model.label_column) and
                    column.name == @model.label_column.name
                )
              }
              button={column.sortable? && Attrs.sort(@id, column, @myself)}
              sort={@state.sort}
              resizer={"#{@id}-resize-#{column.name}"}
              texts={Words.texts(:header_cell, %{column: column, editing?: @model.editing?})}
              messages={Words.messages(:header_cell, %{column: column, editing?: @model.editing?})}
            />
            <div
              :if={@geometry.trail == 1}
              {Attrs.header("#{@id}-actions-head", @geometry.colcount)}
              class="table-cell px-2 py-1"
            >
              {@texts.actions}
            </div>
          </div>
          <div
            :if={@geometry.header_rows == 2}
            {Attrs.filter_row(@id, @geometry)}
            class="table-row"
          >
            <div :if={@selecting} {Attrs.empty_cell("#{@id}-select-filter", "1")} class="table-cell">
            </div>
            <div
              :if={@expandable?}
              {Attrs.empty_cell("#{@id}-expander-filter", @geometry.lead)}
              class="table-cell"
            >
            </div>
            <Kit.part
              :for={{column, index} <- Enum.with_index(@model.columns)}
              part={:filter_cell}
              kit={@kit}
              id={"#{@id}-filter-#{column.name}"}
              column={column}
              colindex={@geometry.lead + index + 1}
              table={@id}
              form={Ids.filters(@id)}
              filter={@filters[column.name].filter}
              rejected?={@filters[column.name].rejected?}
              applied?={@filters[column.name].applied?}
              target={@myself}
            />
            <div
              :if={@geometry.trail == 1}
              {Attrs.empty_cell("#{@id}-actions-filter", @geometry.colcount)}
              class="table-cell"
            >
            </div>
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
              :if={Attrs.detail?(row) && row.lines}
              part={:detail}
              kit={@kit}
              id={@id}
              row={row}
              model={@model}
              colspan={@geometry.colcount}
              myself={@myself}
            /><Kit.part
              :if={!Attrs.detail?(row)}
              part={:row}
              kit={@kit}
              dom_id={dom_id}
              row={row}
              id={@id}
              columns={@model.columns}
              label={@model.label_column && @model.label_column.name}
              actions={@model.actions}
              geometry={@geometry}
              selecting={@selecting}
              expandable?={@expandable?}
              open={@open}
              asks?={@asks?}
              time_zone={@time_zone}
              texts={Words.texts(:row)}
              messages={Words.messages(:row)}
            /></div>
        <Kit.part
          :if={@nested? or @geometry.summary?}
          part={:footer}
          kit={@kit}
          expandable?={@expandable?}
          full_view={@full_view}
          geometry={@geometry}
          id={@id}
          label={@label}
          model={@model}
          myself={@myself}
          nested?={@nested?}
          page={@page}
          pages?={@pages?}
          row_count={@row_count}
          selecting={@selecting}
          state={@state}
          summary={@summary}
          summing?={@summing?}
          time_zone={@time_zone}
        />
      </div>
      <%!-- the editors are the default kit's, in the same templates --%>
      <template
        :for={column <- @model.columns}
        :if={column.editable?}
        {Attrs.editor_template(@id, column, @asks?)}
      >
        <Kit.editor
          kit={@kit}
          id={Ids.editor(@id, column.name)}
          column={column}
        />
      </template>
      <template :if={@model.editing? or @geometry.trail == 1} id={"#{@id}-failure"} phx-no-format><Kit.part part={:failure} kit={@kit} id={nil} message={Words.message(:failure, %{message: ""})} text={Words.text(:failure, %{message: ""})} /></template>
    </div>
    <div {Attrs.scrollbar(@id)} class="fixed z-10 overflow-x-scroll overflow-y-hidden">
      <div class="h-px"></div>
    </div>
    """
  end

  def header_cell(assigns) do
    ~H"""
    <div
      id={@id}
      role="columnheader"
      aria-colindex={@colindex}
      aria-label={@column.label}
      {@attrs}
      class="relative table-cell px-2 py-1 text-start whitespace-nowrap"
      phx-no-format
    ><button :if={@button} {@button} class="font-semibold">{@column.label}</button><%= if !@button do %>{@column.label}<% end %><Kit.part part={:resizer} kit={@kit} id={@resizer} column={@column} /></div>
    """
  end

  def filter_cell(assigns) do
    ~H"""
    <div
      id={@id}
      role="cell"
      aria-colindex={@colindex}
      data-filter={@column.operators != []}
      class="table-cell px-2 py-1"
    >
      <Kit.part
        :if={@column.operators != []}
        part={:filter}
        kit={@kit}
        id={@id}
        table={@table}
        form={@form}
        column={@column}
        filter={@filter}
        rejected?={@rejected?}
        applied?={@applied?}
        target={@target}
        texts={Words.texts(:filter, %{column: @column, filter: @filter})}
        messages={Words.messages(:filter, %{column: @column, filter: @filter})}
      />
    </div>
    """
  end

  def row(assigns) do
    ~H"""
    <div id={"#{@dom_id}-r"} role="row" aria-rowindex={@row.rowindex} class="table-row" phx-no-format><div
      :if={@selecting}
      id={Ids.selector(@dom_id)}
      role="cell"
      aria-colindex="1"
      data-selector
      class="table-cell px-2 py-1"
    ><input :if={@selecting == :multi} type="checkbox" aria-label={@texts.select_row} class="checkbox checkbox-xs" /><input :if={@selecting == :single} type="radio" name={"#{@id}-select"} aria-label={@texts.select_row} class="radio radio-xs" /></div><div
      :if={@expandable?}
      id={Ids.expander(@dom_id)}
      role="cell"
      aria-colindex={@geometry.lead}
      data-expander
      class="table-cell px-2 py-1"
    ><button type="button" aria-expanded={to_string(@row.open)} aria-label={@texts.related_records}></button></div><div
      :for={{column, index} <- Enum.with_index(@columns)}
      id={Ids.cell(@dom_id, column.name)}
      role={if column.name == @label, do: "rowheader", else: "cell"}
      aria-colindex={@geometry.lead + index + 1}
      {Attrs.cell(column, @row.cells[column.name])}
      class="table-cell px-2 py-1"
    ><Kit.cell kit={@kit} id={Ids.cell(@dom_id, column.name)} column={column} cell={@row.cells[column.name]} time_zone={@time_zone} /></div><Kit.part
      :if={@geometry.trail == 1}
      part={:actions_cell}
      kit={@kit}
      id={Ids.actions_cell(@dom_id)}
      colindex={@geometry.colcount}
      row={@row}
      actions={@actions}
      open={@open}
      asks?={@asks?}
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
      {Attrs.actions(@id, @row)}
      class="table-cell px-2 py-1 whitespace-nowrap"
      phx-no-format
    ><button
      :if={@open}
      type="button"
      id={"#{@id}-open"}
      data-open
      class="btn btn-xs me-1"
    >{@open}</button><button
      :for={action <- @actions}
      type="button"
      id={"#{@id}-#{action.name}"}
      data-action={action.name}
      {Attrs.action(action, @asks?)}
      class="btn btn-xs me-1"
    >{action.label}</button><Kit.part :if={@row.failure} part={:failure} kit={@kit} id={Ids.error(@id)} message={@row.failure.message} text={@row.failure.text} /></div>
    """
  end

  def detail(assigns) do
    ~H"""
    <Kit.part
      :for={{relationship, line} <- Enum.zip(@model.relationships, @row.lines)}
      part={:line}
      kit={@kit}
      id={Ids.row(@id, @row.key)}
      relationship={relationship}
      open?={line.open}
      count={line.count}
      colspan={@colspan}
      table={Ids.nested_table(Ids.row(@id, @row.key), relationship.name)}
      myself={@myself}
      texts={%{count: line.text}}
      messages={%{count: line.message}}
    />
    """
  end

  # A line spans the grid: a `div` laid out as a table cannot span
  # columns, so the line's cell is one of its own row, and says so
  # (`colspan`) for the hook.
  def line(assigns) do
    ~H"""
    <div id={"#{@id}-l-#{@relationship.name}"} role="row" class="table-row">
      <div
        id={Ids.line_cell(@id, @relationship.name)}
        role="cell"
        colspan={@colspan}
        aria-colindex="1"
        {Attrs.line(@relationship)}
        class="table-cell px-2 py-1"
      >
        <div class="flex flex-wrap items-center gap-2">
          <button
            type="button"
            id={Ids.line_button(@id, @relationship.name)}
            aria-expanded={to_string(@open?)}
            class="font-medium"
          >
            {@relationship.label}
          </button>
          <%!-- where the nested table's heading line goes --%>
          <div :if={@open?} id={Ids.line_heading(@id, @relationship.name)} class="grow"></div>
        </div>
      </div>
    </div>
    <div :if={@open?} id={Ids.nested_row(@id, @relationship.name)} role="row" class="table-row">
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
    <div
      id={"#{@id}-foot"}
      role="rowgroup"
      class="table-footer-group"
      hidden={
        not (@geometry.summary? and not is_nil(@page)) and
          not (@nested? and (@pages? or (not is_nil(@page) and not is_nil(@full_view))))
      }
    >
      <div
        :if={@geometry.summary? and @page}
        {Attrs.summaries(@id, @geometry, @page)}
        class="table-row"
      >
        <div
          :if={@selecting}
          id={"#{@id}-summaries-select"}
          role="cell"
          aria-colindex="1"
          class="table-cell"
        >
        </div>
        <div
          :if={@expandable?}
          id={"#{@id}-summaries-expander"}
          role="cell"
          aria-colindex={@geometry.lead}
          class="table-cell"
        >
        </div>
        <Kit.part
          :for={{column, index} <- Enum.with_index(@model.columns)}
          part={:summary_cell}
          kit={@kit}
          id={"#{@id}-summary-#{column.name}"}
          column={column}
          colindex={@geometry.lead + index + 1}
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
        <div
          :if={@geometry.trail == 1}
          id={"#{@id}-summaries-actions"}
          role="cell"
          aria-colindex={@geometry.colcount}
          class="table-cell"
        >
        </div>
      </div>
      <div
        :if={@nested? and @pages?}
        {Attrs.row("#{@id}-foot-row")}
        class="table-row"
      >
        <div
          {Attrs.spanning("#{@id}-pager", @geometry, %{"data-pager" => true})}
          class="table-cell px-2 py-1"
        >
          <Kit.part
            part={:pagination}
            kit={@kit}
            id={@id}
            {AshDataTable.Kit.Projection.of(:pagination, %{
              id: @id,
              nested?: true,
              page: @page,
              model: @model,
              state: @state,
              row_count: @row_count,
              label: @label,
              target: @myself
            })}
          />
        </div>
      </div>
      <Kit.part
        :if={@nested? and not is_nil(@page) and not is_nil(@full_view)}
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
    </div>
    """
  end

  # The summary of a column, as a cell of the footer row: what it is and
  # the number, both as the table says them in the person's language.
  def summary_cell(assigns) do
    ~H"""
    <div
      id={@id}
      role="cell"
      aria-colindex={@colindex}
      {Attrs.summary(@column, @summing?)}
      class="table-cell whitespace-nowrap"
    >
      <span :if={@column.summary}>{@texts.kind}{@text && " " <> @text}</span>
    </div>
    """
  end

  # The link to a nested table's full view, as the last row of its grid.
  def full_view(assigns) do
    ~H"""
    <div {Attrs.row("#{@id}-view-row")} class="table-row">
      <div
        {Attrs.spanning("#{@id}-view", @geometry, %{"data-view" => true})}
        class="table-cell px-2 py-1"
      >
        <.link
          id={"#{@id}-full-view"}
          navigate={@full_view}
          aria-label={@texts.full_view_of}
          class="link"
        >
          {@texts.full_view}
        </.link>
      </div>
    </div>
    """
  end
end
