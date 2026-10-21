defmodule AshDataTable.Ids do
  @moduledoc """
  The DOM ids that the table's core and a kit's parts must agree on.

  The core names some elements a part draws: the cell focus goes to, the
  cell a nested table is moved into and the button that names it (a
  nested grid's `aria-labelledby`), the field of the action panel and the
  value of an argument focus goes back to after a change. A part draws
  these elements with the ids these functions make, and the core names
  them with the same functions, so neither writes an id by hand that the
  other has to match.

  `id` is the table's id. A row is named by `key`, the key in its DOM id
  (`AshDataTable.Kit`'s parts are given it as a row's `key`). `row` is a
  row's DOM id, `row(id, key)`, which a part is given as `dom_id`.

  `assets/js/ids.js` makes the same ids in the browser, function by
  function (`row`, `cell`, `actionsCell`, …), for a kit that draws there;
  a browser test compares the two.
  """

  @doc "A record's row group: `ID-row-KEY`, the DOM id of a row of the stream."
  @spec row(String.t(), String.t()) :: String.t()
  def row(id, key), do: "#{id}-row-#{key}"

  @doc "The cell of column `name` in a row: `ROW-c-NAME`."
  @spec cell(String.t(), atom | String.t()) :: String.t()
  def cell(row, name), do: "#{row}-c-#{name}"

  @doc "The element of a record's row inside its row group: `ROW-r`."
  @spec record(String.t()) :: String.t()
  def record(row), do: "#{row}-r"

  @doc "The actions cell of a row, focus's place where a row has no column: `ROW-a`."
  @spec actions_cell(String.t()) :: String.t()
  def actions_cell(row), do: "#{row}-a"

  @doc "The button of row action `name` in an actions cell `CELL`: `CELL-NAME`."
  @spec action(String.t(), atom | String.t()) :: String.t()
  def action(cell, name), do: "#{cell}-#{name}"

  @doc "The \"Open\" button in an actions cell `CELL`: `CELL-open`."
  @spec open(String.t()) :: String.t()
  def open(cell), do: "#{cell}-open"

  @doc "The row of the line of relationship `name` under a row: `ROW-l-NAME`."
  @spec line(String.t(), atom | String.t()) :: String.t()
  def line(row, name), do: "#{row}-l-#{name}"

  @doc "The cell of a row's selection box: `ROW-s`."
  @spec selector(String.t()) :: String.t()
  def selector(row), do: "#{row}-s"

  @doc "The expander cell of a row: `ROW-e`."
  @spec expander(String.t()) :: String.t()
  def expander(row), do: "#{row}-e"

  @doc "The row group of the lines under an expanded row: `ROW-x`."
  @spec detail(String.t()) :: String.t()
  def detail(row), do: "#{row}-x"

  @doc "The cell of the line of relationship `name` under a row: `ROW-l-NAME-c`."
  @spec line_cell(String.t(), atom | String.t()) :: String.t()
  def line_cell(row, name), do: "#{row}-l-#{name}-c"

  @doc """
  The button that names the line of relationship `name`, and with it the
  nested table's grid (its `aria-labelledby`): `ROW-l-NAME-b`.
  """
  @spec line_button(String.t(), atom | String.t()) :: String.t()
  def line_button(row, name), do: "#{row}-l-#{name}-b"

  @doc """
  The place on the line of relationship `name` that the nested table's
  heading is moved into, its second portal target: `ROW-l-NAME-h`.
  """
  @spec line_heading(String.t(), atom | String.t()) :: String.t()
  def line_heading(row, name), do: "#{row}-l-#{name}-h"

  @doc "The row under a line that the nested table is moved into: `ROW-n-NAME`."
  @spec nested_row(String.t(), atom | String.t()) :: String.t()
  def nested_row(row, name), do: "#{row}-n-#{name}"

  @doc "Its cell, the nested table's portal target: `ROW-n-NAME-c`."
  @spec nested_cell(String.t(), atom | String.t()) :: String.t()
  def nested_cell(row, name), do: "#{row}-n-#{name}-c"

  @doc "The id of the table nested under a row's line of relationship `name`: `ROW-t-NAME`."
  @spec nested_table(String.t(), atom | String.t()) :: String.t()
  def nested_table(row, name), do: "#{row}-t-#{name}"

  @doc """
  The element of the message of an element that failed, which its
  `aria-describedby` names: of a cell or a row's actions cell whose save or
  action failed, of a filter, an argument or a field of the panel that
  holds a value refused: `ELEMENT-error`.
  """
  @spec error(String.t()) :: String.t()
  def error(element), do: "#{element}-error"

  @doc "The header of the grid, a row group with its two rows: `ID-head`."
  @spec head(String.t()) :: String.t()
  def head(id), do: "#{id}-head"

  @doc "The row of the column headers: `ID-head-row`."
  @spec head_row(String.t()) :: String.t()
  def head_row(id), do: "#{id}-head-row"

  @doc "The header of column `name`: `ID-head-NAME`."
  @spec header_cell(String.t(), atom | String.t()) :: String.t()
  def header_cell(id, name), do: "#{id}-head-#{name}"

  @doc """
  The button in the header of column `name` that sorts by it, the header's
  only Tab stop: `ID-sort-NAME`.
  """
  @spec sort(String.t(), atom | String.t()) :: String.t()
  def sort(id, name), do: "#{id}-sort-#{name}"

  @doc """
  The link at the start of a table that jumps past it ("Skip table …"):
  `ID-skip`.
  """
  @spec skip(String.t()) :: String.t()
  def skip(id), do: "#{id}-skip"

  @doc """
  Where that link jumps to, after the table's pagination: an empty element
  that takes the focus, `ID-end`.
  """
  @spec skip_target(String.t()) :: String.t()
  def skip_target(id), do: "#{id}-end"

  @doc "The filter row, the header's second: `ID-filter-row`."
  @spec filter_row(String.t()) :: String.t()
  def filter_row(id), do: "#{id}-filter-row"

  @doc "The form of the filter row, which its controls name (`form=`): `ID-filters`."
  @spec filters(String.t()) :: String.t()
  def filters(id), do: "#{id}-filters"

  @doc """
  The `<template>` of the editor of column `name`, which the grid's hook
  copies into a cell to edit it: `ID-editor-NAME`.
  """
  @spec editor(String.t(), atom | String.t()) :: String.t()
  def editor(id, name), do: "#{id}-editor-#{name}"

  @doc "The table's question: `ID-dialog`."
  @spec dialog(String.t()) :: String.t()
  def dialog(id), do: "#{id}-dialog"

  @doc """
  The place inside the action panel that what opens in it is moved into
  (a portal): the picker a field opened, where the
  panel is modal and the picker inline, and the question's copy:
  `ID-panel-place`.
  """
  @spec panel_place(String.t()) :: String.t()
  def panel_place(id), do: "#{id}-panel-place"

  @doc """
  The place inside the picker that its table is moved into, with the
  question's copy where the picker is modal and the question inline:
  `ID-picker-place`.
  """
  @spec picker_place(String.t()) :: String.t()
  def picker_place(id), do: "#{id}-picker-place"

  @doc """
  A field of the action panel, by the way to it: its name, and inside a
  value made of fields the segments on the way, which
  `AshDataTable.GroupValue.at/2` and `inside/2` make (`[:place]`,
  `["stops", "0", "f", "city"]`): `ID-panel-f-NAME-…`.
  """
  @spec field(String.t(), [atom | String.t() | integer]) :: String.t()
  def field(id, path), do: Enum.join(["#{id}-panel-f" | path], "-")

  @doc "The button of a field that clears a sensitive value, or keeps it: `FIELD-clear`."
  @spec clear(String.t()) :: String.t()
  def clear(field), do: "#{field}-clear"

  @doc "The button of a field that opens the picker: `FIELD-choose`."
  @spec choose(String.t()) :: String.t()
  def choose(field), do: "#{field}-choose"

  @doc "The button that takes the record at place `at` out of a field of several: `FIELD-r-AT`."
  @spec unpick(String.t(), non_neg_integer) :: String.t()
  def unpick(field, at), do: "#{field}-r-#{at}"

  @doc """
  An argument of the argument line, by `named`
  (`AshDataTable.Model.Argument.argument_id/1`): `ID-arg-NAMED`.
  """
  @spec argument(String.t(), String.t()) :: String.t()
  def argument(id, named), do: "#{id}-arg-#{named}"

  @doc """
  A value of an argument that takes several, at place `at`, or the button
  that adds one (`:add`): `ARGUMENT-AT`, `ARGUMENT-add`.
  """
  @spec argument_value(String.t(), non_neg_integer | :add) :: String.t()
  def argument_value(argument, at), do: "#{argument}-#{at}"
end
