defmodule AshDataTable.Ids do
  @moduledoc """
  The DOM ids that the table's core and a kit's parts must agree on.

  The core names some elements a part draws: the cell focus goes to, the
  cell a nested table is moved into and the button that names it (a
  nested grid's `aria-labelledby`), the field of the action panel and the
  value of an argument focus goes back to after a change. A part draws
  these elements with the ids these functions make, and the core names
  them with the same functions, so neither writes an id by hand that the
  other has to match (target §6, the id scheme).

  `id` is the table's id. A row is named by `key`, the key in its DOM id
  (`AshDataTable.Kit`'s parts are given it as a row's `key`). `row` is a
  row's DOM id, `row(id, key)`, which a part is given as `dom_id`.
  """

  @doc "A record's row group: `ID-row-KEY`, the DOM id of a row of the stream."
  @spec row(String.t(), String.t()) :: String.t()
  def row(id, key), do: "#{id}-row-#{key}"

  @doc "The cell of column `name` in a row: `ROW-c-NAME`."
  @spec cell(String.t(), atom | String.t()) :: String.t()
  def cell(row, name), do: "#{row}-c-#{name}"

  @doc "The actions cell of a row, focus's place where a row has no column: `ROW-a`."
  @spec actions_cell(String.t()) :: String.t()
  def actions_cell(row), do: "#{row}-a"

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
  A field of the action panel, by the way to it: its name, and inside a
  value made of fields the names and the keys of the values on the way
  (`[:place]`, `[:stops, "0", :city]`): `ID-panel-f-NAME-…`.
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
