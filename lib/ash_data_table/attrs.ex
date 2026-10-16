defmodule AshDataTable.Attrs do
  @moduledoc false
  # The attribute bundles (target.md S5): one function per element of the
  # table, returning every attribute the element carries besides its look,
  # its id, its ARIA role and states, the `data-*` markers the hooks find it
  # by, `phx-*` and `phx-hook`. A part spreads a bundle on its element
  # (`<td {Attrs.cell(…)}>`) and writes only its class and its content.
  #
  # A marker is an ARIA role where the element has one, else a `data-*`
  # attribute (the design note of stage 7, D2). The hooks find the table's
  # elements by these markers only; `markers/0` names them, as
  # `assets/js/markers.js` does on the hooks' side, and a test compares the
  # two lists. A marker added here and not read there, or read there and
  # not written here, is a bug (target.md 6).
  #
  # Internal: what the bundles hold is the contract of a kit's parts, which
  # `AshDataTable.Kit`'s moduledoc will document part by part (stage 7b).

  alias AshDataTable.Model.Limits
  alias AshDataTable.Parts.Common
  alias AshDataTable.Present
  alias AshDataTable.Text
  alias AshDataTable.Typed
  alias Phoenix.LiveView.JS

  @markers ~w(
    [role=grid] [role=rowgroup] [role=row] [role=gridcell] [role=columnheader] [role=dialog]
    [data-ash-data-table] data-table
    [colspan] [data-selector] [data-select-page] [data-expander] [data-line] [data-nested]
    [data-actions] [data-pager] [data-view] [data-filter] [data-lines] [data-paragraph] [data-detail]
    [data-current] [data-summaries]
    [data-resize] [data-open] [data-action] [data-create] [data-table-action]
    [data-reveal] [data-mask] [data-masked] [data-secret] [data-unseen]
    [data-choices-button] [data-choices]
    [data-control] [data-clear] [data-count] [data-value-text] [data-list] [data-item] [data-add]
    [data-remove] [data-own]
    [data-selection] [data-arguments]
    [data-field] [data-cancel] [data-add-group] [data-remove-group] [data-unpick] [data-clear-field]
    [data-none] [data-take] [aria-current=page]
  )

  @doc "Every marker the hooks find an element by, as `assets/js/markers.js` names them."
  def markers, do: @markers

  # ---- the grid ------------------------------------------------------------

  # The element of a grid's hook. `data-ash-data-table` marks it, for the
  # hooks of the tables nested in it and around it; `data-table` is the
  # table's id; `data-lead` the number of columns before the first data
  # column; `data-select` whether rows can be selected, and how many at a
  # time; `data-choose` that the table is one to choose a record from, and
  # `data-chosen-rows`, where several are chosen, which rows are selected as
  # it opens. No tab stop (`tabindex`), which a browser may make of an
  # element that scrolls: the tab stop of a grid is one of its cells.
  def grid(id, myself, lead, selecting, choose) do
    %{
      "id" => "#{id}-grid",
      "phx-hook" => "AshDataTable.Grid",
      "phx-target" => myself,
      "data-ash-data-table" => true,
      "data-table" => id,
      "data-lead" => lead,
      "data-select" => selecting,
      "data-choose" => not is_nil(choose),
      "data-chosen-rows" => choose && selecting == :multi && held(chosen_rows(choose)),
      "tabindex" => "-1"
    }
  end

  # opens: each as `[key in its id, what the server is told of it]`, the
  # second nil where the key says it.
  defp chosen_rows(choose) do
    for {row_key, names} <- Map.get(choose, :chosen) || [], do: [row_key, names]
  end

  # The grid itself, whose rows are a stream.
  def table(id, label, labelledby, page, summarised?, colcount, selecting, busy?) do
    %{
      "id" => "#{id}-table",
      "role" => "grid",
      "aria-label" => is_nil(labelledby) && label,
      "aria-labelledby" => labelledby,
      "aria-rowcount" => rowcount(page, summarised?),
      "aria-colcount" => colcount,
      "aria-multiselectable" => selecting && to_string(selecting == :multi),
      "aria-busy" => busy? && "true",
      "data-first-row" => Present.first_row(page),
      "phx-update" => "stream"
    }
  end

  # The rows of the grid in all pages: the header rows, the records, and the
  # footer row of the summaries where there is one. -1 says "unknown".
  defp rowcount(%{total: total}, summarised?) when is_integer(total),
    do: total + Present.header_rows() + if(summarised?, do: 1, else: 0)

  defp rowcount(_page, _summarised?), do: -1

  # How many columns the grid has: those before the data columns, the data
  # columns and the actions.
  def colcount(model, lead, acting?), do: length(model.columns) + lead + Common.trail(acting?)

  # A row of the grid that is no record's: the header row, the filter row,
  # the footer rows.
  def row(id, rowindex \\ nil), do: %{"id" => id, "role" => "row", "aria-rowindex" => rowindex}

  # A cell that is no record's, and no column header: of the filter row, of
  # the footer row of the summaries. `colindex` is where it stands.
  def gridcell(id, colindex, more \\ %{}) do
    Map.merge(
      %{"id" => id, "role" => "gridcell", "aria-colindex" => colindex, "tabindex" => "-1"},
      more
    )
  end

  # A cell that spans the grid: a line, the cell a nested table is in, the
  # pages of a nested table, its link to the full view.
  def spanning(id, colspan, more) do
    Map.merge(
      %{
        "id" => id,
        "role" => "gridcell",
        "colspan" => colspan,
        "aria-colindex" => "1",
        "tabindex" => "-1"
      },
      more
    )
  end

  # A header that is no column's: of the boxes that select rows (where one
  # stands for the rows of the page, `data-select-page`), of the expanders,
  # of the actions.
  def header(id, colindex, more \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "role" => "columnheader",
        "scope" => "col",
        "aria-colindex" => colindex,
        "tabindex" => "-1"
      },
      more
    )
  end

  # The header of a column, beside its id, place, role, name and
  # `tabindex`, which the part writes, as it does for every element drawn
  # once per column (D3 b: an opened nested table sends them once per
  # column). `data-label` where it stays in view as the grid scrolls
  # sideways (`sticky_label?`), `data-sort` where it sorts; a click sorts
  # by it.
  def column_header(id, column, sort, label?, myself) do
    sortable? = column.sortable?

    %{
      "aria-sort" => sortable? && aria_sort(sort, column),
      "data-label" => label?,
      "data-sort" => sortable?,
      "phx-click" => sortable? && Common.event(id, "sort"),
      "phx-value-column" => sortable? && column.name,
      "phx-target" => sortable? && myself
    }
  end

  def aria_sort({name, :asc}, %{name: name}), do: "ascending"
  def aria_sort({name, :desc}, %{name: name}), do: "descending"
  def aria_sort(_sort, _column), do: "none"

  # The narrowest and the widest a person can make a column, in pixels.
  # Narrower than this a column is its padding and little else; the widest
  # is there because a separator says where it stands between two ends.
  # The handle at the end of a column's header, with which a person makes
  # the column wider or narrower, says so (`aria-valuemin`, `aria-valuemax`).
  def least_width, do: 48
  def most_width, do: 1000

  # An item of the stream: a record's row group, or the detail under it (a
  # map that says `detail?`). `data-detail` and `data-row` on a detail,
  # which is hidden while it holds no line; `data-key` what the server is
  # told of a record that is selected, where rows can be; `data-current` on
  # the record that is chosen now, in a table to choose from.
  #
  # The rows of the records hold what varies only: their id, `role` and
  # `tabindex`, the same on every row, are written by the part, as every
  # byte of a row is sent again whenever the row is (the design note of
  # stage 7, D3 b: with them in the bundle "Page change" sent 11 % more).
  # So do the row of a record, its cells and its actions cell below.
  def rowgroup(row, selecting) do
    detail? = detail?(row)

    %{
      "hidden" => detail? && is_nil(row.lines),
      "data-detail" => detail?,
      "data-row" => detail? && row.key,
      "data-key" => selecting && !detail? && row.names && held(row.names),
      "data-current" => current?(row)
    }
  end

  # Nil, not false, where it is not: an attribute that is nil is left out,
  # as one that is false.
  def detail?(%{detail?: true}), do: true
  def detail?(_row), do: nil

  defp current?(%{current?: current?}), do: current?
  defp current?(_detail), do: nil

  # The cell of a record under a column. What it says about editing, for
  # people and for the hook:
  #
  #   * `aria-readonly` on a cell that cannot be edited, when the table
  #     offers editing at all;
  #   * `data-value` where the editor's value is not the text the cell shows:
  #     a choice and a boolean, a cell whose content is a component's, and a
  #     cell whose save failed, which shows what was typed;
  #   * on a cell whose save failed, also `aria-invalid`, `aria-describedby`
  #     naming the action's message, and `data-saved`, the value the record
  #     still has, which the hook compares with what is typed next; and
  #     where the action said which values of an array it refused,
  #     `data-invalid`, their places counted from 0, as JSON. The hook marks
  #     the controls of those values when the cell's editor is opened again.
  #
  # A cell of a sensitive column says that its editor holds nothing
  # (`data-value=""`), and nothing else: what was typed into it is never
  # sent back. `data-lines` where the column shows more than one line.
  #
  # `row` is a `AshDataTable.Present.Row`: each cell says whether it can be
  # edited and what failed in it (`AshDataTable.Present.Cell`).
  #
  # `id` is the cell's id; the part writes it with the cell's place and
  # role (D3 b, above).
  def cell(id, column, editing?, row, zone) do
    Map.new([
      {"data-lines", column.max_lines > 1 && column.max_lines}
      | editing(editing?, id, column, row, zone)
    ])
  end

  defp editing(false, _id, _column, _row, _zone), do: []

  defp editing(true, id, column, row, zone) do
    cell = row.cells[column.name]

    case {cell.editable?, cell.failure} do
      {false, _failure} ->
        [{"aria-readonly", "true"}]

      # a reference cell has no editor that holds a value: it is edited in
      # the picker, which opens on the record the row has
      {true, %{}} when column.kind == :reference ->
        [{"aria-invalid", "true"}, {"aria-describedby", "#{id}-error"}]

      {true, nil} when column.kind == :reference ->
        []

      # The editor of a sensitive cell starts empty, and holds nothing of
      # the record: neither does the cell.
      {true, %{}} when column.sensitive? ->
        [
          {"aria-invalid", "true"},
          {"aria-describedby", "#{id}-error"},
          {"data-value", ""},
          {"data-saved", ""}
        ]

      {true, nil} when column.sensitive? ->
        [{"data-value", ""}]

      {true, %{typed: typed, places: places}} ->
        [
          {"aria-invalid", "true"},
          {"aria-describedby", "#{id}-error"},
          {"data-value", held(typed)},
          {"data-saved", held(Typed.of(column, cell.value, zone))}
        ] ++ if(places == [], do: [], else: [{"data-invalid", held(places)}])

      {true, nil} ->
        if own_value?(column),
          do: [{"data-value", held(Typed.of(column, cell.value, zone))}],
          else: []
    end
  end

  # What an editor holds, as a cell says it: the text, and for an array the
  # texts of its values, as JSON.
  def held(texts) when is_list(texts), do: Phoenix.json_library().encode!(texts)
  def held(text), do: text

  # Whether what a column's editor holds is something else than the text its
  # cells show: a choice, which shows its label; a boolean; an array, whose
  # editor holds each value apart; and a column whose component shows the
  # value in a way of its own.
  defp own_value?(%{cell_type: cell_type}) when cell_type in [:boolean, :enum], do: true
  # a map cell has no editor in the cell: nothing is held for one
  defp own_value?(%{cell_type: cell_type})
       when cell_type in [:map, {:array, :map}, :union, {:array, :union}],
       do: false

  defp own_value?(%{cell_type: {:array, _item}}), do: true
  defp own_value?(%{component: %{cell?: true}}), do: true
  defp own_value?(_column), do: false

  # The actions cell of a record. What it says about an action that failed:
  # as a cell whose save failed, `aria-invalid` and `aria-describedby`
  # naming the action's message. `id` is the cell's id.
  def actions(id, row) do
    %{
      "aria-invalid" => row.action_failure && "true",
      "aria-describedby" => row.action_failure && "#{id}-error"
    }
  end

  # The footer row of the summaries, the last of all rows, and the summary
  # of a column in it.
  def summaries(id, page) do
    Map.put(row("#{id}-summaries", Common.summary_rowindex(page)), "data-summaries", true)
  end

  #
  # The cells of the row, as the cells of a record, write their id, place,
  # role and `tabindex` themselves, as the row is sent again while its
  # summaries are on their way and once more when they are there (D3 b).
  def summary(column, summing?) do
    %{"aria-busy" => column.summary && summing? && "true", "data-summary" => column.summary}
  end

  # A row action's button, beside its id, `tabindex` and `data-action`,
  # which the part writes (D3 b): `data-question` the question the hook asks
  # first (none in controlled mode, where the host asks), `data-destructive`
  # on an action that destroys.
  def action(action, asks?) do
    %{"data-question" => asks? && action.confirm, "data-destructive" => action.type == :destroy}
  end

  # The kind of an editable column's editor, on the template the hook
  # copies into the cell being edited (`data-editor`): `secret` for a
  # sensitive column.
  def editor_kind(column), do: if(column.sensitive?, do: :secret, else: column.editor)

  # The control of a column component's editor: what the table gives it.
  def component_control(column) do
    %{
      "aria-label" => column.label,
      "aria-required" => column.required? && "true",
      "data-control" => true
    }
  end

  # The control of a built-in editor whose column has a most it can be
  # long (`Limits.counted/1`): the counter is its description.
  def counted_control(id, column) do
    %{
      "data-control" => true,
      "aria-label" => column.label,
      "aria-required" => column.required? && "true",
      "aria-describedby" => Limits.counted(column) && "#{id}-count"
    }
  end

  # The scrollbar of the grid once more, at the bottom edge of the window:
  # for the pointer alone, which patches leave as the hook has it.
  def scrollbar(id) do
    %{
      "id" => "#{id}-scrollbar",
      "phx-update" => "ignore",
      "aria-hidden" => "true",
      "tabindex" => "-1",
      "hidden" => true,
      "data-scrollbar" => true
    }
  end

  # ---- the table and what is around its grid ---------------------------------

  # The root of a table: the table on the page's (where `AshDataTable`'s
  # wiring draws it), a nested table's in its portal, a picker's table in
  # its dialog. `data-read` once its first read has been shown.
  def root(id, page), do: %{"id" => id, "data-read" => not is_nil(page)}

  # The live region of the table, read out after a filter change and when a
  # save fails.
  def status(id), do: %{"id" => "#{id}-status", "role" => "status", "aria-live" => "polite"}

  # The line above the grid with what is selected: `data-more` where there
  # are more records than the page, and the texts the hook says, with `{n}`
  # where it puts the count.
  def selection(id, more?, total) do
    %{
      "id" => "#{id}-selection",
      "role" => "group",
      "aria-label" => Text.t(:selected_rows),
      "data-selection" => true,
      "data-more" => more?,
      "data-selected" => Text.t(:selected, count: "{n}"),
      "data-all" =>
        if(total, do: Text.t(:all_selected, count: total), else: Text.t(:all_selected_uncounted))
    }
  end

  # The popover with the whole text of a cell whose text is cut off, for the
  # eye alone; the hook writes it.
  def whole(id) do
    %{
      "id" => "#{id}-whole",
      "popover" => "manual",
      "phx-update" => "ignore",
      "aria-hidden" => "true",
      "data-whole" => true
    }
  end

  # The pagination, and its hook. Under a table on the page a navigation
  # landmark; in a nested table a group in its last row.
  def pagination(id, label, nested?) do
    %{
      "id" => "#{id}-pagination",
      "phx-hook" => "AshDataTable.Pagination",
      "data-table" => id,
      "role" => nested? && "group",
      "aria-label" => Text.t(:pagination, table: label)
    }
  end

  # ---- what opens over the page ------------------------------------------------

  # The table's question dialog, which the grid's hook opens.
  def confirm(id) do
    %{"id" => "#{id}-dialog", "role" => "dialog", "aria-labelledby" => "#{id}-dialog-question"}
  end

  # The action panel and its hook. `data-question` the question it asks
  # before a submit, `data-ask` that it asks it only when something changed
  # (a map cell's panel), `data-destructive` on an action that destroys.
  def panel(id, panel, question, target) do
    %{
      "id" => "#{id}-panel",
      "role" => "dialog",
      "phx-hook" => "AshDataTable.Panel",
      "phx-mounted" => JS.ignore_attributes(["open"]),
      "phx-target" => target,
      "data-table" => id,
      "data-question" => question,
      "data-ask" => panel.kind == :cell && "changed",
      "data-destructive" => panel.destructive?,
      "aria-labelledby" => "#{id}-panel-title"
    }
  end

  # The picker and its hook. `data-several` where several records are
  # chosen.
  def picker(id, question, several?, target) do
    %{
      "id" => "#{id}-picker",
      "role" => "dialog",
      "phx-hook" => "AshDataTable.Picker",
      "phx-mounted" => JS.ignore_attributes(["open"]),
      "phx-target" => target,
      "data-table" => id,
      "data-question" => question,
      "data-several" => several?,
      "aria-labelledby" => "#{id}-picker-title"
    }
  end

  # Cancel, in the panel and in the picker.
  def cancel(id), do: %{"id" => id, "data-cancel" => true}

  # "No record", in a picker whose field may be empty.
  def none(id), do: %{"id" => "#{id}-picker-none", "data-none" => true}

  # "Choose": not to be used while no row is selected, and says so without
  # being `disabled`. Which rows are selected is the hook's, so this is too:
  # a patch leaves it alone.
  def take(id, several?) do
    %{
      "id" => "#{id}-picker-choose",
      "aria-disabled" => to_string(not several?),
      "phx-mounted" => JS.ignore_attributes(["aria-disabled"]),
      "data-take" => true
    }
  end
end
