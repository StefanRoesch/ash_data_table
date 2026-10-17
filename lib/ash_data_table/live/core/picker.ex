defmodule AshDataTable.Live.Core.Picker do
  @moduledoc false
  # The picker (stage 3c): open, choose, cancel, and the fields of the
  # action panel given by choosing related records.

  alias AshDataTable.Act
  alias AshDataTable.Ids
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Cells
  alias AshDataTable.Live.Core.Panel
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Live.Core.Requests
  alias AshDataTable.Model
  alias AshDataTable.Operation
  alias AshDataTable.Pick
  alias AshDataTable.Present
  alias AshDataTable.Query
  alias AshDataTable.Record
  alias AshDataTable.State
  alias AshDataTable.Text
  alias AshDataTable.Typed

  require AshDataTable.Live.Current, as: Current

  # Sent by the panel's hook when a person uses the button that takes one
  # of the chosen records out of a field that holds several: the field, and
  # the record's key as the field holds it. The panel is rendered again
  # without it, and the action is told as it is of anything typed. The
  # answer says where focus goes: to what stands where the record stood.
  def on({:panel_unpick, name, key}, socket) when is_map(Current.entry(socket, :panel)) do
    panel = Core.table(socket).entry.panel

    with %{editor: :references} = input <- reference_input(panel, name),
         at when is_integer(at) <- Enum.find_index(panel.refs[name], &(&1 == key)) do
      keys = List.delete_at(panel.refs[name], at)
      field = Ids.field(Core.table(socket).entry.id, [name])

      focus =
        cond do
          at < length(keys) -> Ids.unpick(field, at)
          at > 0 -> Ids.unpick(field, at - 1)
          true -> Ids.choose(field)
        end

      {:reply, %{focus: focus},
       Core.put(socket,
         panel: Panel.errors(hold(panel, input, keys), Core.table(socket).entry.model)
       )}
    else
      _ -> {:reply, %{}, socket}
    end
  end

  def on({:panel_unpick, _name, _key}, socket), do: {:reply, %{}, socket}

  # Sent by the hook when a person opens the editor of a reference cell: the
  # row by the key in its DOM id, and the column. The picker opens; nothing
  # is saved. The record is read first, as the person: the picker opens on
  # the record the cell points at now.
  def on({:pick, key, name}, socket) do
    %{model: model, rows: rows} = Core.table(socket).entry

    with %{editable?: true, kind: :reference, reference: reference} = column <-
           Operation.column(model, name),
         %{} = row <- rows[key] do
      case Record.fetch(model, row.pk, Query.reader_opts(Core.reader(socket))) do
        {:ok, record} ->
          case Map.get(record, reference.source_attribute) do
            # not theirs to see on this record, and so not theirs to change
            %Ash.ForbiddenField{} ->
              {:reply, %{ok: false}, socket}

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

              {:reply, %{ok: true}, Core.put(socket, picker: picker)}
          end

        :error ->
          message = {:text, :record_gone, []}

          {:reply, %{ok: false, error: Text.say(message)},
           Core.say(socket, {:text, :not_saved, column: column.label, message: message})}
      end
    else
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  # Sent by the button of a field of the action panel that holds the key of
  # a related record: the picker opens on top of the panel, on the record
  # the field holds now.
  def on({:pick_input, name}, socket) when is_map(Current.entry(socket, :panel)) do
    panel = Core.table(socket).entry.panel

    case reference_input(panel, name) do
      nil ->
        {:noreply, socket}

      # several records: the picker opens with the rows selected of the
      # records the field holds now, on whatever page they are
      %{editor: :references} = input ->
        known = Map.get(panel.chosen, input.name, %{})

        picker = %{
          for: {:input, input.name},
          name: input.name,
          reference: input.reference,
          title: picker_title(input.label, input.reference),
          several?: true,
          current: nil,
          chosen: for(key <- panel.refs[name], %{row: {_, _} = row} <- [known[key]], do: row),
          allow_none?: false,
          question: nil,
          error: nil
        }

        {:noreply, Core.put(socket, picker: picker)}

      input ->
        picker = %{
          for: {:input, input.name},
          name: input.name,
          reference: input.reference,
          title: picker_title(input.label, input.reference),
          several?: false,
          current: Reading.blank_as_nil(held_key(panel, input)),
          chosen: [],
          allow_none?: not input.required?,
          question: nil,
          error: nil
        }

        {:noreply, Core.put(socket, picker: picker)}
    end
  end

  def on({:pick_input, _name}, socket), do: {:noreply, socket}

  # Sent by the picker's hook when the person has chosen: the row they
  # selected, as the grid's hook names it (its primary key), or nil for no
  # record; and `confirmed`, once they have answered the column's question.
  # Where several records are chosen, `rows` in place of `row`: every row
  # that is selected.
  #
  # The row is a claim. Which cell or field it is chosen for is the
  # server's to say, from what the picker was opened for.
  def on({:picked, picked}, socket) when is_map(Current.entry(socket, :picker)),
    do: picked(socket, picked, :hook)

  def on({:picked, _picked}, socket), do: {:reply, %{ok: false}, socket}

  # Sent by the picker's hook for Cancel and Escape.
  def on(:picker_cancel, socket),
    do: {:noreply, Core.put(socket, picker: nil)}

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
        case panel && reference_input(panel, Atom.to_string(name)) do
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
  question was answered. In controlled mode the host asks it: the choice
  waits, the picker closes and the hook is told the cell waits (`held`).
  Where the host draws the picker and the table asks its own questions,
  the host has shown the question with its chooser (`question` of its
  request), and its choice is the answer.
  """
  def refer(socket, key, name, named, arguments, confirmed?, by \\ :hook) do
    %{model: model, rows: rows} = Core.table(socket).entry
    column = Enum.find(model.columns, &(&1.name == name))
    intent = {:refer, key, name, named, confirmed?, arguments}

    case Operation.refer(Core.operation(socket, intent)) do
      :refused ->
        {:reply, %{ok: false}, Core.put(socket, picker: nil)}

      {:ask, question} ->
        cond do
          Requests.controlled?(socket, :confirm) ->
            socket
            |> Core.put(picker: nil)
            |> Requests.ask_cell(
              {:refer, key, name, named, arguments},
              column,
              rows[key].pk,
              named
            )
            |> Cells.held()

          by == :host ->
            refer(socket, key, name, named, arguments, true, by)

          true ->
            Cells.referred({:ask, question}, socket, key, column)
        end

      result ->
        Cells.referred(result, socket, key, column)
    end
  end

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

      {text, known} ->
        panel = %{
          panel
          | chosen: Map.put(panel.chosen, input.name, %{text => known}),
            # the key is looked up once more when the action runs: through
            # the picker's read action as it was given when it was chosen
            picked_with: Map.put(panel.picked_with, input.name, {text, arguments})
        }

        keys = if text == "", do: [], else: [text]

        {:reply, %{ok: true},
         Core.put(socket,
           picker: nil,
           panel: Panel.errors(hold(panel, input, keys), Core.table(socket).entry.model)
         )}
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
    name = Atom.to_string(input.name)
    known = Map.get(panel.chosen, input.name, %{})
    selected = MapSet.new(rows, &named/1)

    kept =
      Enum.filter(panel.refs[name], fn key ->
        case known[key] do
          %{row: {_row_key, _names} = row} -> MapSet.member?(selected, named(row))
          _not_shown -> true
        end
      end)

    held = for key <- panel.refs[name], %{row: {_, _} = row} <- [known[key]], do: named(row)
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
        with_arguments = Map.new(added, fn {text, _known} -> {text, arguments} end)

        picked_with =
          Map.update(panel.picked_with, input.name, with_arguments, fn
            %{} = before -> Map.merge(before, with_arguments)
            _other -> with_arguments
          end)

        panel = %{
          panel
          | chosen: Map.put(panel.chosen, input.name, Map.merge(known, Map.new(added))),
            picked_with: picked_with
        }

        keys = kept ++ Enum.map(added, &elem(&1, 0))

        {:reply, %{ok: true},
         Core.put(socket,
           picker: nil,
           panel: Panel.errors(hold(panel, input, keys), Core.table(socket).entry.model)
         )}
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

      {:ok, {key_text(input, value, zone), %{label: called(reference, record, zone), row: row}}}
    end
  end

  # A key as a field of the panel writes it: an attribute's as the editor
  # of its type does, an argument's as a key is written.
  def key_text(%{kind: :attribute} = input, value, zone), do: Typed.of(input, value, zone)

  def key_text(_argument, value, _zone), do: to_string(Pick.written(value))

  # Puts keys into a field of the panel that is given by choosing: as if
  # its form had sent them. The field is one the person has been in.
  defp hold(panel, input, keys) do
    name = Atom.to_string(input.name)

    sent =
      case input.editor do
        :references -> ["" | keys]
        :reference -> List.first(keys, "")
      end

    typed = Map.put(panel.typed, name, sent)
    picked = MapSet.put(panel.picked, name)

    %{
      panel
      | form: Act.validate(panel.form, panel.inputs, typed, Panel.given(panel), panel.time_zone),
        typed: typed,
        refs:
          if(is_map_key(panel.refs, name), do: Map.put(panel.refs, name, keys), else: panel.refs),
        picked: picked,
        used: MapSet.union(panel.used, picked)
    }
  end

  # The key a field of the panel holds that is given by choosing one record:
  # as it is written, "" for none. An argument's is the panel's to keep;
  # an attribute's is the form's.
  defp held_key(panel, %{kind: :argument} = input),
    do: List.first(panel.refs[Atom.to_string(input.name)] || [], "")

  defp held_key(panel, input) do
    default? = panel.kind == :create
    Present.field_value(input, AshPhoenix.Form.value(panel.form, input.name), default?, panel)
  end

  # The row the browser named is none of a record this person may read
  # through the picker's read action: nothing is chosen, and the picker
  # stays open and says so.
  def unavailable(socket) do
    %{picker: picker} = Core.table(socket).entry
    message = {:text, :record_gone, []}

    socket |> Core.put(picker: %{picker | error: message}) |> Core.say(message)
  end

  # The input of a panel that is given by choosing a related record, by its
  # name as text.
  defp reference_input(panel, name) do
    Enum.find(
      panel.inputs,
      &(&1.editor in [:reference, :references] and Atom.to_string(&1.name) == name)
    )
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
