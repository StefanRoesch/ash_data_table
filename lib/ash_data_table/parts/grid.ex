defmodule AshDataTable.Parts.Grid do
  @moduledoc false
  # The grid: the header row, the filter row, the rows and their cells,
  # the footer, the editors the hook copies into a cell, and the "Columns" list.
  # Moved out of `AshDataTable.Live.TableComponent` in stage 1 of the
  # refactor (docs/architecture/target.md); it still draws from the
  # component's assigns.
  use Phoenix.Component

  alias AshDataTable.Attrs
  alias AshDataTable.Edit
  alias AshDataTable.Format
  alias AshDataTable.Model
  alias AshDataTable.Model.Limits
  alias AshDataTable.Parts
  alias AshDataTable.Present
  alias AshDataTable.Text
  alias Phoenix.LiveView.JS

  # The handle at the end of a column's header, with which a person makes
  # the column wider or narrower: dragged, or moved with the arrow keys once
  # F2 on the header has put the focus on it. A separator that can be moved,
  # as ARIA has it for the bar between two panes, and what it says of itself
  # is the column's width in pixels; `aria-valuenow` is the hook's, which
  # alone knows how wide a column is. It is not seen until it is pointed at,
  # has the focus or is dragged: then a line at the column's edge.
  #
  # Nothing of this reaches the server: the widths are the hook's, kept in a
  # style sheet of its own, and are gone with the page (see "the widths of
  # the columns" in the hook). The header says its name itself
  # (`aria-label`), so that the handle's name is no part of it.
  attr :id, :string, required: true
  attr :column, :map, required: true

  defp resizer(assigns) do
    ~H"""
    <span
      id={@id}
      role="separator"
      aria-orientation="vertical"
      aria-label={Text.t(:resize_column, column: @column.label)}
      aria-valuemin={Attrs.least_width()}
      aria-valuemax={Attrs.most_width()}
      tabindex="-1"
      data-resize
      class={[
        "absolute inset-y-0 end-0 w-3 cursor-col-resize touch-none select-none",
        "focus:outline-2 focus:-outline-offset-2 focus:outline-base-content",
        "[&:is(:hover,:focus,[data-dragging])]:after:absolute [&:is(:hover,:focus,[data-dragging])]:after:inset-y-0 [&:is(:hover,:focus,[data-dragging])]:after:end-0 [&:is(:hover,:focus,[data-dragging])]:after:border-e-2 [&:is(:hover,:focus,[data-dragging])]:after:border-base-content [&:is(:hover,:focus,[data-dragging])]:after:content-['']"
      ]}
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
  # It is a disclosure, not a menu: a button that says whether the list is
  # open (`aria-expanded`), and a group of labelled boxes. The list is a
  # popover, so that nothing around the table cuts it off: not the grid
  # that scrolls sideways around a nested table, and not a dialog.
  #
  # `columns` are the columns that can be hidden (`hideable/1`).
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
  #   * the texts, with `{n}`, `{details}` and `{column}` where the hook
  #     puts something in.
  attr :id, :string, required: true
  attr :columns, :list, required: true
  attr :keeps_one?, :boolean, required: true
  attr :state, :map, required: true
  attr :class, :any, default: nil

  def columns(assigns) do
    ~H"""
    <div id={"#{@id}-columns-control"} class={@class}>
      <button
        type="button"
        id={"#{@id}-columns-button"}
        aria-expanded="false"
        aria-controls={"#{@id}-columns"}
        phx-mounted={JS.ignore_attributes(["aria-expanded"])}
        data-columns-button
        data-text={Text.t(:columns)}
        data-text-with={Text.t(:columns_with, details: "{details}")}
        data-text-hidden={Text.t(:columns_hidden, count: "{n}")}
        data-text-filtered={Text.t(:columns_filtered, count: "{n}")}
        data-text-sorted={Text.t(:columns_sorted, count: "{n}")}
        data-say-hidden={Text.t(:column_hidden, column: "{column}")}
        data-say-shown={Text.t(:column_shown, column: "{column}")}
        class="btn btn-sm"
      >
        <span id={"#{@id}-columns-text"} phx-update="ignore">{Text.t(:columns)}</span>
      </button>
      <%!-- with the edge and the ground of the table's other popovers --%>
      <div
        id={"#{@id}-columns"}
        role="group"
        aria-label={Text.t(:columns)}
        popover="manual"
        phx-mounted={JS.ignore_attributes(["style"])}
        data-columns-list
        data-keeps-one={@keeps_one?}
        class="inset-auto m-0 max-h-[60vh] overflow-y-auto rounded border border-base-content/40 bg-base-100 p-2 text-sm text-base-content shadow"
      >
        <label
          :for={column <- @columns}
          id={"#{@id}-column-#{column.name}-entry"}
          class="flex cursor-pointer items-center gap-2 px-1 py-0.5 whitespace-nowrap"
        >
          <input
            type="checkbox"
            id={"#{@id}-column-#{column.name}"}
            checked
            data-head={"#{@id}-head-#{column.name}"}
            data-label={column.label}
            data-filtered={is_map_key(@state.filters, column.name)}
            data-sorted={Attrs.aria_sort(@state.sort, column) != "none"}
            class={["peer checkbox checkbox-xs", Parts.Editors.box_edge()]}
          />
          <span>{column.label}</span>
          <span :if={column_flag(@state, column)} data-flag class="peer-checked:hidden">
            ({column_flag(@state, column)})
          </span>
        </label>
      </div>
      <%!-- What the hook says when a column is hidden or shown again. A live
      region of its own: the one above the grid is rendered by the server,
      and would say its last text once more when the next patch put it back. --%>
      <p id={"#{@id}-columns-status"} role="status" phx-update="ignore" class="sr-only"></p>
    </div>
    """
  end

  # What a column's box in the list says of the column besides its name,
  # while the column is hidden: that the rows are filtered by it, sorted by
  # it, or both.
  defp column_flag(state, column) do
    case {is_map_key(state.filters, column.name), Attrs.aria_sort(state.sort, column) != "none"} do
      {true, true} -> Text.t(:column_filtered_sorted)
      {true, false} -> Text.t(:column_filtered)
      {false, true} -> Text.t(:column_sorted)
      {false, false} -> nil
    end
  end

  # What a cell of an editable column is edited with: the native control of
  # its cell type, without a name or a form, as the hook reads its value and
  # sends it. It takes the place of the cell's text, so it has the text's
  # size and no border of its own; the cell shows the focus.
  #
  # `id` is the id of the editor's `<template>`. What is in a template is
  # not in the page, and one copy of it at most is: an id that starts with
  # it is the id of one element.
  attr :id, :string, required: true
  attr :column, :map, required: true
  attr :allow_nil?, :boolean, required: true

  # A column whose component edits: the editor is the component's.
  defp editor(%{column: %{editor: :component}} = assigns) do
    ~H"""
    <Parts.Common.dynamic_component
      module={@column.component.module}
      function={:editor}
      value=""
      label={@column.label}
      column={@column.component.column}
      place={:grid}
      control={Attrs.component_control(@column)}
    />
    """
  end

  # A sensitive column, which is text or a number: a password input, so that
  # what is typed is not shown. The hook opens it empty.
  #
  # Left empty it saves nothing, so nothing typed into it empties the cell.
  # Where the cell can be empty (`AshDataTable.Edit.clearable?/1`), a button
  # beside the input does: "Clear", named with the column. The two are the
  # editor then, and the input is its control. The hook takes the button
  # out for a cell that holds nothing.
  defp editor(%{column: %{sensitive?: true}} = assigns) do
    assigns = assign(assigns, clearable?: Edit.clearable?(assigns.column))

    ~H"""
    <input
      :if={!@clearable?}
      type="password"
      autocomplete="off"
      aria-label={@column.label}
      class="block h-5 w-full min-w-24 bg-transparent p-0 text-sm outline-none"
    />
    <div :if={@clearable?} class="flex w-full min-w-24 items-center gap-2">
      <input
        type="password"
        autocomplete="off"
        data-control
        aria-label={@column.label}
        class="block h-5 w-0 min-w-12 flex-1 bg-transparent p-0 text-sm outline-none"
      />
      <button
        type="button"
        data-clear
        aria-label={Text.t(:clear_value, column: @column.label)}
        class="btn btn-xs -my-1 shrink-0"
      >
        {Text.t(:clear)}
      </button>
    </div>
    """
  end

  # Text is edited in a textarea, so that text of several lines keeps its
  # lines. It is one line high until the text needs more.
  #
  # A text with a most it can be long has its counter with it. The textarea
  # takes the place of the cell's text as before, to the last pixel: a
  # counter beside it would take room from the text, and a text that fills
  # its column would break into another line. So the counter is a popover,
  # which the hook shows under the cell at its end while the editor is
  # open, as it shows the message of a failed cell: neither the row nor the
  # column moves. The two are the editor; the textarea is its control.
  defp editor(%{column: %{editor: :text}} = assigns) do
    assigns = assign(assigns, counted: Limits.counted(assigns.column))

    ~H"""
    <textarea
      :if={!@counted}
      rows="1"
      aria-label={@column.label}
      aria-required={@column.required? && "true"}
      class="block w-full min-w-40 resize-none bg-transparent p-0 text-sm break-words whitespace-pre-wrap outline-none"
    ></textarea>
    <div :if={@counted}>
      <textarea
        rows="1"
        {Attrs.counted_control(@id, @column)}
        class="block w-full min-w-40 resize-none bg-transparent p-0 text-sm break-words whitespace-pre-wrap outline-none"
      ></textarea>
      <Parts.Editors.count id={"#{@id}-count"} counted={@counted} value="" floats?={true} />
    </div>
    """
  end

  defp editor(%{column: %{editor: :boolean}} = assigns) do
    ~H"""
    <input
      type="checkbox"
      tabindex="-1"
      aria-label={@column.label}
      class="checkbox checkbox-xs pointer-events-none"
    />
    """
  end

  defp editor(%{column: %{editor: :enum}} = assigns) do
    ~H"""
    <select
      aria-label={@column.label}
      aria-required={@column.required? && "true"}
      class="block h-5 w-full bg-transparent p-0 text-sm outline-none"
    >
      <option :if={@allow_nil?} value=""></option>
      <option :for={{choice, label} <- @column.values} value={choice}>{label}</option>
    </select>
    """
  end

  # An array of enum values is edited as multiple choice: one box per value
  # of the enum, in declared order. The boxes are a group, which the column
  # names; each is named by the label of its value.
  defp editor(%{column: %{editor: :choices}} = assigns) do
    ~H"""
    <div role="group" aria-label={@column.label} class="flex flex-col items-start gap-1 py-0.5">
      <label :for={{choice, label} <- @column.values} class="flex items-center gap-2">
        <input
          type="checkbox"
          value={choice}
          class={["checkbox checkbox-xs", Parts.Editors.box_edge()]}
        />
        {label}
      </label>
    </div>
    """
  end

  # Any other array is edited value by value.
  defp editor(%{column: %{editor: :list, cell_type: {:array, item}}} = assigns) do
    assigns = assign(assigns, item: item)

    ~H"""
    <Parts.Editors.list
      id={"#{@id}-list"}
      role="group"
      aria-label={@column.label}
      label={@column.label}
      item={@item}
      limits={Limits.of(@column)}
      counted={@item == :text && Limits.counted(@column)}
      place={:grid}
    />
    """
  end

  # The control of a number says what the attribute's constraints say of it
  # (`AshDataTable.Model.Limits`). Nothing in the browser checks it against them:
  # the hook sends what the control holds, and Ash says what is wrong with it.
  defp editor(assigns) do
    assigns = assign(assigns, limits: Limits.of(assigns.column))

    ~H"""
    <input
      type={Parts.Editors.input_type(@column.editor)}
      step={@limits.step || Parts.Editors.input_step(@column.editor)}
      min={@limits.min}
      max={@limits.max}
      aria-label={@column.label}
      aria-required={@column.required? && "true"}
      class="block h-5 w-full min-w-24 bg-transparent p-0 text-sm outline-none"
    />
    """
  end

  # A choice that can be empty offers the empty choice.
  defp allow_nil?(resource, column) do
    Ash.Resource.Info.attribute(resource, column.name).allow_nil?
  end

  defp sort_mark({name, :asc}, %{name: name}), do: " ▲"
  defp sort_mark({name, :desc}, %{name: name}), do: " ▼"
  defp sort_mark(_sort, _column), do: ""

  defp action_failure(_id, %{action_failure: nil}), do: []

  defp action_failure(id, %{action_failure: message}),
    do: Parts.Common.failure_message("#{id}-error", message)

  # A cell whose save failed shows what was typed, as the cell would show it
  # had it been saved, and holds the action's message. The message is a
  # popover the hook opens while the cell has focus or the pointer, so that
  # the row keeps its height; it is in the text colour on the page's
  # background, as the error colour is too faint for small text.
  defp cell_content(id, column, row, zone) do
    cell = row.cells[column.name]

    case cell.failure do
      # a sensitive cell shows what it shows at rest, never what was typed
      %{message: message} when column.sensitive? ->
        {:safe, shown} = column |> shown(cell, zone) |> Phoenix.HTML.html_escape()
        {:safe, message} = Parts.Common.failure_message("#{id}-error", message)
        {:safe, [shown, message]}

      %{typed: typed, message: message} ->
        {:safe, shown} = typed |> typed(column, zone) |> paragraph(column, false)
        {:safe, message} = Parts.Common.failure_message("#{id}-error", message)
        {:safe, [shown, message]}

      nil ->
        column |> shown(cell, zone) |> paragraph(column, cell.state == :forbidden)
    end
  end

  # The text of a cell whose column says `max_lines` is a paragraph: that is
  # what wraps and is cut off after the last line. An empty cell holds
  # nothing, as everywhere, and the cell of a field the person may not see
  # holds what it holds in every column.
  defp paragraph(shown, %{max_lines: 1}, _forbidden?), do: Phoenix.HTML.html_escape(shown)
  defp paragraph(shown, _column, true), do: Phoenix.HTML.html_escape(shown)

  defp paragraph(shown, _column, false) do
    {:safe, shown} = Phoenix.HTML.html_escape(shown)

    if IO.iodata_length(shown) == 0,
      do: {:safe, shown},
      else: {:safe, [~s(<p data-paragraph>), shown, "</p>"]}
  end

  # What was typed into an editor, as its cell shows it.
  defp typed("true", %{editor: :boolean} = column, zone), do: cell(column, true, zone)
  defp typed("false", %{editor: :boolean} = column, zone), do: cell(column, false, zone)

  defp typed(typed, %{editor: :enum, values: values}, _zone) do
    Enum.find_value(values, typed, fn {value, label} -> to_string(value) == typed && label end)
  end

  # the values of an array, each as its cell shows it
  defp typed(typed, %{cell_type: {:array, item}} = column, _zone) when is_list(typed),
    do: Enum.map_join(typed, ", ", &typed_value(&1, item, column))

  defp typed(typed, _column, _zone), do: typed

  defp typed_value("true", :boolean, _column), do: Text.t(:yes)
  defp typed_value("false", :boolean, _column), do: Text.t(:no)

  defp typed_value(typed, :enum, %{values: values}) do
    Enum.find_value(values, typed, fn {value, label} -> to_string(value) == typed && label end)
  end

  defp typed_value(typed, _item, _column), do: typed

  # What a cell shows, by what it holds (`AshDataTable.Present.Cell`).
  #
  # A field the actor may not see on this row looks empty and is announced.
  defp shown(_column, %{state: :forbidden}, _zone) do
    {:safe, [~s(<span class="sr-only" data-unseen>), escape(Text.t(:not_available)), "</span>"]}
  end

  # A record that has no value has an empty cell, whatever its column: what
  # "empty" looks like is the table's to say, in one way for all columns.
  defp shown(_column, %{state: :empty}, _zone), do: ""

  # A sensitive value is not shown: the cell holds a mask, the same for
  # every value and for the eye only, what a screen reader says in its
  # place, an empty live region the hook puts the value into when a person
  # asks for it, and the button that asks. The button is named with the
  # column, as every row has one. A cell without a value is empty, as any
  # cell is: that there is nothing is all it says.
  #
  # What is rendered is the same whatever the value is; the value itself is
  # not in what a row is rendered from (`AshDataTable.Present`).
  defp shown(column, %{state: :masked}, _zone) do
    {:safe,
     [
       ~s(<span class="inline-flex max-w-72 items-center align-bottom"><span data-mask aria-hidden="true">),
       Present.mask(),
       ~s(</span><span data-masked class="sr-only">),
       escape(Text.t(:hidden_value)),
       ~s(</span><span data-secret aria-live="polite" class="min-w-0 truncate"></span>),
       ~s(<button type="button" tabindex="-1" data-reveal data-show="),
       escape(Text.t(:show)),
       ~s(" data-hide="),
       escape(Text.t(:hide)),
       ~s(" data-show-label="),
       escape(Text.t(:show_value, column: column.label)),
       ~s(" data-hide-label="),
       escape(Text.t(:hide_value, column: column.label)),
       ~s(" aria-label="),
       escape(Text.t(:show_value, column: column.label)),
       ~s(" class="btn btn-xs -my-1 ms-2 shrink-0">),
       escape(Text.t(:show)),
       "</button></span>"
     ]}
  end

  defp shown(column, %{state: :value, value: value}, zone), do: cell(column, value, zone)

  # The kind of a union is no sensitive field: what it holds is shown as a
  # cell of its own type shows it.
  defp cell(_column, %Ash.ForbiddenField{}, zone), do: shown(nil, %{state: :forbidden}, zone)
  defp cell(_column, nil, _zone), do: ""
  defp cell(_column, %Ash.NotLoaded{}, _zone), do: ""

  # A column whose component shows: the cell's content is the component's,
  # which is given the value and what the table itself would show for it.
  # Only for a value: a value that is hidden from the person never reaches
  # a component, and neither does the lack of one.
  defp cell(%{component: %{cell?: true} = component} = column, value, zone) do
    assigns = %{
      module: component.module,
      value: value,
      text: Format.format(column, value, zone),
      column: component.column
    }

    ~H"""
    <Parts.Common.dynamic_component
      module={@module}
      function={:cell}
      value={@value}
      text={@text}
      column={@column}
    />
    """
  end

  # A union shows the value it holds, as a cell of its kind's type shows
  # it: a yes or no among its kinds is the check indicator a boolean has.
  defp cell(
         %{cell_type: :union, members: [_ | _] = members} = column,
         %Ash.Union{} = union,
         zone
       ) do
    case Enum.find(members, &(&1.name == union.type)) do
      nil -> Format.format(column, union, zone)
      kind -> cell(kind, union.value, zone)
    end
  end

  # A boolean is a check indicator with its accessible text beside it;
  # everything else is plain text.
  defp cell(%{cell_type: :boolean} = column, value, zone) when is_boolean(value) do
    mark = if value, do: "✓", else: "–"

    {:safe,
     [
       ~s(<span aria-hidden="true">),
       mark,
       ~s(</span><span class="sr-only" data-unseen>),
       escape(Format.format(column, value, zone)),
       "</span>"
     ]}
  end

  defp cell(column, value, zone), do: Format.format(column, value, zone)

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  # Its markup keeps the indentation it had in the table component's
  # `render/1`, held by `phx-no-format`, so that the text in it, and with it
  # the page, is the same byte for byte.
  attr :acting?, :any, required: true
  attr :open, :string, default: nil
  # whether the hook asks the question of a row action; in controlled mode
  # the host does (`AshDataTable.Live.Core.Requests`)
  attr :asks?, :boolean, default: true
  attr :busy?, :any, required: true
  attr :choose, :any, required: true
  attr :creates, :any, required: true
  attr :editing?, :any, required: true
  attr :expandable?, :any, required: true
  attr :full_view, :any, required: true
  attr :id, :any, required: true
  attr :label, :any, required: true
  attr :label_column, :any, required: true
  attr :labelledby, :any, required: true
  attr :lead, :any, required: true
  attr :model, :any, required: true
  attr :myself, :any, required: true
  attr :nested?, :any, required: true
  attr :page, :any, required: true
  attr :pending, :any, required: true
  attr :rejected, :any, required: true
  attr :row_count, :any, required: true
  # the items of the table's stream
  attr :rows, :any, required: true
  attr :running, :any, required: true
  attr :selecting, :any, required: true
  attr :state, :any, required: true
  attr :summarised?, :any, required: true
  attr :summary, :any, required: true
  attr :summing?, :any, required: true
  attr :time_zone, :any, required: true

  def grid(assigns) do
    ~H"""
    <%!-- The grid is the table's own scroll area: every table scrolls
    sideways in its own, a nested table as the table on the page (see
    "scrolling sideways" in the hook). A nested table that is scrolled to
    its end does not go on to scroll the table around it. Its attributes are
    `AshDataTable.Attrs.grid/5`'s. --%>
    <div
      phx-no-format
      {Attrs.grid(@id, @myself, @lead, @selecting, @choose)}
      class={["overflow-x-auto outline-none", @nested? && "overscroll-x-contain"]}
    >
        <table
          {Attrs.table(@id, @label, @labelledby, @page, @summarised?, Attrs.colcount(@model, @lead, @acting?), @selecting, @busy? or not is_nil(@running))}
          class={
            [
              "table",
              # a nested table is as wide as its columns need and no wider; in
              # everything else it looks as a table on a page does
              @nested? && "w-auto",
              # what every cell looks like is set once here, to keep each cell's markup small:
              # the focus ring, which a cell keeps while its editor has the focus. In
              # the text colour: the one colour a theme promises to be seen on its
              # background, which its brand colour need not be.
              "[&_:is(td,th):focus]:outline-2 [&_:is(td,th):focus]:-outline-offset-2 [&_:is(td,th):focus]:outline-base-content",
              "[&>tbody>tr>td:not([data-nested]):focus-within]:outline-2 [&>tbody>tr>td:not([data-nested]):focus-within]:-outline-offset-2 [&>tbody>tr>td:not([data-nested]):focus-within]:outline-base-content",
              # A cell whose save is on its way, and the rows of a table that is
              # reading: dimmed, and no further than text may be. The header and the
              # filters are not dimmed, as they can be used meanwhile and are muted
              # already; nor is a nested table, which is not what is reading.
              "[&_td[aria-busy]]:opacity-70 [&[aria-busy]>tbody>tr>td:not([data-nested])]:opacity-70",
              # A cell whose save or action failed: a ring and a mark, both drawn by
              # the cell's style, so that they add nothing to a row's markup. The ring
              # is a border, which forced colours keep and a shadow they do not, in
              # the error colour mixed with the text colour, so that it is seen on the
              # background in a theme whose error colour alone is not. With focus it
              # moves inside the focus ring, and both show.
              "[&_td[aria-invalid]]:relative [&_td[aria-invalid]]:before:pointer-events-none [&_td[aria-invalid]]:before:absolute [&_td[aria-invalid]]:before:inset-0 [&_td[aria-invalid]]:before:border-2 [&_td[aria-invalid]]:before:border-[color-mix(in_oklab,var(--color-error)_70%,var(--color-base-content))] [&_td[aria-invalid]]:before:content-['']",
              "[&_td[aria-invalid]:is(:focus,:focus-within)]:before:inset-[3px]",
              # The mark is what says "failed" without a colour: a "!" in the cell's
              # padding at its end, in the text colour. It is for the eye only (the
              # empty alternative text): the cell says the same with `aria-invalid`.
              "[&_td[aria-invalid]]:after:absolute [&_td[aria-invalid]]:after:end-2 [&_td[aria-invalid]]:after:top-1/2 [&_td[aria-invalid]]:after:-translate-y-1/2 [&_td[aria-invalid]]:after:leading-none [&_td[aria-invalid]]:after:font-bold [&_td[aria-invalid]]:after:content-['!'_/_'']",
              # one line per row: long text is cut off, not wrapped. Not in a cell
              # that spans the table: a line, or the cell a nested table is in.
              "[&>tbody>tr>td:not([colspan],[data-actions])]:max-w-80 [&>tbody>tr>td:not([colspan],[data-actions])]:truncate [&>tbody>tr>td[data-actions]]:whitespace-nowrap",
              # But for the cells of a column that says `max_lines`: their text is
              # in a paragraph that wraps, keeps the line breaks of the value and is
              # cut off after that many lines (`data-lines` on the cell). The row is
              # as high as its highest cell. A word longer than the column breaks.
              "[&>tbody>tr>td[data-lines]]:whitespace-normal [&>tbody>tr>td[data-lines]>p]:min-w-40 [&>tbody>tr>td[data-lines]>p]:break-words [&>tbody>tr>td[data-lines]>p]:whitespace-pre-line",
              "[&>tbody>tr>td[data-lines='2']>p]:line-clamp-2 [&>tbody>tr>td[data-lines='3']>p]:line-clamp-3 [&>tbody>tr>td[data-lines='4']>p]:line-clamp-4 [&>tbody>tr>td[data-lines='5']>p]:line-clamp-5 [&>tbody>tr>td[data-lines='6']>p]:line-clamp-6 [&>tbody>tr>td[data-lines='7']>p]:line-clamp-7 [&>tbody>tr>td[data-lines='8']>p]:line-clamp-8 [&>tbody>tr>td[data-lines='9']>p]:line-clamp-9 [&>tbody>tr>td[data-lines='10']>p]:line-clamp-10",
              # the expander of a row and the button of a line (which is in the
              # element of its cell that stays in view). Their mark is a
              # triangle drawn in CSS, not a character: it turns about its own
              # centre, so it sits in the same place open and closed.
              "[&>tbody>tr>:is(td[data-expander],td[data-line])_button[aria-expanded]]:cursor-pointer [&>tbody>tr>td[data-expander]]:w-0 [&>tbody>tr>td[data-expander]>button]:px-1",
              # the box that selects a row: its cell as narrow as the box, and
              # the box in the middle of it
              "[&>tbody>tr>td[data-selector]]:w-0 [&>tbody>tr>td[data-selector]>input]:block",
              "[&>tbody>tr>:is(td[data-expander],td[data-line])_button[aria-expanded]]:before:inline-block [&>tbody>tr>:is(td[data-expander],td[data-line])_button[aria-expanded]]:before:size-0 [&>tbody>tr>:is(td[data-expander],td[data-line])_button[aria-expanded]]:before:content-['']",
              "[&>tbody>tr>:is(td[data-expander],td[data-line])_button[aria-expanded]]:before:border-y-[0.3em] [&>tbody>tr>:is(td[data-expander],td[data-line])_button[aria-expanded]]:before:border-y-transparent [&>tbody>tr>:is(td[data-expander],td[data-line])_button[aria-expanded]]:before:border-s-[0.45em] [&>tbody>tr>:is(td[data-expander],td[data-line])_button[aria-expanded]]:before:border-s-current",
              "[&>tbody>tr>:is(td[data-expander],td[data-line])_button[aria-expanded]]:before:transition-transform [&>tbody>tr>:is(td[data-expander],td[data-line])_button[aria-expanded=true]]:before:rotate-90",
              # forced colours would fill the two transparent sides of the triangle
              # and make it a square, which looks the same open and closed
              "[&>tbody>tr>:is(td[data-expander],td[data-line])_button[aria-expanded]]:before:forced-color-adjust-none forced-colors:[&>tbody>tr>:is(td[data-expander],td[data-line])_button[aria-expanded]]:before:border-s-[CanvasText]",
              # a line's mark stands under its row's
              "[&>tbody>tr>td[data-line]>div>button[aria-expanded]]:ps-1 [&>tbody>tr>td[data-line]>div>button[aria-expanded]]:before:me-2",
              # the create button on a line, and the buttons of the nested table's
              # table actions, once the nested table under it has read: found by
              # the table's own marker of its portal, whatever LiveView wraps it in
              "[&>tbody>tr:has(+tr>td[data-nested]_[data-ash-data-table-portal]>div>[data-read])>td[data-line]>div>button[data-create]]:inline-flex",
              "[&>tbody>tr:has(+tr>td[data-nested]_[data-ash-data-table-portal]>div>[data-read])>td[data-line]>div>button[data-table-action]]:inline-flex"
            ]
          }
        >
          <thead id={"#{@id}-head"}>
            <tr {Attrs.row("#{@id}-head-row", "1")}>
              <%!-- The first column, where rows can be selected: a box per row,
              and here the one that stands for the rows of the page. Its state
              is the hook's, as is that of every box under it. Where one row at a
              time is selected there is nothing to stand for, and the rows have
              radio buttons of one group: one of them at most is on. --%>
              <th
                :if={@selecting}
                {Attrs.header("#{@id}-select-head", "1", %{"data-select-page" => @selecting == :multi})}
                class="w-0"
              >
                <input
                  :if={@selecting == :multi}
                  type="checkbox"
                  tabindex="-1"
                  aria-label={Text.t(:select_page)}
                  class={["checkbox checkbox-xs block", Parts.Editors.box_edge()]}
                />
                <span :if={@selecting == :single} class="sr-only">{Text.t(:select_row)}</span>
              </th>
              <th
                :if={@expandable?}
                {Attrs.header("#{@id}-expander-head", @lead)}
                class="w-0"
              >
                <span class="sr-only">{Text.t(:related_records)}</span>
              </th>
              <th
                :for={{column, index} <- Enum.with_index(@model.columns)}
                id={"#{@id}-head-#{column.name}"}
                role="columnheader"
                scope="col"
                aria-colindex={Parts.Common.colindex(index, @lead)}
                aria-label={column.label}
                tabindex="-1"
                {Attrs.column_header(@id, column, @state.sort, @model.sticky_label? and column == @label_column, @myself)}
                class={[
                  "relative whitespace-nowrap",
                  column.sortable? && "cursor-pointer select-none"
                ]}
                phx-no-format
              >{column.label}<span :if={column.sortable?} aria-hidden="true">{sort_mark(@state.sort, column)}</span><.resizer id={"#{@id}-resize-#{column.name}"} column={column} /></th>
              <th
                :if={@acting?}
                {Attrs.header("#{@id}-actions-head", length(@model.columns) + @lead + 1)}
                class="whitespace-nowrap"
              >
                {Text.t(:actions)}
              </th>
            </tr>
            <tr {Attrs.row("#{@id}-filter-row", "2")}>
              <td :if={@selecting} {Attrs.gridcell("#{@id}-select-filter", "1")}>
              </td>
              <td :if={@expandable?} {Attrs.gridcell("#{@id}-expander-filter", @lead)}>
              </td>
              <td
                :for={{column, index} <- Enum.with_index(@model.columns)}
                id={"#{@id}-filter-#{column.name}"}
                role="gridcell"
                aria-colindex={Parts.Common.colindex(index, @lead)}
                tabindex="-1"
                data-filter={column.operators != []}
              >
                <Parts.Filter.filter
                  :if={column.operators != []}
                  id={"#{@id}-filter-#{column.name}"}
                  table={@id}
                  form={"#{@id}-filters"}
                  column={column}
                  filter={Parts.Filter.shown_filter(@rejected, @pending, @state, column.name)}
                  rejected?={is_map_key(@rejected, column.name)}
                  applied?={is_map_key(@state.filters, column.name)}
                  target={@myself}
                />
              </td>
              <td :if={@acting?} {Attrs.gridcell("#{@id}-actions-filter", length(@model.columns) + @lead + 1)}>
              </td>
            </tr>
          </thead>
          <%!-- Written without whitespace on purpose: every byte of a row is sent again
          whenever the row is, and a cell's text must not be padded. An item of the
          stream is a row or, after its row, the row's detail (see "Nested tables"
          at the top). --%>
          <tbody
            :for={{dom_id, row} <- @rows}
            id={dom_id}
            role="rowgroup"
            {Attrs.rowgroup(row, @selecting)}
            phx-no-format
          ><Parts.Related.lines
              :if={Attrs.detail?(row) && row.lines}
              id={@id}
              row={row}
              model={@model}
              colspan={length(@model.columns) + @lead + Parts.Common.trail(@acting?)}
              creates={@creates}
              myself={@myself}
            /><tr
              :if={!Attrs.detail?(row)}
              id={"#{dom_id}-r"}
              role="row"
              aria-rowindex={row.rowindex}
            ><td
              :if={@selecting}
              id={"#{dom_id}-s"}
              role="gridcell"
              aria-colindex="1"
              tabindex="-1"
              data-selector
            ><input :if={@selecting == :multi} type="checkbox" tabindex="-1" aria-label={Text.t(:select_row)} class="checkbox checkbox-xs border-base-content/50" /><input :if={@selecting == :single} type="radio" name={"#{@id}-select"} tabindex="-1" aria-label={Text.t(:select_row)} class="radio radio-xs border-base-content/50" /></td><td
              :if={@expandable?}
              id={"#{dom_id}-e"}
              role="gridcell"
              aria-colindex={@lead}
              tabindex="-1"
              data-expander
            ><button type="button" tabindex="-1" aria-expanded={to_string(row.open?)} aria-label={Text.t(:related_records)}></button></td><td
              :for={{column, index} <- Enum.with_index(@model.columns)}
              id={"#{dom_id}-c-#{column.name}"}
              role="gridcell"
              aria-colindex={Parts.Common.colindex(index, @lead)}
              tabindex="-1"
              {Attrs.cell("#{dom_id}-c-#{column.name}", column, @editing?, row, @time_zone)}
            >{cell_content("#{dom_id}-c-#{column.name}", column, row, @time_zone)}</td><td
              :if={@acting?}
              id={"#{dom_id}-a"}
              role="gridcell"
              aria-colindex={length(@model.columns) + @lead + 1}
              tabindex="-1"
              data-actions
              {Attrs.actions("#{dom_id}-a", row)}
            ><button
              :if={@open}
              type="button"
              id={"#{dom_id}-a-open"}
              tabindex="-1"
              data-open
              class="btn btn-xs -my-1 me-1"
            >{@open}</button><button
              :for={action <- @model.actions}
              type="button"
              id={"#{dom_id}-a-#{action.name}"}
              tabindex="-1"
              data-action={action.name}
              {Attrs.action(action, @asks?)}
              class="btn btn-xs -my-1 me-1"
            >{action.label}</button>{action_failure("#{dom_id}-a", row)}</td></tr></tbody>
          <%!-- The pages of a nested table are a last row of its grid: reached with
          the arrow keys and entered with Enter, as a filter is, and no tab stop in the
          middle of the grid around it. The element stays where it is once it is there,
          as every child of a stream's container with an id does. --%>
          <%!-- In the text of the table: the range reads as it does under a table
          on a page, not as a footer's heading. What the two rows hold stays at
          the left edge of the table's scroll area, as what a line holds does. --%>
          <tfoot
            :if={@nested? or @summarised?}
            id={"#{@id}-foot"}
            class="font-normal text-base-content"
            hidden={
              not (@summarised? and not is_nil(@page)) and
                not (@nested? and
                       (Parts.Pagination.pages?(@page, @model) or
                          Parts.Related.full_view?(@page, @full_view)))
            }
          >
            <Parts.Summary.summaries
              acting?={@acting?}
              expandable?={@expandable?}
              id={@id}
              lead={@lead}
              model={@model}
              page={@page}
              selecting={@selecting}
              summarised?={@summarised?}
              summary={@summary}
              summing?={@summing?}
              time_zone={@time_zone}
            />
            <tr
              :if={@nested? and Parts.Pagination.pages?(@page, @model)}
              {Attrs.row("#{@id}-foot-row")}
            >
              <td {Attrs.spanning("#{@id}-pager", Attrs.colcount(@model, @lead, @acting?), %{"data-pager" => true})}>
                <Parts.Pagination.pagination
                  id={@id}
                  nested?={true}
                  page={@page}
                  model={@model}
                  state={@state}
                  row_count={@row_count}
                  label={@label}
                  target={@myself}
                />
              </td>
            </tr>
            <Parts.Related.full_view
              acting?={@acting?}
              full_view={@full_view}
              id={@id}
              label={@label}
              lead={@lead}
              model={@model}
              nested?={@nested?}
              page={@page}
            />
          </tfoot>
        </table>
        <%!-- One editor per editable column. The hook opens a copy of it in the
        cell being edited; which cell that is, the server never knows. A
        reference column has an empty one: its cells are edited in the picker,
        which the hook asks for. So has the column of a map cell, which is
        edited in the side panel. --%>
        <template
          :for={column <- @model.columns}
          :if={column.editable?}
          id={"#{@id}-editor-#{column.name}"}
          data-editor={Attrs.editor_kind(column)}
          data-commit={column.editor == :component && column.component.commit}
          data-confirm={column.confirm}
        >
          <.editor
            :if={column.editor not in [:reference, :group, :groups, :union]}
            id={"#{@id}-editor-#{column.name}"}
            column={column}
            allow_nil?={allow_nil?(@model.resource, column)}
          />
        </template>
        <Parts.Messages.failure
          acting?={@acting?}
          editing?={@editing?}
          id={@id}
        />
      </div>
    <%!-- The scrollbar of the grid once more, for when the grid's own is
    below the window: the hook shows it at the bottom edge of the window, as
    wide as the grid, and keeps the two together. For the pointer alone: no
    tab stop, and nothing a screen reader is told of, as the grid scrolls
    with the focus. Patches leave it as the hook has it. --%>
    <div
      phx-no-format
      {Attrs.scrollbar(@id)}
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
  def root do
    "ash-data-table [--ash-data-table-default-ground:var(--color-base-100)] [--ash-data-table-default-line:var(--color-base-content)]"
  end

  # The columns a person can hide, in the table's order: every column but the
  # one a record is called by, the attribute of the resource's `label_field`,
  # without which a row cannot be told from another. A table that has no
  # such column lets every column be hidden; one of them stays, whichever,
  # and that is the browser's to see to (`AshDataTable.Model.keeps_one?/1`).
  def hideable(%Model{columns: columns} = model) do
    case Model.label_column(model) do
      nil -> columns
      label -> List.delete(columns, label)
    end
  end
end
