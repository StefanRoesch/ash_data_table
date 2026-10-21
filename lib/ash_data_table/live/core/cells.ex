defmodule AshDataTable.Live.Core.Cells do
  @moduledoc false
  # Cells: save, clear, reveal, the choice for a reference
  # cell, discard, dismiss, and the panel of a map cell.

  alias AshDataTable.Format
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Notify
  alias AshDataTable.Live.Core.Opener
  alias AshDataTable.Live.Core.Picker
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Model
  alias AshDataTable.Operation
  alias AshDataTable.Text

  # Sent by the hook when a person has changed a cell's value and pressed
  # Enter or left the cell: the row by the key in its DOM id, the column, and
  # the value as it was typed.
  #
  # A column with a question asks it (`Opener.ask/4`): the hook asked it
  # before it sent the save, or the host asks it (controlled mode), what
  # was typed held until it answers, and the hook is told that the cell
  # waits (`held`).
  def on({:save, _key, _name, typed} = intent, socket), do: asked(socket, intent, typed)

  # Sent by the hook when a person uses "Clear" in the editor of a sensitive
  # cell: the row by the key in its DOM id, and the column. Nothing typed
  # says "no value" for such a cell (an empty editor saves nothing), so this
  # is asked for by name, and is the save of a cell in everything else: the
  # column has to be one this person edits and one that can be emptied, the
  # row one of the page, and the record is read again, as the person.
  def on({:clear, _key, _name} = intent, socket), do: asked(socket, intent, "")

  # Sent by the hook when a person asks for the value of a sensitive cell:
  # the row by the key in its DOM id, and the column. The record is read
  # again, as the person, through the table's read action, and the answer
  # is the value as the cell would show it. It goes to the hook alone:
  # nothing of it is rendered, kept or said.
  #
  # Only a cell of a sensitive column this person has, in a row of the page.
  # A value Ash hides from them on this record is not given; whoever may
  # see the field may ask (`sensitive?` is no access rule).
  def on({:reveal, _key, name} = intent, socket) do
    %{model: model} = Core.table(socket).entry

    case Operation.reveal(Core.operation(socket, intent)) do
      {:ok, value} ->
        text = Format.format(Operation.column(model, name), value, model.time_zone)
        {:reply, %{ok: true, value: text}, socket}

      {:error, message} ->
        {:reply, %{ok: false, error: Text.say(message)}, socket}

      _hidden_or_refused ->
        {:reply, %{ok: false}, socket}
    end
  end

  # Sent by the hook when a person opens the editor of a cell that is
  # edited in the side panel (an array, a map cell, a union): the row by the
  # key in its DOM id, and the column. The side panel opens with the
  # column's field, as a form of the column's update action
  # (`AshDataTable.Live.Core.Panel.open/4`); nothing is saved. The record is read
  # first, as the person.
  def on({:edit, key, name}, socket) do
    %{model: model, rows: rows} = Core.table(socket).entry

    with %{editable?: true} = column <- Operation.column(model, name),
         true <- Model.in_panel?(column),
         %{} = row <- rows[key] do
      case Core.Panel.open(socket, :cell, %{key: key, pk: row.pk, column: column}) do
        {:ok, socket} ->
          {:reply, %{ok: true}, socket}

        # not theirs to see on this record, and so not theirs to change
        :refused ->
          {:reply, %{ok: false}, socket}

        {:error, message} ->
          {:reply, %{ok: false, error: Text.say(message)},
           Core.say(socket, {:text, :not_saved, column: column.label, message: message})}
      end
    else
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  # Sent by the hook when a person presses Escape on a cell whose save has
  # failed: the edit is given up, and the cell shows its record's value again.
  def on({:discard, key, name}, socket) do
    with %{} = column <- Operation.column(Core.table(socket).entry.model, name),
         %{cells: %{}} <- Core.table(socket).entry.failed[key] do
      {:noreply,
       socket
       |> Reading.put_failure(key, column.name, nil)
       |> Reading.put_read(key)}
    else
      _ -> {:noreply, socket}
    end
  end

  # The host's Confirm of a column's question (controlled mode): the save
  # or "Clear" runs, as it would have from the hook.
  def on({:confirmed, intent}, socket), do: write(intent, socket)

  # Sent by the hook when a person presses Escape on a button of a row's
  # actions cell that shows the message of an action that failed: the
  # message is given up.
  def on({:dismiss, key}, socket) do
    case Core.table(socket).entry.failed[key] do
      %{action: message} when not is_nil(message) ->
        {:noreply, socket |> Reading.put_action_failure(key, nil) |> Reading.put_read(key)}

      _none ->
        {:noreply, socket}
    end
  end

  # Whether the column of a cell asks before a value is given to it, for
  # one this person edits on a row of the page: then the question is asked
  # (`Opener.ask/4`), and the save runs, or waits for the host's answer
  # with the reply `held` and the `ref` of the request, by which the hook
  # knows the answer (`ash_data_table:answered`). Any other save goes the
  # way it goes, refused where it is no cell of theirs.
  defp asked(socket, intent, value) do
    [_kind, key, name | _rest] = Tuple.to_list(intent)
    %{model: model, rows: rows} = Core.table(socket).entry

    with %{editable?: true, confirm: question} = column when is_binary(question) <-
           Operation.column(model, name),
         %{} = row <- rows[key] do
      about = %{action: column.update_action, key: row.pk, column: column, value: value}

      case Opener.ask(socket, intent, question, about) do
        {:run, socket} -> write(intent, socket)
        {:held, reply, socket} -> {:reply, reply, socket}
      end
    else
      _other -> write(intent, socket)
    end
  end

  @doc """
  The save of a cell, or "Clear", through `AshDataTable.Operation`: what
  the hook sends, or Confirm runs after a question the host asked.
  """
  def write({:save, key, name, typed} = intent, socket) do
    case Operation.save(Core.operation(socket, intent)) do
      # not a cell this table lets anyone edit: nothing a person can send
      # through the table, so nothing is shown for it either
      :refused ->
        {:reply, %{ok: false}, socket}

      result ->
        saved(
          result,
          socket,
          key,
          Operation.column(Core.table(socket).entry.model, name),
          typed
        )
    end
  end

  def write({:clear, key, name} = intent, socket) do
    case Operation.clear(Core.operation(socket, intent)) do
      :refused ->
        {:reply, %{ok: false}, socket}

      result ->
        saved(result, socket, key, Operation.column(Core.table(socket).entry.model, name), "")
    end
  end

  # What became of the save of a cell, as the row and the hook are told it.
  # Either way the row is put back with what is true now: the action's
  # result, or the record as it is and the cell marked with what was typed.
  defp saved(result, socket, key, column, typed) do
    case result do
      {:ok, %Operation.Outcome{record: record} = outcome} ->
        {:reply, %{ok: true},
         socket
         |> Reading.put_failure(key, column.name, nil)
         |> Reading.put_row(key, record)
         |> Notify.told(outcome.event)}

      {:error, %Operation.Failure{record: %_{} = record, message: message}} ->
        # what was typed into a sensitive cell is not kept, and not shown
        typed = if column.sensitive?, do: "", else: typed

        {:reply, %{ok: false},
         socket
         |> Reading.put_failure(key, column.name, {typed, message})
         |> Reading.put_row(key, record)
         |> Core.say({:text, :not_saved, column: column.label, message: message})}

      # The record is gone, or no longer this person's to read: there is
      # nothing to show the row from, so it stays as it is, and the hook
      # marks the cell with the message. A veto says no in the same way.
      {_error_or_halted, message_or_failure} ->
        message = Operation.message(message_or_failure)

        {:reply, %{ok: false, error: Text.say(message)},
         Core.say(socket, {:text, :not_saved, column: column.label, message: message})}
    end
  end

  # The choice of a related record for a reference cell (`Operation.refer/1`).
  # A column with a question is asked first whether the choice changes the
  # row at all, and the hook asks the person; a choice that changes nothing
  # calls nothing. Then, as for any cell, the row is put back with what is
  # true now: the action's result, or the record as it is and the cell
  # marked, with what the chosen record is called in it.
  def referred(result, socket, key, column) do
    case result do
      {:ask, question} ->
        {:reply, %{ask: Text.say(question)}, socket}

      {:error, %Operation.Failure{unchosen: [_ | _]}} ->
        {:reply, %{ok: false}, Picker.unavailable(socket)}

      {:ok, %Operation.Outcome{record: record} = outcome} ->
        {:reply, %{ok: true},
         socket
         |> Core.put(picker: nil)
         |> Reading.put_failure(key, column.name, nil)
         |> Reading.put_row(key, record)
         |> Notify.told(outcome.event)}

      {:error, %Operation.Failure{record: %_{} = record, message: message, chosen: chosen}} ->
        {:reply, %{ok: false},
         socket
         |> Core.put(picker: nil)
         |> Reading.put_failure(
           key,
           column.name,
           {chosen_text(column, chosen, Core.table(socket).caller.time_zone), message}
         )
         |> Reading.put_row(key, record)
         |> Core.say({:text, :not_saved, column: column.label, message: message})}

      {_error_or_halted, message_or_failure} ->
        message = Operation.message(message_or_failure)

        {:reply, %{ok: false, error: Text.say(message)},
         socket
         |> Core.put(picker: nil)
         |> Core.say({:text, :not_saved, column: column.label, message: message})}
    end
  end

  # What a reference cell shows of a record that was chosen for it: its
  # label, as far as this person may see it. Nothing for no record.
  defp chosen_text(_column, nil, _zone), do: ""

  defp chosen_text(%{reference: %{label_field: label}} = column, chosen, zone),
    do: Format.format(column, Map.get(chosen, label), zone)
end
