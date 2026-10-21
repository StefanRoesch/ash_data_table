defmodule AshDataTable.Parts.Grid do
  @moduledoc false
  # The grid: the header row, the filter row, the rows and their cells,
  # the editors the hook copies into a cell, and the "Columns" list. The
  # parts `grid`, `header_cell`, `filter_cell`, `row`, `cell`,
  # `actions_cell`, `resizer`, `editor` and `columns` of
  # `AshDataTable.Kit.Default`; what a part draws inside it, it draws
  # through the kit (`Parts.Common.part/1`), so that a kit that replaces
  # one part keeps the others.
  use Phoenix.Component

  alias AshDataTable.Ids
  alias AshDataTable.Kit
  alias AshDataTable.Parts
  alias AshDataTable.Parts.Common
  alias AshDataTable.Present

  # The handle at the end of a column's header, with which a person makes
  # the column wider or narrower: dragged with the pointer, for the pointer
  # alone (`aria-hidden`, no Tab stop): the keyboard has the width fields in
  # the list of "Columns" (`columns/1`). It is not seen until it is pointed
  # at or dragged: then a line at the column's edge.
  #
  # Nothing of this reaches the server: the widths are the hook's, kept in a
  # style sheet of its own, and are gone with the page (see "the widths of
  # the columns" in the hook). Its projection (`AshDataTable.Kit.Projection`,
  # a header cell's `resizer`).
  attr :element, :map, required: true

  def resizer(assigns) do
    ~H"""
    <span
      {@element}
      aria-hidden="true"
      data-resize
      class="absolute inset-y-0 end-0 w-3 cursor-col-resize touch-none select-none [&:is(:hover,[data-dragging])]:after:absolute [&:is(:hover,[data-dragging])]:after:inset-y-0 [&:is(:hover,[data-dragging])]:after:end-0 [&:is(:hover,[data-dragging])]:after:border-e-2 [&:is(:hover,[data-dragging])]:after:border-base-content [&:is(:hover,[data-dragging])]:after:content-['']"
    ></span>
    """
  end

  # "Columns": the button above the grid that opens the list of the table's
  # columns, with a box each. A column whose box is not ticked is hidden.
  #
  # Hidden in the browser, and nowhere else: the server reads the column and
  # renders it as before, and never hears which columns a person hid. The
  # hook hides them with rules of its own style sheet, beside the widths
  # (see "hiding columns" in the hook), and they are back when the page is
  # loaded again. So what depends on it is the hook's to put in: the text
  # of the button, which says how many are hidden, which boxes are ticked,
  # and what is read out. The server renders the button with its plain
  # text and every box ticked. Its patches leave the button's text, whether
  # the list is open and where it stands alone; a box they tick again, which
  # the hook sees and puts right before anything is drawn.
  #
  # It is a disclosure, not a menu: a button and a group of labelled boxes,
  # each with the width field of its column beside it (`Attrs.width_field/3`,
  # a number in pixels the hook fills in as the list opens and sets the
  # column's width from), and "Reset widths" after them: the keyboard's way
  # to the widths, which the handle gives the pointer.
  # The list is the browser's own popover (`popover="auto"`), which the
  # button opens and closes (`popovertarget`): it stands in the top layer,
  # so that nothing around the table cuts it off (not the grid that
  # scrolls sideways around a nested table, not a dialog), a click
  # elsewhere and Escape close it, and the button says whether it is open.
  # It is placed under the button by CSS anchor positioning (the button's
  # `anchor-name`, the list's `position-anchor` and `position-area`);
  # where a browser has none, it opens in the middle of the window. It looks
  # as daisyUI 5's dropdown that is a popover does (`dropdown menu` on the
  # popover itself, `rounded-box bg-base-100 shadow-sm`); `flex-nowrap`
  # keeps a long list in one column that scrolls, where `menu` would wrap.
  #
  # `columns` are the columns that can be hidden (every one but the label
  # column), and `label_column` the label column (nil for none), which
  # cannot: its entry
  # comes first, its name and its width field, with no box.
  # A column that is filtered or sorted by says so at its box, in text, for
  # as long as it is hidden (`data-flag`, shown while the box is not
  # ticked): its filter is in the header row, and goes out of sight with
  # it. What the server says for the hook:
  #
  #   * `data-head` at a box is the id of the column's header;
  #   * `data-filtered` and `data-sorted` at a box, that the rows are
  #     filtered or sorted by its column;
  #   * `data-keeps-one` at the list, that one column has to stay (the
  #     table has no column of its label, which would);
  #   * at the button, what it says of the hidden columns for every number
  #     from 1 to the number of columns (`data-text-hidden`,
  #     `data-text-filtered`, `data-text-sorted`, each a JSON list, the
  #     text for 1 first), and the text they are put into, with `{details}`
  #     where the hook puts them, a comma between;
  #   * at a box, what is read out when its column is hidden and shown
  #     again (`data-say-hidden`, `data-say-shown`).
  #
  # The button shows an eye struck through, "Columns" and, while columns are
  # hidden, how many in a badge; what it is called is the text the hook
  # writes (`ID-columns-text`, out of sight: "Columns (2 hidden)", of a
  # nested table "Columns of Comments (2 hidden)"), which begins with what
  # it shows. The badge is the hook's too (`ID-columns-count`), empty and
  # out of sight while nothing is hidden. A Tab stop, in a nested table too,
  # where it stands on the table's line.
  # Its projection (`AshDataTable.Kit.Projection`, the heading's `columns`):
  # the button and the list, the label column's entry (`label`, nil for
  # none), an entry per column that can be hidden, "Reset widths"; `class`
  # is its look, which the part that draws it gives.
  attr :id, :string, required: true
  attr :control, :map, required: true
  attr :button, :map, required: true
  attr :text, :map, required: true
  attr :count, :map, required: true
  attr :list, :map, required: true
  attr :status, :map, required: true
  attr :label, :map, required: true
  attr :entries, :list, required: true
  attr :reset, :map, required: true
  attr :least, :integer, required: true
  attr :most, :integer, required: true
  attr :class, :any, required: true
  attr :texts, :map, required: true
  attr :messages, :map, required: true

  def columns(assigns) do
    ~H"""
    <div {@control} class={@class}>
      <button
        type="button"
        {@button}
        style={"anchor-name: #{anchor(@id)}"}
        class="btn btn-ghost btn-sm gap-1 px-2"
      >
        <svg
          aria-hidden="true"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.6"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="size-4"
        >
          <path d="M3.98 8.22A10.48 10.48 0 0 0 1.93 12C3.23 16.34 7.24 19.5 12 19.5c.99 0 1.95-.14 2.86-.4M6.23 6.23A10.45 10.45 0 0 1 12 4.5c4.76 0 8.77 3.16 10.07 7.5a10.52 10.52 0 0 1-4.29 5.77M6.23 6.23 3 3m3.23 3.23 3.65 3.65m7.89 7.89L21 21m-3.23-3.23-3.65-3.65m0 0a3 3 0 1 0-4.24-4.24m4.24 4.24L9.88 9.88" />
        </svg>
        <span aria-hidden="true">{@texts.columns}</span>
        <span {@text} phx-update="ignore" class="sr-only">
          {@texts.columns_name}
        </span>
        <span
          {@count}
          phx-update="ignore"
          aria-hidden="true"
          class="badge badge-xs badge-neutral empty:hidden"
        ></span>
      </button>
      <div
        {@list}
        style={"position-anchor: #{anchor(@id)}"}
        class="dropdown menu max-h-[60vh] flex-nowrap overflow-y-auto rounded-box bg-base-100 p-2 text-base-content shadow-sm forced-colors:border [position-area:bottom_span-right] [position-try-fallbacks:flip-inline,flip-block] supports-[position-area:bottom]:inset-auto supports-[position-area:bottom]:m-0 supports-[position-area:bottom]:mt-0.5"
      >
        <div :if={@label} class="flex items-center gap-2">
          <span class="grow py-0.5 ps-7 pe-1 whitespace-nowrap">{@label.label}</span>
          <input
            type="number"
            min={@least}
            max={@most}
            {@label.width}
            class="input input-xs w-20"
          />
        </div>
        <div :for={entry <- @entries} class="flex items-center gap-2">
          <label
            {entry.entry}
            class="flex grow cursor-pointer items-center gap-2 px-1 py-0.5 whitespace-nowrap"
          >
            <input
              type="checkbox"
              {entry.box}
              checked
              class={["peer checkbox checkbox-xs", Parts.Editors.box_edge()]}
            />
            <span>{entry.label}</span>
            <span :if={entry.flag} data-flag class="peer-checked:hidden">
              ({entry.flag})
            </span>
          </label>
          <input
            type="number"
            min={@least}
            max={@most}
            {entry.width}
            class="input input-xs w-20"
          />
        </div>
        <button {@reset} class="btn btn-ghost btn-xs mt-1 self-start">
          {@texts.reset_widths}
        </button>
      </div>
      <%!-- What the hook says when a column is hidden or shown again. A live
      region of its own: the one above the grid is rendered by the server,
      and would say its last text once more when the next patch put it back. --%>
      <p {@status} role="status" phx-update="ignore" class="sr-only"></p>
    </div>
    """
  end

  # What a cell of an editable column is edited with: the native control of
  # its cell type, without a name or a form, as the hook reads its value and
  # sends it. It takes the place of the cell's text, so it has the text's
  # size and no border of its own; the cell shows the focus.
  #
  # `id` is the id of the editor's `<template>`. What is in a template is
  # not in the page, and one copy of it at most is: an id that starts with
  # it is the id of one element.
  #
  # A column whose component edits has the component's editor instead
  # (`grid/1`); the kit's `editor/1` draws the others. Its projection
  # (`AshDataTable.Kit.Projection`, an editor of `grid`'s `editors`): what
  # the control says (the limits of a number, the counter of a text and its
  # control's bundle, whether a sensitive cell can be emptied).
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :editor, :atom, required: true
  attr :required?, :boolean, required: true
  attr :sensitive?, :boolean, required: true
  attr :values, :list, required: true
  attr :limits, :map, required: true
  attr :counted, :map, required: true
  attr :count, :map, required: true
  attr :control, :map, required: true
  attr :clearable?, :boolean, required: true
  attr :kit, :atom, required: true
  attr :texts, :map, required: true
  attr :messages, :map, required: true

  # A sensitive column, which is text or a number: a password input, so that
  # what is typed is not shown. The hook opens it empty.
  #
  # Left empty it saves nothing, so nothing typed into it empties the cell.
  # Where the cell can be empty (`clearable?`), a button
  # beside the input does: "Clear", named with the column. The two are the
  # editor then, and the input is its control. The hook takes the button
  # out for a cell that holds nothing.
  def editor(%{sensitive?: true} = assigns) do
    ~H"""
    <input
      :if={!@clearable?}
      type="password"
      autocomplete="off"
      aria-label={@label}
      class="block h-5 w-full min-w-24 bg-transparent p-0 text-sm outline-none"
    />
    <div :if={@clearable?} class="flex w-full min-w-24 items-center gap-2">
      <input
        type="password"
        autocomplete="off"
        data-control
        aria-label={@label}
        class="block h-5 w-0 min-w-12 flex-1 bg-transparent p-0 text-sm outline-none"
      />
      <button
        type="button"
        data-clear
        aria-label={@texts.clear_value}
        class="btn btn-xs -my-1 shrink-0"
      >
        {@texts.clear}
      </button>
    </div>
    """
  end

  # Text is edited in a textarea, so that text of several lines keeps its
  # lines. It is one line high until the text needs more.
  #
  # A text with a most it can be long has its counter with it, under the
  # textarea at its end: the row grows by a line while the editor is open,
  # and the column keeps its width. The two are the editor; the textarea is
  # its control.
  def editor(%{editor: :text} = assigns) do
    ~H"""
    <textarea
      :if={!@counted}
      rows="1"
      aria-label={@label}
      aria-required={@required? && "true"}
      class="block w-full min-w-40 resize-none bg-transparent p-0 text-sm break-words whitespace-pre-wrap outline-none"
    ></textarea>
    <div :if={@counted}>
      <textarea
        rows="1"
        {@control}
        class="block w-full min-w-40 resize-none bg-transparent p-0 text-sm break-words whitespace-pre-wrap outline-none"
      ></textarea>
      <Kit.part
        part={:count}
        kit={@kit}
        class="block text-end"
        {@count}
      />
    </div>
    """
  end

  # A boolean has no editor that takes the focus: Enter on the cell toggles
  # it, and the hook shows this box in the cell while the value is saved
  # (`inert`: no Tab stop, the cell is).
  def editor(%{editor: :boolean} = assigns) do
    ~H"""
    <input
      type="checkbox"
      inert
      aria-label={@label}
      class="checkbox checkbox-xs pointer-events-none"
    />
    """
  end

  def editor(%{editor: :enum} = assigns) do
    ~H"""
    <select
      aria-label={@label}
      aria-required={@required? && "true"}
      class="block h-5 w-full bg-transparent p-0 text-sm outline-none"
    >
      <option :if={not @required?} value=""></option>
      <option :for={choice <- @values} value={choice.value}>{choice.label}</option>
    </select>
    """
  end

  # The control of a number says what the attribute's constraints say of it
  # (`limits`). Nothing in the browser checks it against them: the hook
  # sends what the control holds, and Ash says what is wrong with it.
  def editor(assigns) do
    ~H"""
    <input
      type={Parts.Editors.input_type(@editor)}
      step={@limits.step || Parts.Editors.input_step(@editor)}
      min={@limits.min}
      max={@limits.max}
      aria-label={@label}
      aria-required={@required? && "true"}
      class="block h-5 w-full min-w-24 bg-transparent p-0 text-sm outline-none"
    />
    """
  end

  # The header of a column: its label, the mark of the sort, the handle
  # that resizes it (the kit's `resizer/1`). Its role and scope are written
  # here, as of every element drawn once per column; its id, place, name and
  # what varies (`aria-sort`, `data-sort`, `data-label`, …) are its
  # `element`. A column that sorts has its label and mark in a button
  # (`button`), the header's only Tab stop; the header says the direction
  # (`aria-sort`). A header that does not sort is no stop. Its projection
  # (`AshDataTable.Kit.Projection`, a cell of `grid`'s `head`).
  attr :element, :map, required: true
  attr :label, :string, required: true
  # the sort button's bundle, nil where the column does not sort
  attr :button, :map, required: true
  attr :mark, :string, required: true
  attr :resizer, :map, required: true
  attr :kit, :atom, required: true
  attr :texts, :map, required: true
  attr :messages, :map, required: true

  def header_cell(assigns) do
    ~H"""
    <th
      {@element}
      role="columnheader"
      scope="col"
      class="relative whitespace-nowrap"
      phx-no-format
    ><button :if={@button} {@button} class="cursor-pointer select-none rounded-sm font-[inherit] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-current">{@label}<span aria-hidden="true">{@mark}</span></button><%= if !@button do %>{@label}<% end %><svg :if={@texts.read_only} role="img" aria-label={@texts.read_only} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="ms-1 inline-block size-3 align-[-1px] opacity-60"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg><Kit.part part={:resizer} kit={@kit} {@resizer} /></th>
    """
  end

  # The cell of a column in the filter row, with the column's filter (the
  # kit's `filter/1`) where the column has one (`data-filter`). Its
  # projection (`AshDataTable.Kit.Projection`, a cell of `grid`'s
  # `filters`).
  attr :element, :map, required: true
  attr :filter, :map, required: true
  attr :kit, :atom, required: true

  def filter_cell(assigns) do
    ~H"""
    <td
      {@element}
      role="cell"
    >
      <Kit.part
        :if={@filter}
        part={:filter}
        kit={@kit}
        {@filter}
      />
    </td>
    """
  end

  # The row of a record: the box that selects it, its expander, a cell per
  # column and the actions cell (the kit's `actions_cell/1`). Written without whitespace on purpose: every byte of a
  # row is sent again whenever the row is, and a cell's text must not be
  # padded. The constant attributes of the row and its cells are written
  # here; what varies is the item's (its cells' `attrs`: an editable cell's
  # `tabindex="0"` among it), beside the column's own (its `attrs`). What
  # a cell holds is the column's component's, else the kit's `cell/1`'s.
  #
  # The cell of the label column (its column's `header?`) is the row's
  # header (`<th scope="row" role="rowheader">`), which names the row as a
  # screen reader moves down a column. It is drawn between the cells
  # before it and those after it, so that every other cell keeps its
  # constant role in the markup, not in what is sent with each row. The
  # box and the expander are no Tab stops themselves: their controls are.
  #
  # `row` is the item of the stream (`AshDataTable.Item`); the rest is its
  # projection (`AshDataTable.Kit.Projection`, `grid`'s `row`), the same
  # for every row.
  attr :row, :any, required: true
  attr :selecting, :any, required: true
  attr :radio, :string, required: true
  attr :expandable?, :boolean, required: true
  attr :lead, :integer, required: true
  attr :columns, :list, required: true
  attr :actions, :map, required: true
  attr :relationships, :list, required: true
  attr :colspan, :integer, required: true
  attr :kit, :atom, required: true
  attr :texts, :map, required: true
  attr :messages, :map, required: true

  def row(assigns) do
    ~H"""
    <tr
      id={Ids.record(@row.dom_id)}
      role="row"
      aria-rowindex={@row.rowindex}
      phx-no-format
    ><td
      :if={@selecting}
      id={Ids.selector(@row.dom_id)}
      role="cell"
      aria-colindex="1"
      data-selector
    ><input :if={@selecting == :multi} type="checkbox" aria-label={@texts.select_row} class="checkbox checkbox-xs border-base-content/50" /><input :if={@selecting == :single} type="radio" name={@radio} aria-label={@texts.select_row} class="radio radio-xs border-base-content/50" /></td><td
      :if={@expandable?}
      id={Ids.expander(@row.dom_id)}
      role="cell"
      aria-colindex={@lead}
      data-expander
    ><button type="button" aria-expanded={to_string(@row.open)} aria-label={@texts.related_records}></button></td><td
      :for={{column, cell} <- cells(@columns, @row, :before)}
      id={Ids.cell(@row.dom_id, column.name)}
      role="cell"
      aria-colindex={column.colindex}
      {Map.merge(column.attrs, cell.attrs)}
    ><Common.dynamic_component
      :if={component?(column, cell)}
      module={column.component.module}
      function={:cell}
      value={cell.value}
      text={cell.text}
      column={column.component.column}
    /><Kit.part
      :if={!component?(column, cell)}
      part={:cell}
      kit={@kit}
      id={Ids.cell(@row.dom_id, column.name)}
      cell={cell}
      {column}
    /></td><th
      :for={{column, cell} <- cells(@columns, @row, :label)}
      id={Ids.cell(@row.dom_id, column.name)}
      scope="row"
      role="rowheader"
      aria-colindex={column.colindex}
      {Map.merge(column.attrs, cell.attrs)}
      class="text-start font-normal"
    ><Common.dynamic_component
      :if={component?(column, cell)}
      module={column.component.module}
      function={:cell}
      value={cell.value}
      text={cell.text}
      column={column.component.column}
    /><Kit.part
      :if={!component?(column, cell)}
      part={:cell}
      kit={@kit}
      id={Ids.cell(@row.dom_id, column.name)}
      cell={cell}
      {column}
    /></th><td
      :for={{column, cell} <- cells(@columns, @row, :after)}
      id={Ids.cell(@row.dom_id, column.name)}
      role="cell"
      aria-colindex={column.colindex}
      {Map.merge(column.attrs, cell.attrs)}
    ><Common.dynamic_component
      :if={component?(column, cell)}
      module={column.component.module}
      function={:cell}
      value={cell.value}
      text={cell.text}
      column={column.component.column}
    /><Kit.part
      :if={!component?(column, cell)}
      part={:cell}
      kit={@kit}
      id={Ids.cell(@row.dom_id, column.name)}
      cell={cell}
      {column}
    /></td><Kit.part
      :if={@actions}
      part={:actions_cell}
      kit={@kit}
      id={Ids.actions_cell(@row.dom_id)}
      row={@row}
      {@actions}
    /></tr>
    """
  end

  # The cells of a record's row, before the label column's cell, that cell,
  # or after it: each column, and what the row's item (`AshDataTable.Item`)
  # says of the cell. Without a label column every cell is before it.
  defp cells(columns, row, part) do
    {before, rest} = Enum.split_while(columns, &(not &1.header?))
    {labelled, behind} = Enum.split(rest, 1)
    taken = %{before: before, label: labelled, after: behind}

    for column <- taken[part], do: {column, row.cells[column.name]}
  end

  # What a cell of a record holds: the
  # column's component draws a value that is there and that the person may
  # see; anything else is the kit's `cell/1`'s (`AshDataTable.Kit.cell/1`
  # for a kit's own row; written out here, as a component of its own would
  # send one more level of every cell of every row).
  defdelegate component?(column, cell), to: Kit
  # What a cell of a record shows (`AshDataTable.Kit.Default.cell/1`):
  # its value, as the column's type shows it, nothing where it is empty,
  # the mask of a sensitive value, "Not available" for the eye of nobody
  # where the person may not see it. A cell whose save failed shows what
  # was typed, as the cell would show it had it been saved (its column's
  # `typed`), and holds the action's message (the kit's `failure/1`); a
  # sensitive one what it shows at rest, never what was typed. `cell` is
  # the item's cell; the rest is its column's projection
  # (`AshDataTable.Kit.Projection`, a column of `grid`'s `row`).
  attr :id, :string, required: true
  attr :cell, :map, required: true
  attr :name, :atom, required: true
  attr :label, :string, required: true
  attr :colindex, :integer, required: true
  attr :header?, :boolean, required: true
  attr :cell_type, :any, required: true
  attr :editor, :atom, required: true
  attr :max_lines, :integer, required: true
  attr :sensitive?, :boolean, required: true
  attr :values, :list, required: true
  attr :attrs, :map, required: true
  attr :component, :map, required: true
  attr :typed, :map, required: true
  attr :kit, :atom, required: true
  attr :texts, :map, required: true
  attr :messages, :map, required: true
  attr :locale, :string, required: true

  def cell(%{cell: %{failure: nil}} = assigns) do
    ~H"""
    {shown(@cell.state, @cell.value, @cell.text, @max_lines, @texts)}
    """
  end

  def cell(%{sensitive?: true} = assigns) do
    ~H"""
    {shown(@cell.state, nil, nil, @max_lines, @texts)}<Kit.part
      part={:failure}
      kit={@kit}
      id={Ids.error(@id)}
      message={@cell.failure.message}
      text={@cell.failure.text}
    />
    """
  end

  def cell(assigns) do
    ~H"""
    {@cell.failure.typed |> typed(@editor, @typed) |> paragraph(@max_lines)}<Kit.part
      part={:failure}
      kit={@kit}
      id={Ids.error(@id)}
      message={@cell.failure.message}
      text={@cell.failure.text}
    />
    """
  end

  # The cell of a record's actions: "Open" where the page offers it, a
  # button per row action, and the message of an action that failed (the
  # kit's `failure/1`). `id` is the cell's, `row` the item, which says
  # whether its action failed; the rest is its projection
  # (`AshDataTable.Kit.Projection`, `grid`'s `row`'s `actions`).
  attr :id, :string, required: true
  attr :row, :any, required: true
  attr :colindex, :integer, required: true
  attr :open, :any, required: true
  attr :buttons, :list, required: true
  attr :kit, :atom, required: true

  def actions_cell(assigns) do
    ~H"""
    <td
      id={@id}
      role="cell"
      aria-colindex={@colindex}
      data-actions
      data-failed={!!@row.failure}
      aria-describedby={@row.failure && Ids.error(@id)}
      phx-no-format
    ><button
      :if={@open}
      type="button"
      id={Ids.open(@id)}
      data-open
      class="btn btn-xs -my-1 me-1"
    >{@open}</button><button
      :for={action <- @buttons}
      type="button"
      id={Ids.action(@id, action.name)}
      data-action={action.name}
      {action.attrs}
      class="btn btn-xs -my-1 me-1"
    >{action.label}</button><Kit.part :if={@row.failure} part={:failure} kit={@kit} id={Ids.error(@id)} message={@row.failure.message} text={@row.failure.text} /></td>
    """
  end

  # The text of a cell whose column says `max_lines` is a paragraph: that is
  # what wraps and is cut off after the last line. An empty cell holds
  # nothing, as everywhere.
  defp paragraph(shown, 1), do: shown

  defp paragraph(shown, _max_lines) do
    {:safe, shown} = Phoenix.HTML.html_escape(shown)

    if IO.iodata_length(shown) == 0,
      do: {:safe, shown},
      else: {:safe, [~s(<p data-paragraph>), shown, "</p>"]}
  end

  # What was typed into an editor, as its cell shows it (its column's
  # `typed`: a yes or no with its mark, as a boolean's cell shows it; an
  # enum's label), else as it was typed.
  defp typed(typed, :boolean, said) when typed in ["true", "false"],
    do: value(typed == "true", said[typed])

  defp typed(typed, _editor, said), do: Map.get(said || %{}, typed, typed)

  # What a cell shows, by what it holds (a cell of `AshDataTable.Item`),
  # in the words it is given (`text`, `texts`).
  #
  # A field the actor may not see on this row looks empty and is announced.
  defp shown(:forbidden, _value, _text, _max_lines, texts) do
    {:safe, [~s(<span class="sr-only" data-unseen>), escape(texts.not_available), "</span>"]}
  end

  # A record that has no value has an empty cell, whatever its column: what
  # "empty" looks like is the table's to say, in one way for all columns.
  defp shown(:empty, _value, _text, _max_lines, _texts), do: ""

  # A sensitive value is not shown: the cell holds a mask, the same for
  # every value and for the eye only, what a screen reader says in its
  # place, an empty live region the hook puts the value into when a person
  # asks for it, and the button that asks. The button is named with the
  # column, as every row has one. A cell without a value is empty, as any
  # cell is: that there is nothing is all it says.
  #
  # What is rendered is the same whatever the value is; the value itself is
  # not in what a row is rendered from (`AshDataTable.Present`).
  defp shown(:masked, _value, _text, _max_lines, texts) do
    {:safe,
     [
       ~s(<span class="inline-flex max-w-72 items-center align-bottom"><span data-mask aria-hidden="true">),
       Present.mask(),
       ~s(</span><span data-masked class="sr-only">),
       escape(texts.hidden_value),
       ~s(</span><span data-secret aria-live="polite" class="min-w-0 truncate"></span>),
       ~s(<button type="button" data-reveal data-show="),
       escape(texts.show),
       ~s(" data-hide="),
       escape(texts.hide),
       ~s(" data-show-label="),
       escape(texts.show_value),
       ~s(" data-hide-label="),
       escape(texts.hide_value),
       ~s(" aria-label="),
       escape(texts.show_value),
       ~s(" class="btn btn-xs -my-1 ms-2 shrink-0">),
       escape(texts.show),
       "</button></span>"
     ]}
  end

  defp shown(:value, value, text, max_lines, _texts),
    do: value |> value(text) |> paragraph(max_lines)

  # A value as a cell of its column shows it, `text` the words of it (a
  # union's are those of the kind it holds, the item says). A yes or no is
  # a check indicator with its accessible text beside it.
  defp value(value, text) when is_boolean(value) do
    assigns = %{mark: if(value, do: "✓", else: "–"), text: text}

    ~H"""
    <span aria-hidden="true">{@mark}</span><span class="sr-only" data-unseen>{@text}</span>
    """
  end

  # everything else is plain text
  defp value(_value, text), do: text || ""

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  # Its projection (`AshDataTable.Kit.Projection`, `grid`); `rows` the
  # items of the table's stream.
  attr :id, :string, required: true
  attr :rows, :any, required: true
  attr :nested?, :boolean, required: true
  attr :sender, :map, required: true
  attr :skip, :map, required: true
  attr :scrollbar, :map, required: true
  attr :filter_form, :map, required: true
  attr :grid, :map, required: true
  attr :table, :map, required: true
  attr :head, :map, required: true
  attr :filters, :map, required: true
  attr :row, :map, required: true
  attr :footer, :map, required: true
  attr :editors, :list, required: true
  attr :failure, :map, required: true
  attr :kit, :atom, required: true
  attr :texts, :map, required: true
  attr :messages, :map, required: true

  def grid(assigns) do
    ~H"""
    <%!-- The form of the filter row, where there is one. A form cannot sit
    inside a table around its cells, so the controls name it instead. --%>
    <form :if={@filter_form} {@filter_form}></form>
    <%!-- The grid is the table's own scroll area: every table scrolls
    sideways in its own, a nested table as the table on the page (see
    "scrolling sideways" in the hook). A nested table that is scrolled to
    its end does not go on to scroll the table around it. Its attributes are
    `AshDataTable.Attrs.grid/6`'s. Before it the sender of its events,
    which LiveView locks while one is on its way, in place of the grid. --%>
    <div {@sender}></div>
    <%!-- "Skip table NAME": the first Tab stop of the grid, seen only while it
    has the focus, over the table's top left; it jumps past the table, to
    the end of its root (the kit's `root/1`). --%>
    <a
      {@skip}
      class="btn btn-sm absolute z-30 not-focus:sr-only"
    >
      {@texts.skip_table}
    </a>
    <div
      {@grid}
      class={@kit.class(:grid, %{nested?: @nested?})}
    >
      <table
        {@table}
        class={["table", @nested? && "w-auto"]}
      >
        <thead id={Ids.head(@id)}>
          <tr {@head.row}>
            <%!-- The first column, where rows can be selected: a box per row,
              and here the one that stands for the rows of the page. Its state
              is the hook's, as is that of every box under it. Where one row at a
              time is selected there is nothing to stand for, and the rows have
              radio buttons of one group: one of them at most is on. --%>
            <th
              :if={@head.select}
              {@head.select.element}
              class="w-0"
            >
              <input
                :if={@head.select.page?}
                type="checkbox"
                aria-label={@head.texts.select_page}
                class={["checkbox checkbox-xs block", Parts.Editors.box_edge()]}
              />
              <span :if={!@head.select.page?} class="sr-only">{@head.texts.select_row}</span>
            </th>
            <th
              :if={@head.expander}
              {@head.expander}
              class="w-0"
            >
              <span class="sr-only">{@texts.related_records}</span>
            </th>
            <Kit.part
              :for={cell <- @head.cells}
              part={:header_cell}
              kit={@kit}
              {cell}
            />
            <th
              :if={@head.actions}
              {@head.actions}
              class="whitespace-nowrap"
            >
              {@texts.actions}
            </th>
          </tr>
          <%!-- The filter row, where a column has a filter. --%>
          <tr :if={@filters} {@filters.row}>
            <td :if={@filters.select} {@filters.select}></td>
            <td :if={@filters.expander} {@filters.expander}></td>
            <Kit.part
              :for={cell <- @filters.cells}
              part={:filter_cell}
              kit={@kit}
              {cell}
            />
            <td
              :if={@filters.actions}
              {@filters.actions}
            >
            </td>
          </tr>
        </thead>
        <%!-- Written without whitespace on purpose: every byte of a row is sent again
          whenever the row is. An item of the stream is a row or, after its row, the
          row's detail (the kit's `row/1` and `detail/1`). --%>
        <tbody
          :for={{dom_id, row} <- @rows}
          id={dom_id}
          role="rowgroup"
          {row.attrs}
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
            /></tbody>
        <Kit.part
          :if={@footer}
          part={:footer}
          kit={@kit}
          id={@id}
          {@footer}
        />
      </table>
      <%!-- One editor per editable column. The hook opens a copy of it in the
        cell being edited; which cell that is, the server never knows. A
        reference column has an empty one: its cells are edited in the picker,
        which the hook asks for. So has the column of an array, a map cell or
        a union, which is edited in the side panel. A column whose component edits has the
        component's editor; every other the
        kit's. --%>
      <template
        :for={editor <- @editors}
        {editor.template}
      >
        <Kit.editor
          kit={@kit}
          editor={editor}
        />
      </template>
      <%!-- The message of a cell whose save failed, for the one case in which
      the hook has to mark the cell itself: the record is gone, so there is
      no row to send. --%>
      <template :if={@failure} {@failure.template} phx-no-format><Kit.part part={:failure} kit={@kit} id={nil} message={@failure.message} text={@failure.text} /></template>
    </div>
    <%!-- The scrollbar of the grid once more, for when the grid's own is
    below the window: the hook shows it at the bottom edge of the window, as
    wide as the grid, and keeps the two together. For the pointer alone: no
    tab stop, and nothing a screen reader is told of, as the grid scrolls
    with the focus. Patches leave it as the hook has it. --%>
    <div
      {@scrollbar}
      class="fixed z-10 overflow-x-scroll overflow-y-hidden"
    >
      <div class="h-px"></div>
    </div>
    """
  end

  # The look of the root of the table on the page, once per page: what the
  # hooks draw with is given here in the theme's colours. The hooks take
  # `--ash-data-table-ground` and `--ash-data-table-line` where a host sets
  # them, else these (the ground behind the cells that stay in view, the
  # edge beside them).
  #
  # And the look of every grid inside it, the nested tables' and the
  # pickers' tables' too, which are drawn inside this root: written once
  # here, on the grid's markers (`role=table`, `role=rowgroup`, `role=row`,
  # `role=cell`, `role=rowheader`, `data-lines`, `data-failed`, …), not on every grid,
  # so that an opened nested table or picker sends none of it. A rule
  # about a grid's own cells reaches them
  # through its row groups and rows (`>`), so that a nested table, which
  # stands in a cell, is not one of them. Written out in full, as Tailwind
  # finds a class only as it is written in the source.
  @root Enum.join(
          [
            "ash-data-table",
            "[--ash-data-table-default-ground:var(--color-base-100)] [--ash-data-table-default-line:var(--color-base-content)]",
            # The focus rings the kit draws itself, as daisyUI draws its own: 2px in
            # the text colour, the one colour a theme promises to be seen on its
            # background, which its brand colour need not be (#46). A daisyUI
            # control (a button, a box, a menu, an input) keeps its own.
            #
            # An editable cell, the one cell that is a Tab stop, inside its
            # edge; it keeps it while its editor has the focus (not while a
            # button in it has, a sensitive cell's "Show", which has its own).
            # A cell that spans the table draws none.
            "[&_:is([role=cell],[role=rowheader]):not([colspan]):focus]:outline-2 [&_:is([role=cell],[role=rowheader]):not([colspan]):focus]:-outline-offset-2 [&_:is([role=cell],[role=rowheader]):not([colspan]):focus]:outline-base-content",
            "[&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader]):not([data-selector],[data-expander],[data-actions],[data-filter],[colspan]):focus-within:not(:has(button:focus))]:outline-2 [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader]):not([data-selector],[data-expander],[data-actions],[data-filter],[colspan]):focus-within:not(:has(button:focus))]:-outline-offset-2 [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader]):not([data-selector],[data-expander],[data-actions],[data-filter],[colspan]):focus-within:not(:has(button:focus))]:outline-base-content",
            # The buttons of the kit's own look: a column's sort button, the
            # expander of a row and the button of a line, outside their edge.
            "[&_:is([data-sort]>button,[data-expander]>button,[data-line]_button[aria-expanded]):focus-visible]:outline-2 [&_:is([data-sort]>button,[data-expander]>button,[data-line]_button[aria-expanded]):focus-visible]:outline-offset-2 [&_:is([data-sort]>button,[data-expander]>button,[data-line]_button[aria-expanded]):focus-visible]:outline-current",
            # Which cells can be edited, where a table offers editing (its grid
            # has an editor's template): at rest they look alike. With the
            # pointer an editable cell (`tabindex="0"`) shows a thin edge inside
            # it, a text cursor and a small pencil at its end (not on a failed
            # cell, whose end holds its mark); a read-only cell does not change.
            "[&_[data-ash-data-table]:has(>template[data-editor])>[role=table]>[role=rowgroup]:not([data-detail],:has(>[role=row]>[role=columnheader]))>[role=row]:not([data-summaries])>:is([role=cell],[role=rowheader])[tabindex='0']]:relative [&_[data-ash-data-table]:has(>template[data-editor])>[role=table]>[role=rowgroup]:not([data-detail],:has(>[role=row]>[role=columnheader]))>[role=row]:not([data-summaries])>:is([role=cell],[role=rowheader])[tabindex='0']]:cursor-text [&_[data-ash-data-table]:has(>template[data-editor])>[role=table]>[role=rowgroup]:not([data-detail],:has(>[role=row]>[role=columnheader]))>[role=row]:not([data-summaries])>:is([role=cell],[role=rowheader])[tabindex='0']:hover]:shadow-[inset_0_0_0_1px_color-mix(in_oklab,var(--color-base-content)_30%,transparent)]",
            "[&_[data-ash-data-table]:has(>template[data-editor])>[role=table]>[role=rowgroup]:not([data-detail],:has(>[role=row]>[role=columnheader]))>[role=row]:not([data-summaries])>:is([role=cell],[role=rowheader])[tabindex='0']:not([data-failed]):is(:hover,:focus)]:after:absolute [&_[data-ash-data-table]:has(>template[data-editor])>[role=table]>[role=rowgroup]:not([data-detail],:has(>[role=row]>[role=columnheader]))>[role=row]:not([data-summaries])>:is([role=cell],[role=rowheader])[tabindex='0']:not([data-failed]):is(:hover,:focus)]:after:end-1.5 [&_[data-ash-data-table]:has(>template[data-editor])>[role=table]>[role=rowgroup]:not([data-detail],:has(>[role=row]>[role=columnheader]))>[role=row]:not([data-summaries])>:is([role=cell],[role=rowheader])[tabindex='0']:not([data-failed]):is(:hover,:focus)]:after:top-1/2 [&_[data-ash-data-table]:has(>template[data-editor])>[role=table]>[role=rowgroup]:not([data-detail],:has(>[role=row]>[role=columnheader]))>[role=row]:not([data-summaries])>:is([role=cell],[role=rowheader])[tabindex='0']:not([data-failed]):is(:hover,:focus)]:after:-translate-y-1/2 [&_[data-ash-data-table]:has(>template[data-editor])>[role=table]>[role=rowgroup]:not([data-detail],:has(>[role=row]>[role=columnheader]))>[role=row]:not([data-summaries])>:is([role=cell],[role=rowheader])[tabindex='0']:not([data-failed]):is(:hover,:focus)]:after:text-xs [&_[data-ash-data-table]:has(>template[data-editor])>[role=table]>[role=rowgroup]:not([data-detail],:has(>[role=row]>[role=columnheader]))>[role=row]:not([data-summaries])>:is([role=cell],[role=rowheader])[tabindex='0']:not([data-failed]):is(:hover,:focus)]:after:leading-none [&_[data-ash-data-table]:has(>template[data-editor])>[role=table]>[role=rowgroup]:not([data-detail],:has(>[role=row]>[role=columnheader]))>[role=row]:not([data-summaries])>:is([role=cell],[role=rowheader])[tabindex='0']:not([data-failed]):is(:hover,:focus)]:after:text-base-content/60 [&_[data-ash-data-table]:has(>template[data-editor])>[role=table]>[role=rowgroup]:not([data-detail],:has(>[role=row]>[role=columnheader]))>[role=row]:not([data-summaries])>:is([role=cell],[role=rowheader])[tabindex='0']:not([data-failed]):is(:hover,:focus)]:after:content-['✎'_/_'']",
            # A cell whose save is on its way, and the rows of a table that is
            # reading: dimmed, and no further than text may be. The header and the
            # filters are not dimmed, as they can be used meanwhile and are muted
            # already; nor is a nested table, which is not what is reading.
            "[&_:is([role=cell],[role=rowheader])[aria-busy]]:opacity-70 [&_[role=table][aria-busy]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader]):not([data-nested])]:opacity-70",
            # A cell whose save or action failed (`data-failed`): a ring and a
            # mark, both drawn by the cell's style, so that they add nothing to a
            # row's markup. The ring is a border, which forced colours keep and a
            # shadow they do not, in the error colour mixed with the text colour,
            # so that it is seen on the background in a theme whose error colour
            # alone is not. With focus it moves inside the focus ring, and both
            # show.
            "[&_:is([role=cell],[role=rowheader])[data-failed]]:relative [&_:is([role=cell],[role=rowheader])[data-failed]]:before:pointer-events-none [&_:is([role=cell],[role=rowheader])[data-failed]]:before:absolute [&_:is([role=cell],[role=rowheader])[data-failed]]:before:inset-0 [&_:is([role=cell],[role=rowheader])[data-failed]]:before:border-2 [&_:is([role=cell],[role=rowheader])[data-failed]]:before:border-[color-mix(in_oklab,var(--color-error)_70%,var(--color-base-content))] [&_:is([role=cell],[role=rowheader])[data-failed]]:before:content-['']",
            "[&_:is([role=cell],[role=rowheader])[data-failed]:is(:focus,:focus-within)]:before:inset-[3px]",
            # The mark is what says "failed" without a colour: a "!" in the cell's
            # padding at its end, in the text colour. It is for the eye only (the
            # empty alternative text): the cell is described by its message.
            "[&_:is([role=cell],[role=rowheader])[data-failed]]:after:absolute [&_:is([role=cell],[role=rowheader])[data-failed]]:after:end-2 [&_:is([role=cell],[role=rowheader])[data-failed]]:after:top-1/2 [&_:is([role=cell],[role=rowheader])[data-failed]]:after:-translate-y-1/2 [&_:is([role=cell],[role=rowheader])[data-failed]]:after:leading-none [&_:is([role=cell],[role=rowheader])[data-failed]]:after:font-bold [&_:is([role=cell],[role=rowheader])[data-failed]]:after:content-['!'_/_'']",
            # one line per row: long text is cut off, not wrapped. Not in a cell
            # that spans the table: a line, or the cell a nested table is in.
            "[&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader]):not([colspan],[data-actions])]:max-w-80 [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader]):not([colspan],[data-actions])]:truncate [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-actions]]:whitespace-nowrap",
            # But for the cells of a column that says `max_lines`: their text is
            # in a paragraph that wraps, keeps the line breaks of the value and is
            # cut off after that many lines (`data-lines` on the cell). The row is
            # as high as its highest cell. A word longer than the column breaks.
            "[&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-lines]]:whitespace-normal [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-lines]>[data-paragraph]]:min-w-40 [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-lines]>[data-paragraph]]:break-words [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-lines]>[data-paragraph]]:whitespace-pre-line",
            # A cell that cuts some of its text off shows all of it while the
            # button the hook puts into it says so (`data-whole`,
            # `aria-expanded`): the text wraps, keeps its line breaks and
            # is not cut off, and the row grows. The button says what its
            # marker holds (`content: attr(data-whole)`): it has no text of
            # its own. Cut off, it stands at the cell's end, over the end of
            # the text; expanded, on a line of its own under the text.
            "[&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader]):has(>[data-whole])]:relative [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader]):has(>[data-whole][aria-expanded=true])]:whitespace-pre-line [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader]):has(>[data-whole][aria-expanded=true])]:[overflow-wrap:anywhere] [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader]):has(>[data-whole][aria-expanded=true])>[data-paragraph]]:line-clamp-none",
            "[&_[data-whole]]:absolute [&_[data-whole]]:end-1 [&_[data-whole]]:top-1 [&_[data-whole]]:cursor-pointer [&_[data-whole]]:rounded [&_[data-whole]]:bg-base-100 [&_[data-whole]]:px-1 [&_[data-whole]]:text-xs [&_[data-whole]]:leading-tight [&_[data-whole]]:underline [&_[data-whole]]:before:content-[attr(data-whole)] [&_[data-whole][aria-expanded=true]]:static [&_[data-whole][aria-expanded=true]]:block [&_[data-whole][aria-expanded=true]]:px-0 [&_[data-whole][aria-expanded=true]]:whitespace-normal [&_[data-whole]]:[overflow-wrap:anywhere]",
            "[&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-lines='2']>[data-paragraph]]:line-clamp-2 [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-lines='3']>[data-paragraph]]:line-clamp-3 [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-lines='4']>[data-paragraph]]:line-clamp-4 [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-lines='5']>[data-paragraph]]:line-clamp-5 [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-lines='6']>[data-paragraph]]:line-clamp-6 [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-lines='7']>[data-paragraph]]:line-clamp-7 [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-lines='8']>[data-paragraph]]:line-clamp-8 [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-lines='9']>[data-paragraph]]:line-clamp-9 [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-lines='10']>[data-paragraph]]:line-clamp-10",
            # the expander of a row and the button of a line (which is in the
            # element of its cell that stays in view). Their mark is a
            # triangle drawn in CSS, not a character: it turns about its own
            # centre, so it sits in the same place open and closed.
            "[&_[role=table]>[role=rowgroup]>[role=row]>:is([data-expander],[data-line])_button[aria-expanded]]:cursor-pointer [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-expander]]:w-0 [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-expander]>button]:px-1",
            # the box that selects a row: its cell as narrow as the box, and
            # the box in the middle of it
            "[&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-selector]]:w-0 [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-selector]>input]:block",
            "[&_[role=table]>[role=rowgroup]>[role=row]>:is([data-expander],[data-line])_button[aria-expanded]]:before:inline-block [&_[role=table]>[role=rowgroup]>[role=row]>:is([data-expander],[data-line])_button[aria-expanded]]:before:size-0 [&_[role=table]>[role=rowgroup]>[role=row]>:is([data-expander],[data-line])_button[aria-expanded]]:before:content-['']",
            "[&_[role=table]>[role=rowgroup]>[role=row]>:is([data-expander],[data-line])_button[aria-expanded]]:before:border-y-[0.3em] [&_[role=table]>[role=rowgroup]>[role=row]>:is([data-expander],[data-line])_button[aria-expanded]]:before:border-y-transparent [&_[role=table]>[role=rowgroup]>[role=row]>:is([data-expander],[data-line])_button[aria-expanded]]:before:border-s-[0.45em] [&_[role=table]>[role=rowgroup]>[role=row]>:is([data-expander],[data-line])_button[aria-expanded]]:before:border-s-current",
            "[&_[role=table]>[role=rowgroup]>[role=row]>:is([data-expander],[data-line])_button[aria-expanded]]:before:transition-transform [&_[role=table]>[role=rowgroup]>[role=row]>:is([data-expander],[data-line])_button[aria-expanded=true]]:before:rotate-90",
            # forced colours would fill the two transparent sides of the triangle
            # and make it a square, which looks the same open and closed
            "[&_[role=table]>[role=rowgroup]>[role=row]>:is([data-expander],[data-line])_button[aria-expanded]]:before:forced-color-adjust-none forced-colors:[&_[role=table]>[role=rowgroup]>[role=row]>:is([data-expander],[data-line])_button[aria-expanded]]:before:border-s-[CanvasText]",
            # a line's mark stands under its row's
            "[&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-line]_button[aria-expanded]]:ps-1 [&_[role=table]>[role=rowgroup]>[role=row]>:is([role=cell],[role=rowheader])[data-line]_button[aria-expanded]]:before:me-2",
            # a nested table stays at the left edge of the scroll area around
            # it, and is as wide as that area (`--ash-data-table-view`, which
            # the grid's hook sets); its heading, the other portal, is on its
            # line, which stays there itself
            "[&_[data-ash-data-table-portal]:has(>[data-ash-data-table-view])]:sticky [&_[data-ash-data-table-portal]:has(>[data-ash-data-table-view])]:left-0 [&_[data-ash-data-table-portal]:has(>[data-ash-data-table-view])]:w-0 [&_[data-ash-data-table-view]]:relative [&_[data-ash-data-table-view]]:w-[var(--ash-data-table-view)]"
          ],
          " "
        )

  def root, do: @root

  # The name the "Columns" button is anchored by (`anchor-name`), the
  # table's own: a page has a list per table.
  defp anchor(id), do: "--ash-data-table-columns-" <> String.replace(id, ~r/[^A-Za-z0-9_-]/, "_")
end
