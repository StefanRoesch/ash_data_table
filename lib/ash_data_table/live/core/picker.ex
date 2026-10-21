defmodule AshDataTable.Live.Core.Picker do
  @moduledoc false
  # The picker: open, choose, cancel, and the fields of the
  # action panel given by choosing related records.
  #
  # Over the table (stage 9g): opening the picker (`pick`, `pick_input`),
  # Cancel and taking a chosen record out of a field (`panel_unpick`) are
  # steps (`step/3`); a choice saves or fills the panel on the socket
  # (`on/2`).

  alias AshDataTable.Ids
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Cells
  alias AshDataTable.Live.Core.Opener
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Live.Core.Selection
  alias AshDataTable.Model
  alias AshDataTable.Operation
  alias AshDataTable.Panel
  alias AshDataTable.Pick
  alias AshDataTable.Query
  alias AshDataTable.Record
  alias AshDataTable.State
  alias AshDataTable.Table
  alias AshDataTable.Text

  require AshDataTable.Live.Current, as: Current

  # Sent by the panel's hook when a person uses the button that takes one
  # of the chosen records out of a field that holds several: the field, and
  # the record's key as the field holds it. The panel is rendered again
  # without it, and the action is told as it is of anything typed. The
  # answer says where focus goes: to what stands where the record stood.
  def step({:panel_unpick, name, key}, table, _context) when is_map(table.entry.panel) do
    %{id: id, model: model, panel: panel} = table.entry

    with %{editor: :references} = input <- Panel.reference(panel, name),
         held = Panel.keys(panel, name),
         at when is_integer(at) <- Enum.find_index(held, &(&1 == key)) do
      keys = List.delete_at(held, at)
      field = Ids.field(id, [name])

      focus =
        cond do
          at < length(keys) -> Ids.unpick(field, at)
          at > 0 -> Ids.unpick(field, at - 1)
          true -> Ids.choose(field)
        end

      {Core.Panel.put(table, Panel.hold(panel, model, input, keys)),
       [Core.Panel.focus(table, focus)], nil}
    else
      _ -> {table, [], nil}
    end
  end

  def step({:panel_unpick, _name, _key}, table, _context), do: {table, [], nil}

  # Sent by the hook when a person opens the editor of a reference cell: the
  # row by the key in its DOM id, and the column. The picker opens; nothing
  # is saved. The record is read first, as the person: the picker opens on
  # the record the cell points at now.
  def step({:pick, key, name}, table, context) do
    %{model: model, rows: rows} = table.entry

    with %{editable?: true, kind: :reference, reference: reference} = column <-
           Operation.column(model, name),
         %{} = row <- rows[key] do
      case Record.fetch(model, row.pk, Query.reader_opts(Core.reader(table, context))) do
        {:ok, record} ->
          case Map.get(record, reference.source_attribute) do
            # not theirs to see on this record, and so not theirs to change
            %Ash.ForbiddenField{} ->
              {table, [], %{ok: false}}

            current ->
              picker = %{
                for: {:cell, key, column.name},
                name: column.name,
                reference: reference,
                title: picker_title(column.label, reference),
                several?: false,
                chosen: [],
                current: current,
                allow_none?: reference.allow_nil?,
                question: column.confirm,
                error: nil
              }

              {Table.put(table, picker: picker), [], %{ok: true}}
          end

        :error ->
          message = {:text, :record_gone, []}

          {Core.say(table, {:text, :not_saved, column: column.label, message: message}), [],
           %{ok: false, error: Text.say(message)}}
      end
    else
      _ -> {table, [], %{ok: false}}
    end
  end

  # Sent by the button of a field of the action panel that holds the key of
  # a related record: the picker opens on top of the panel, on the record
  # the field holds now.
  def step({:pick_input, name}, table, _context) when is_map(table.entry.panel) do
    panel = table.entry.panel

    case Panel.reference(panel, name) do
      nil ->
        {table, [], nil}

      # several records: the picker opens with the rows selected of the
      # records the field holds now, on whatever page they are
      %{editor: :references} = input ->
        known = Panel.known(panel, input.name)

        picker = %{
          for: {:input, input.name},
          name: input.name,
          reference: input.reference,
          title: picker_title(input.label, input.reference),
          several?: true,
          current: nil,
          chosen:
            for(key <- Panel.keys(panel, name), %{row: {_, _} = row} <- [known[key]], do: row),
          allow_none?: false,
          question: nil,
          error: nil
        }

        {Table.put(table, picker: picker), [], nil}

      input ->
        picker = %{
          for: {:input, input.name},
          name: input.name,
          reference: input.reference,
          title: picker_title(input.label, input.reference),
          several?: false,
          current: Reading.blank_as_nil(Panel.held(panel, input)),
          chosen: [],
          allow_none?: not input.required?,
          question: nil,
          error: nil
        }

        {Table.put(table, picker: picker), [], nil}
    end
  end

  def step({:pick_input, _name}, table, _context), do: {table, [], nil}

  # Sent by the picker's hook for Cancel and Escape.
  def step(:picker_cancel, table, _context), do: {Table.put(table, picker: nil), [], nil}

  # Sent by the picker's hook when the person has chosen: the row they
  # selected, as the grid's hook names it (its primary key), or nil for no
  # record; and `confirmed`, once they have answered the column's question.
  # Where several records are chosen, `rows` in place of `row`: every row
  # that is selected.
  #
  # The row is a claim. Which cell or field it is chosen for is the
  # server's to say, from what the picker was opened for.
  # Sent by the picker's hook for "Choose", Enter or a double click on a row
  # of its table, and "None": the record chosen is the row selected in the
  # picker's table, as that table holds it (the hook tells it every change,
  # `select`), and where several are chosen every row selected; for one, a
  # row of the page only. Each is a claim still, read again as the person.
  def on({:picked, picked}, socket) when is_map(Current.entry(socket, :picker)) do
    %{id: id, picker: picker} = Core.table(socket).entry
    chooser = Core.table(socket).entries["#{id}-pick-#{picker.name}"]

    cond do
      picked.none? ->
        picked(socket, Map.merge(picked, %{row: nil, rows: []}), :hook)

      picker.several? ->
        picked(
          socket,
          Map.merge(picked, %{row: nil, rows: (chooser && chooser.selected) || []}),
          :hook
        )

      (row = chooser && List.first(Selection.in_view(chooser))) != nil ->
        picked(socket, Map.merge(picked, %{row: row, rows: nil}), :hook)

      true ->
        {:reply, %{ok: false}, socket}
    end
  end

  def on({:picked, _picked}, socket), do: {:reply, %{ok: false}, socket}

  # The host's choice for the picker it draws (`picked/2`).
  def on({:chosen, keys}, socket), do: picked(socket, keys)

  # The host's Confirm of a reference cell's question (controlled mode):
  # the choice saves, as it would have from the hook.
  def on({:confirmed, {:refer, key, name, named, arguments}}, socket),
    do: refer(socket, key, name, named, arguments, true)

  @doc """
  The host's choice for the picker it draws (controlled mode,
  `AshDataTable.pick_request/4`): a primary key (a map, or the value of a
  key of one field), a list of them where several are chosen, or nil for
  none. Each is a claim, taken as a row the browser names.
  """
  def picked(socket, keys) do
    case Core.table(socket).entry.picker do
      %{reference: reference, several?: several?} ->
        named = &named_key(reference.destination, &1)

        picked =
          if several?,
            do: %{
              row: nil,
              rows: Enum.map(List.wrap(keys), named),
              confirmed?: false,
              arguments: nil
            },
            else: %{row: named.(keys), rows: nil, confirmed?: false, arguments: nil}

        picked = Map.put(picked, :none?, false)

        picked(socket, picked, :host)

      nil ->
        {:noreply, socket}
    end
  end

  # A key as the host gives it, as the browser names a row: the values of
  # the primary key in its order. A map without one of them is a mistake of
  # the host's, never "none".
  defp named_key(_destination, nil), do: nil

  defp named_key(destination, %{} = key) do
    fields = Ash.Resource.Info.primary_key(destination)

    values =
      for field <- fields do
        case Map.fetch(key, field) do
          {:ok, value} ->
            value

          :error ->
            raise ArgumentError,
                  "AshDataTable.pick_request/4 was given the key #{inspect(key, limit: 5)}, " <>
                    "which has no `#{inspect(field)}`. A key of #{inspect(destination)} is a map " <>
                    "of the fields of its primary key, by their names as atoms " <>
                    "(#{Enum.map_join(fields, ", ", &inspect/1)}), or the value of a key of one field."
        end
      end

    case values do
      [value] -> value
      values -> values
    end
  end

  defp named_key(_destination, value), do: value

  defp picked(socket, picked, by) do
    picker = Core.table(socket).entry.picker

    %{panel: panel} = Core.table(socket).entry
    named = picked.row
    # what the picker's read action is given: what its argument line holds
    arguments = picked_with(socket, picker.reference, picked.arguments)

    case picker.for do
      {:cell, key, name} ->
        refer(socket, key, name, named, arguments, picked.confirmed?, by)

      {:input, name} ->
        case panel && Panel.reference(panel, Atom.to_string(name)) do
          %{editor: :references} = input ->
            choose_inputs(socket, panel, input, picked.rows, arguments)

          %{} = input ->
            choose_input(socket, panel, input, named, arguments)

          _ ->
            {:reply, %{ok: false}, Core.put(socket, picker: nil)}
        end
    end
  end

  @doc """
  The choice of a related record for a reference cell
  (`AshDataTable.Operation.refer/1`), `confirmed?` once the column's
  question was answered. The question is asked (`Opener.ask/4`): where
  the host asks it (controlled mode), the choice waits, the picker closes
  and the hook is told the cell waits (`held`). Where the table asks it,
  the hook does, but where the host draws the picker: the host has shown
  the question with its chooser (`question` of its request), and its
  choice is the answer.
  """
  def refer(socket, key, name, named, arguments, confirmed?, by \\ :hook) do
    %{model: model, rows: rows} = Core.table(socket).entry
    column = Enum.find(model.columns, &(&1.name == name))
    intent = {:refer, key, name, named, confirmed?, arguments}

    case Operation.refer(Core.operation(Core.table(socket), Core.context(socket), intent)) do
      :refused ->
        {:reply, %{ok: false}, Core.put(socket, picker: nil)}

      {:ask, question} ->
        about = %{
          action: column.update_action,
          key: rows[key].pk,
          column: column,
          value: shown_key(column.reference.destination, named)
        }

        case Opener.ask(socket, {:refer, key, name, named, arguments}, column.confirm, about) do
          {:held, reply, socket} -> {:reply, reply, Core.put(socket, picker: nil)}
          {:run, socket} when by == :host -> refer(socket, key, name, named, arguments, true, by)
          {:run, socket} -> Cells.referred({:ask, question}, socket, key, column)
        end

      result ->
        Cells.referred(result, socket, key, column)
    end
  end

  # The chosen record's key as the host's request says it: the value of a
  # key of one field (the hook names a row by the list of its key's values),
  # the list of them for a key of several.
  defp shown_key(destination, [value]) do
    if match?([_one], Ash.Resource.Info.primary_key(destination)), do: value, else: [value]
  end

  defp shown_key(_destination, named), do: named

  # The choice of a related record for a field of the action panel: its key
  # goes into the panel's form, as if it had been typed there, with what the
  # record is called beside it. Nothing runs.
  defp choose_input(socket, panel, input, named, arguments) do
    chosen =
      with false <- is_nil(named),
           {:ok, record} <-
             Pick.chosen(
               input.reference,
               named,
               [arguments: arguments] ++ chooser(socket)
             ),
           {:ok, entry} <- entry(input, record, Core.table(socket).caller.time_zone) do
        entry
      else
        true -> {"", nil}
        :error -> :error
      end

    case chosen do
      :error ->
        {:reply, %{ok: false}, unavailable(socket)}

      # the key is looked up once more when the action runs: through the
      # picker's read action as it was given when it was chosen
      chosen ->
        panel = Panel.choose(panel, Core.table(socket).entry.model, input, chosen, arguments)
        {:reply, %{ok: true}, socket |> Core.put(picker: nil) |> Core.Panel.put(panel)}
    end
  end

  # The choice of several related records for a field of the action panel:
  # `rows` are the rows that are selected in the picker, each as its grid's
  # hook names it. The field then holds the records it held and whose rows
  # are still selected, in their order, and after them those that were
  # selected besides. A record the field held and that the picker could not
  # show (one this person may not read there) has no row to take the mark
  # off: it stays, until its own button takes it away.
  #
  # A row is a claim. One that names a record the field holds already is
  # that record; any other is read, as the person, and one that names
  # nothing they may read chooses nothing at all.
  defp choose_inputs(socket, panel, input, rows, arguments) when is_list(rows) do
    held = Panel.keys(panel, input.name)
    known = Panel.known(panel, input.name)
    selected = MapSet.new(rows, &named/1)

    kept =
      Enum.filter(held, fn key ->
        case known[key] do
          %{row: {_row_key, _names} = row} -> MapSet.member?(selected, named(row))
          _not_shown -> true
        end
      end)

    held = for key <- held, %{row: {_, _} = row} <- [known[key]], do: named(row)
    opts = [arguments: arguments] ++ chooser(socket)

    added =
      Enum.reduce_while(Enum.uniq_by(rows, &named/1), [], fn row, added ->
        with false <- named(row) in held,
             {:ok, record} <- Pick.chosen(input.reference, row, opts),
             {:ok, entry} <- entry(input, record, Core.table(socket).caller.time_zone) do
          {:cont, added ++ [entry]}
        else
          true -> {:cont, added}
          :error -> {:halt, :error}
        end
      end)

    case added do
      :error ->
        {:reply, %{ok: false}, unavailable(socket)}

      added ->
        added = Enum.reject(added, fn {text, _known} -> text in kept end)
        model = Core.table(socket).entry.model
        panel = Panel.choose(panel, model, input, kept, added, arguments)
        {:reply, %{ok: true}, socket |> Core.put(picker: nil) |> Core.Panel.put(panel)}
    end
  end

  defp choose_inputs(socket, _panel, _input, _rows, _arguments),
    do: {:reply, %{ok: false}, unavailable(socket)}

  # A row as a grid's hook names it, or as a table names it for its hook
  # (`{row_key, names}`), in one form: the values of the primary key as
  # they are written.
  defp named({row_key, nil}), do: [row_key]

  defp named({_row_key, names}), do: names

  defp named(values) when is_list(values), do: Enum.map(values, &to_string/1)

  defp named(value), do: [to_string(value)]

  # A record that a field of the panel holds, as the panel knows it: the
  # key the field holds for it, as it is written, with what the record is
  # called and what the row of its table is named by, where a picker
  # selects it (nil for a record of a table whose rows cannot be told
  # apart: one without a primary key). None for a record whose key this
  # person may not see.
  def entry(%{reference: reference} = input, record, zone) do
    with {:ok, value} <- Pick.value(reference, record) do
      model = Model.build(reference.destination)
      row_key = Reading.row_key(model, record, 0)

      row =
        case model.primary_key do
          [] -> nil
          _key -> {row_key, Reading.names(model, record, row_key)}
        end

      {:ok,
       {Panel.key_text(input, value, zone), %{label: called(reference, record, zone), row: row}}}
    end
  end

  # The row the browser named is none of a record this person may read
  # through the picker's read action: nothing is chosen, and the picker
  # stays open and says so.
  def unavailable(socket) do
    %{picker: picker} = Core.table(socket).entry
    message = {:text, :record_gone, []}

    socket |> Core.put(picker: %{picker | error: message}) |> Core.say(message)
  end

  # What the picker is headed by: the column, or the field, and what one
  # record of the table to choose from is called.
  defp picker_title(label, reference),
    do: {:text, :choose_for, column: label, name: {:label, Model.name(reference.destination)}}

  # What a record of a destination is called, as far as this person may see
  # it on it: for the field of the panel that holds its key. A value, with
  # its column and the zone it is shown in, which the panel formats.
  defp called(reference, record, zone) do
    model =
      reference.destination
      |> Model.build()
      |> Model.zoned(zone)
      |> Core.in_words()

    case Reading.label(model, record) do
      {column, value} -> {column, value, zone}
      nil -> nil
    end
  end

  # Who is asking, for what is read of a destination to choose from: the
  # reader, and what this table was told about authorization, which its
  # picker's table is told too (`AshDataTable.Pick.reader/2`).
  def chooser(socket), do: picking(Core.table(socket)) ++ Core.reader(socket)

  def picking(table), do: [authorize_given: table.entry.authorize_given]

  # What the read action of a picker is given, from what the picker's hook
  # says its argument line holds: the line's form, as a form sends it. It
  # comes from the browser, and is taken as the form's event is: by the
  # arguments the picker's table has for this person, and as Ash takes it.
  defp picked_with(socket, reference, sent) when is_binary(sent) do
    table = Core.table(socket)
    reader = Pick.reader(reference, chooser(socket))

    model =
      reference.destination
      |> Model.build(choose: reference.choose_action)
      |> Model.for_actor(reader)
      |> Model.zoned(table.caller.time_zone)
      |> Model.defaults(Core.page_assigns(socket))

    form =
      case decoded(sent) do
        %{"arguments" => %{} = form} -> form
        _other -> %{}
      end

    {_state, model, _missing, _refused} =
      Reading.settle(model, State.argue(%State{}, model, form), reader)

    model.read_arguments
  end

  defp picked_with(_socket, _reference, _sent), do: %{}

  defp decoded(sent) do
    Plug.Conn.Query.decode(sent)
  rescue
    Plug.Conn.InvalidQueryError -> %{}
  end
end
