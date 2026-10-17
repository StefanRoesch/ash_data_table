defmodule AshDataTable.Intent do
  @moduledoc false
  # What a person asks a table for, parsed once from an event of the
  # browser (docs/architecture/target.md 4.3):
  # one tagged value per event of the "Events" list of
  # `docs/agents/architecture.md`.
  #
  # Only the shape is checked: text where text is expected, a list where a
  # list is. Every value stays a claim. Names stay text: nothing is looked
  # up here, nothing becomes an atom, no record is read. Whether a column
  # can be edited, an action is offered or a row is on the page is the live
  # layer's to check, as before.
  #
  # `parse/2` refuses no payload that the table took before it existed:
  # where the table looked a value up without asking its type first (a
  # column's name, say), a value of another type found nothing there, and
  # is refused here with the same answer (see `malformed/2` in the table
  # component). `:malformed` is answered as the table answered such an
  # event: that answer is the live layer's.

  @typedoc "A key in a row's DOM id, as the browser names a row: a claim."
  @type key :: String.t()

  @typedoc """
  What a person has selected, as the hook says it on every change: every
  record the filters match (`:all`), or the rows named (`{:rows, rows}`,
  none for nothing selected). Each row as the hook names it, its primary
  key: a claim.
  """
  @type selection :: :all | {:rows, [term]}

  @type t ::
          {:sort, String.t()}
          | {:filter, map}
          | {:clear_filter, String.t()}
          | {:filter_values, String.t(), String.t()}
          | :clear_filters
          | {:page, String.t()}
          | {:page_size, String.t()}
          | {:arguments, map}
          | {:argument_add, String.t()}
          | {:argument_remove, String.t(), non_neg_integer}
          | {:expand, key}
          | {:toggle, key, String.t()}
          | {:save, key, String.t(), String.t()}
          | {:clear, key, String.t()}
          | {:discard, key, String.t()}
          | {:dismiss, key}
          | {:reveal, key, String.t()}
          | {:edit, key, String.t()}
          | {:act, key, String.t()}
          | {:open, key}
          | :create
          | {:table_act, String.t()}
          | {:table_run, String.t()}
          | {:select, selection}
          | {:bulk, String.t()}
          | {:bulk_run, String.t(), String.t()}
          | :bulk_seen
          | {:panel_validate, map}
          | {:panel_submit, map}
          | {:panel_add, [String.t(), ...]}
          | {:panel_remove, [String.t(), ...]}
          | {:panel_unpick, String.t(), String.t()}
          | {:panel_clear, String.t()}
          | :panel_cancel
          | {:pick, key, String.t()}
          | {:pick_input, String.t()}
          | {:picked, picked}
          | :picker_cancel
          | {:left, key}
          | :read_again

  @typedoc """
  What the picker says was chosen: `row` (one row, nil for none) or `rows`
  (where several are chosen), each as the grid's hook names it; whether
  the person answered the column's question; and what the argument line
  of the picker's table holds, as its form sends it (nil where the event
  says nothing of it). All of it claims.
  """
  @type picked :: %{
          none?: boolean,
          confirmed?: boolean,
          arguments: String.t() | nil
        }

  @doc "The intent of an event, or `:malformed` for a payload of another shape."
  @spec parse(String.t(), map) :: {:ok, t} | :malformed
  def parse(event, params)

  # Reading
  def parse("sort", %{"column" => column}) when is_binary(column), do: {:ok, {:sort, column}}
  def parse("filter", params), do: {:ok, {:filter, form(params, "filter")}}

  def parse("clear_filter", %{"column" => column}) when is_binary(column),
    do: {:ok, {:clear_filter, column}}

  def parse("clear_filters", _params), do: {:ok, :clear_filters}

  # The button of a filter for several values: the column and the operator.
  def parse("filter_values", %{"column" => column, "operator" => operator})
      when is_binary(column) and is_binary(operator),
      do: {:ok, {:filter_values, column, operator}}

  def parse("page", %{"to" => to}) when is_binary(to), do: {:ok, {:page, to}}
  def parse("page_size", %{"size" => size}) when is_binary(size), do: {:ok, {:page_size, size}}

  # The argument line
  def parse("arguments", params), do: {:ok, {:arguments, form(params, "arguments")}}

  def parse("argument_add", %{"argument" => argument}) when is_binary(argument),
    do: {:ok, {:argument_add, argument}}

  def parse("argument_remove", %{"argument" => argument, "at" => at})
      when is_binary(argument) and is_binary(at) do
    case Integer.parse(at) do
      {at, ""} when at >= 0 -> {:ok, {:argument_remove, argument, at}}
      _not_a_place -> :malformed
    end
  end

  # Nested tables
  def parse("expand", %{"row" => row}) when is_binary(row), do: {:ok, {:expand, row}}

  def parse("toggle", %{"row" => row, "relationship" => relationship})
      when is_binary(row) and is_binary(relationship),
      do: {:ok, {:toggle, row, relationship}}

  # Cells. What was typed is text.
  def parse("save", %{"row" => row, "column" => column, "value" => typed})
      when is_binary(row) and is_binary(column) and is_binary(typed),
      do: {:ok, {:save, row, column, typed}}

  def parse(event, %{"row" => row, "column" => column})
      when event in ["clear", "discard", "reveal", "edit", "pick"] and is_binary(row) and
             is_binary(column),
      do: {:ok, {tag(event), row, column}}

  def parse("dismiss", %{"row" => row}) when is_binary(row), do: {:ok, {:dismiss, row}}

  # Row actions and create
  def parse("act", %{"row" => row, "action" => action}) when is_binary(row) and is_binary(action),
    do: {:ok, {:act, row, action}}

  def parse("create", _params), do: {:ok, :create}
  def parse("open", %{"row" => row}) when is_binary(row), do: {:ok, {:open, row}}

  # Table actions
  def parse("table_act", %{"action" => action}) when is_binary(action),
    do: {:ok, {:table_act, action}}

  def parse("table_run", %{"action" => action}) when is_binary(action),
    do: {:ok, {:table_run, action}}

  # Selection: what is selected, on every change, and an action on it
  def parse("select", %{"all" => true}), do: {:ok, {:select, :all}}
  def parse("select", %{"rows" => rows}) when is_list(rows), do: {:ok, {:select, {:rows, rows}}}

  def parse("bulk", %{"action" => action}) when is_binary(action), do: {:ok, {:bulk, action}}

  # with the token of the selection its question named
  def parse("bulk_run", %{"action" => action, "selection" => token})
      when is_binary(action) and is_binary(token),
      do: {:ok, {:bulk_run, action, token}}

  def parse("bulk_seen", _params), do: {:ok, :bulk_seen}

  # The action panel
  def parse("panel_validate", params), do: {:ok, {:panel_validate, form(params, "panel")}}
  def parse("panel_submit", params), do: {:ok, {:panel_submit, form(params, "panel")}}

  def parse(event, %{"path" => [name | _] = path})
      when event in ["panel_add", "panel_remove"] and is_binary(name) do
    if Enum.all?(path, &is_binary/1),
      do: {:ok, {tag(event), path}},
      else: :malformed
  end

  def parse("panel_unpick", %{"input" => input, "key" => key})
      when is_binary(input) and is_binary(key),
      do: {:ok, {:panel_unpick, input, key}}

  def parse("panel_clear", %{"input" => input}) when is_binary(input),
    do: {:ok, {:panel_clear, input}}

  def parse("panel_cancel", _params), do: {:ok, :panel_cancel}

  # The picker
  def parse("pick_input", %{"input" => input}) when is_binary(input),
    do: {:ok, {:pick_input, input}}

  # The record is the one selected in the picker's table, which the server
  # holds: the event names none (`none` for "None").
  def parse("picked", %{} = params) do
    {:ok,
     {:picked,
      %{
        none?: params["none"] == true,
        confirmed?: params["confirmed"] == true,
        arguments: if(is_binary(params["arguments"]), do: params["arguments"])
      }}}
  end

  def parse("picker_cancel", _params), do: {:ok, :picker_cancel}

  # Live updates
  def parse("left", %{"row" => row}) when is_binary(row), do: {:ok, {:left, row}}
  def parse("read_again", _params), do: {:ok, :read_again}

  def parse(_event, _params), do: :malformed

  # The tag of an event that shares its clause with others, by its name.
  defp tag("clear"), do: :clear
  defp tag("discard"), do: :discard
  defp tag("reveal"), do: :reveal
  defp tag("edit"), do: :edit
  defp tag("pick"), do: :pick
  defp tag("panel_add"), do: :panel_add
  defp tag("panel_remove"), do: :panel_remove

  # What a form sent, under its name; nothing where it sent no form.
  defp form(%{} = params, name) do
    case params do
      %{^name => %{} = form} -> form
      _other -> %{}
    end
  end

  # A payload that is no map at all (a forged push) sent no form either,
  # as the table took it before.
  defp form(_params, _name), do: %{}
end
