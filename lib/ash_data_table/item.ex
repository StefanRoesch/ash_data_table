defmodule AshDataTable.Item do
  @moduledoc """
  An item of a table's stream: what a kit draws a row of the grid from,
  for every kit (ADR 0002). The grid part's `rows` is the table's stream
  as `@streams[name]` gives it; a kit hands it on unchanged (to `:for` in
  HEEx, to a client component as a prop) and draws each item as a record's
  row or as the detail under it.

  An item is a plain map, made where the row is put into the stream, in
  the LiveView's process: each cell already holds its finished text, in
  the person's language and the page's time zone. So a kit that draws in
  the browser shows the text as it is and formats nothing itself. It holds
  plain data only (strings, numbers, booleans, atoms, maps and lists),
  but a column's `component` value (below): it goes to JSON as it is.

  ## A record's row

      %{
        dom_id: "tasks-row-42",
        key: "42",
        rowindex: 3,
        names: nil,
        open: false,
        current: false,
        failure: nil,
        attrs: %{},
        cells: %{
          title: %{
            state: :value,
            text: "Buy milk",
            value: nil,
            editable: true,
            failure: nil,
            attrs: %{}
          }
        }
      }

    * `dom_id` - the row's DOM id (`AshDataTable.Ids.row/2`), the item's
      id in the stream
    * `key` - the key in the row's DOM id, by which its events name it (a
      claim when it comes back)
    * `rowindex` - its `aria-rowindex`, counted from 1 with the header's
      rows
    * `names` - what the hook names the row by where `key` does not (a
      primary key that is no DOM id): its values as text; else nil
    * `open` - whether the row is expanded
    * `current` - in a picker's table, whether it is the record chosen now
    * `failure` - of a row action that failed: `%{text: text, message:
      message}` (`AshDataTable.Messages`); else nil
    * `attrs` - the row group's attributes that vary (`data-key`,
      `data-current`): to spread on the element with `role=rowgroup`
    * `cells` - by column name, a cell each

  A cell:

    * `state` - `:value`, `:empty`, `:masked` (a sensitive value that is
      there) or `:forbidden` (a field hidden from the person on this
      record). A union is in the state of what it holds: a kind the person
      may not see is `:forbidden`, none is `:empty`
    * `text` - in the state `:value`, the value as the cell shows it,
      finished and translated; nil in every other state
    * `value` - the raw value, only where a kit needs it beside the text:
      of a column whose `component` draws its cells (the component is given
      it), and a yes or no (`true`, `false`: a boolean, or a union that
      holds one), which `Kit.Default` draws as a mark. Nil else. A
      component's value is what the record holds (a `Decimal`, a date, …),
      which a bridge to the browser encodes
    * `editable` - whether the person can edit this cell of this row
    * `failure` - after a save failed: `typed` (what was typed, `""` for a
      sensitive column), `text` and `message` (what the action said);
      else nil
    * `attrs` - the cell's attributes that vary (`tabindex` and
      `aria-describedby` on a cell that can be edited, `data-failed`,
      `data-value`, `data-saved`, see `AshDataTable.Attrs.cell/2`)

  A masked cell has no `text` and no `value`: nothing of a sensitive value
  is in an item (the row is scrubbed before, `AshDataTable.Present`).

  ## The detail under a row

      %{
        dom_id: "tasks-row-42-x",
        detail: true,
        key: "42",
        lines: [
          %{
            name: :comments,
            open: true,
            count: 2,
            text: "2 records",
            message: %{key: :records, values: %{count: 2}}
          }
        ],
        attrs: %{"data-detail" => true, "data-row" => "42"}
      }

    * `dom_id` - its DOM id (`AshDataTable.Ids.detail/1`)
    * `detail` - always `true`: what tells a detail from a row
    * `key` - the key of the row it is under
    * `lines` - nil while the row is not expanded; else one per
      relationship the row offers, in the model's order: `name`, `open`
      (whether its nested table is open), `count` (how many records the
      open nested table has, once it has read; else nil) and `text` (that
      number in words; else nil) and `message` (what that text says,
      `AshDataTable.Messages`; else nil)
    * `attrs` - the row group's attributes (`hidden` while it holds no
      line, `data-detail`, `data-row`)

  ## Attributes

  `attrs` holds the attributes that vary by row or cell, named as in HTML,
  each value a string, or `true` for an attribute without a value; an
  attribute that is not there is not in the map. HEEx spreads it as it is
  (`<tbody {item.attrs}>`); a kit in the browser takes `true` as `""`
  (`AshDataTable.Attrs.props/1`). The attributes that are the same on every
  row and cell are not in it: the part writes them (`AshDataTable.Kit`).

  ## What is not in an item

  The texts that are the same on every row (a masked cell's "Show", "Not
  available", a row's "Select row") are not in it, so a row carries only
  what varies: a part is given them once (`AshDataTable.Kit.Words`, the
  `texts` of `row` and `cell`; per column `Kit.Words.texts(:cell, %{column:
  column, cell: %{state: :masked, failure: nil}})`).
  """

  alias AshDataTable.Format
  alias AshDataTable.Ids
  alias AshDataTable.Messages
  alias AshDataTable.Present
  alias AshDataTable.Text
  alias AshDataTable.Typed

  @typedoc "An item: a record's row, or the detail under it (see the moduledoc)."
  @type t :: %{
          required(:dom_id) => String.t(),
          required(:key) => String.t(),
          optional(atom) => term
        }

  @doc """
  The item of a record's row, of a `Present.Row` (scrubbed): `model` the
  table's, `table` what the table says of all its rows: `id` (the table's),
  `time_zone` (the page's), `editing?` (whether the table offers editing
  at all) and `selecting` (`:single`, `:multi` or nil). Its texts are said
  in the locale of this process.
  """
  @spec row(map, Present.Row.t(), map) :: t
  def row(model, %Present.Row{} = row, %{
        id: id,
        time_zone: zone,
        editing?: editing?,
        selecting: selecting
      }) do
    %{
      dom_id: row.dom_id,
      key: row.key,
      rowindex: row.rowindex,
      names: row.names,
      open: row.open?,
      current: row.current?,
      failure: row.action_failure && said(row.action_failure),
      attrs:
        plain(%{
          "data-key" => selecting && row.names && held(row.names),
          "data-current" => row.current?
        }),
      cells:
        Map.new(model.columns, fn column ->
          {column.name, cell(column, row.cells[column.name], row.dom_id, zone, editing? && id)}
        end)
    }
  end

  @doc """
  The item of the detail under the row `key` of the table `id`: `lines` the
  names of its open relationships, nil while the row is not expanded;
  `counts` how many records each open nested table has, where that is
  known.
  """
  @spec detail(map, String.t(), String.t(), [atom] | nil, map) :: t
  def detail(model, id, key, lines, counts \\ %{}) do
    %{
      dom_id: Ids.detail(Ids.row(id, key)),
      detail: true,
      key: key,
      lines: lines && Enum.map(model.relationships, &line(&1, lines, counts)),
      attrs: plain(%{"hidden" => is_nil(lines), "data-detail" => true, "data-row" => key})
    }
  end

  defp line(relationship, open, counts) do
    open? = relationship.name in open
    count = if open?, do: Map.get(counts, relationship.name)

    message = count && {:text, :records, count: count}

    %{
      name: relationship.name,
      open: open?,
      count: count,
      text: message && Text.say(message),
      message: message && Messages.of(message)
    }
  end

  # `editing` is the table's id where it offers editing, else false.
  defp cell(column, cell, dom_id, zone, editing) do
    {state, value} = held_state(column, cell)

    %{
      state: state,
      text: if(state == :value, do: Format.format(column, cell.value, zone)),
      value: value,
      editable: cell.editable?,
      failure: cell.failure && Map.put(said(cell.failure.message), :typed, cell.failure.typed),
      attrs: plain(Map.new(editing(editing, Ids.cell(dom_id, column.name), column, cell, zone)))
    }
  end

  # The state a cell is in, and the raw value a kit needs beside its text.
  defp held_state(
         %{cell_type: :union, members: [_ | _] = members},
         %{state: :value, value: %Ash.Union{type: kind, value: held}}
       ) do
    case {Enum.find(members, &(&1.name == kind)), held} do
      {nil, _held} -> {:value, nil}
      {_kind, %Ash.ForbiddenField{}} -> {:forbidden, nil}
      {_kind, nil} -> {:empty, nil}
      {%{cell_type: :boolean}, held} when is_boolean(held) -> {:value, held}
      {_kind, _held} -> {:value, nil}
    end
  end

  defp held_state(%{component: %{cell?: true}}, %{state: :value} = cell), do: {:value, cell.value}

  defp held_state(%{cell_type: :boolean}, %{state: :value, value: value})
       when is_boolean(value),
       do: {:value, value}

  defp held_state(_column, cell), do: {cell.state, nil}

  # A message as a part is given it: its text and what it is made of.
  defp said(message), do: %{text: Text.say(message), message: Messages.of(message)}

  # What a cell says about editing, for people and for the hook
  # (`AshDataTable.Attrs.cell/2` documents each). A read-only cell says
  # nothing: it is no Tab stop. An editable one is (`tabindex="0"`), and is
  # described by the table's text that says it can be edited, and by its
  # message where its save failed.
  defp editing(false, _id, _column, _cell, _zone), do: []
  defp editing(_table, _id, _column, %{editable?: false}, _zone), do: []

  defp editing(table, id, column, cell, zone) do
    editable = Ids.editable(table)

    [{"tabindex", "0"}, {"aria-describedby", described(editable, id, cell.failure)}] ++
      case cell.failure do
        nil -> held_value(column, cell, zone)
        failure -> failed(column, cell, failure, zone)
      end
  end

  defp described(editable, _id, nil), do: editable
  defp described(editable, id, _failure), do: editable <> " " <> Ids.error(id)

  # What the editor of a cell holds where it is not the text the cell shows.
  # A reference cell has no editor that holds a value: it is edited in the
  # picker, which opens on the record the row has. The editor of a
  # sensitive cell starts empty, and holds nothing of the record: neither
  # does the cell.
  defp held_value(%{kind: :reference}, _cell, _zone), do: []
  defp held_value(%{sensitive?: true}, _cell, _zone), do: [{"data-value", ""}]

  defp held_value(column, cell, zone) do
    if own_value?(column),
      do: [{"data-value", held(Typed.of(column, cell.value, zone))}],
      else: []
  end

  defp failed(%{kind: :reference}, _cell, _failure, _zone), do: [{"data-failed", true}]

  defp failed(%{sensitive?: true}, _cell, _failure, _zone),
    do: [{"data-failed", true}, {"data-value", ""}, {"data-saved", ""}]

  defp failed(column, cell, %{typed: typed}, zone),
    do: [
      {"data-failed", true},
      {"data-value", typed},
      {"data-saved", held(Typed.of(column, cell.value, zone))}
    ]

  # Whether what a column's editor holds is something else than the text its
  # cells show: a choice, which shows its label; a boolean; and a column
  # whose component shows the value in a way of its own. A column edited in
  # the side panel has no editor in the cell: nothing is held for one.
  defp own_value?(%{cell_type: cell_type}) when cell_type in [:boolean, :enum], do: true

  defp own_value?(%{editor: editor}) when editor in [:choices, :list, :group, :groups, :union],
    do: false

  defp own_value?(%{component: %{cell?: true}}), do: true
  defp own_value?(_column), do: false

  # What an attribute holds of a list (as JSON) or a text (as it is).
  defp held(texts) when is_list(texts), do: Phoenix.json_library().encode!(texts)
  defp held(text), do: text

  # The attributes that are there: nil and false left out, `true` kept for
  # an attribute without a value, every other value as text.
  defp plain(attributes) do
    for {name, value} <- attributes, value not in [nil, false], into: %{} do
      {name, if(value == true, do: true, else: to_string(value))}
    end
  end
end
