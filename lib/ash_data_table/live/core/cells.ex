defmodule AshDataTable.Live.Core.Cells do
  @moduledoc false
  # Cells (stage 3c): save, clear, reveal, the choice for a reference
  # cell, discard, dismiss, and the panel of a map cell.

  alias AshDataTable.Edit
  alias AshDataTable.Format
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Notify
  alias AshDataTable.Live.Core.Panel
  alias AshDataTable.Live.Core.Picker
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Model
  alias AshDataTable.Operation
  alias AshDataTable.Text

  # Sent by the hook when a person has changed a cell's value and pressed
  # Enter or left the cell: the row by the key in its DOM id, the column, and
  # the value as it was typed. For an array that is a list, of its values as
  # they were typed.
  def on({:save, key, name, typed} = intent, socket) do
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

  # Sent by the hook when a person uses "Clear" in the editor of a sensitive
  # cell: the row by the key in its DOM id, and the column. Nothing typed
  # says "no value" for such a cell (an empty editor saves nothing), so this
  # is asked for by name, and is the save of a cell in everything else: the
  # column has to be one this person edits and one that can be emptied, the
  # row one of the page, and the record is read again, as the person.
  def on({:clear, key, name} = intent, socket) do
    case Operation.clear(Core.operation(socket, intent)) do
      :refused ->
        {:reply, %{ok: false}, socket}

      result ->
        saved(result, socket, key, Operation.column(Core.table(socket).entry.model, name), "")
    end
  end

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

  # Sent by the hook when a person opens the editor of a map cell: the row
  # by the key in its DOM id, and the column. The side panel opens with the
  # value's fields; nothing is saved. The record is read first, as the
  # person.
  def on({:edit, key, name}, socket) do
    %{id: id, model: model, rows: rows} = Core.table(socket).entry

    with %{editable?: true} = column <- Operation.column(model, name),
         true <- Model.group?(column),
         %{} = row <- rows[key] do
      case Edit.open(model, column, row.pk, "#{id}-panel", Core.reader(socket)) do
        {:ok, record, form} ->
          title =
            case Reading.title_of(model, record) do
              nil -> column.label
              name -> {:text, :action_on, action: column.label, record: name}
            end

          panel =
            Panel.panel(socket, &Map.get(record, &1.name), %{
              kind: :cell,
              # the column's update action, as the panel knows an action
              action: %Model.Action{
                name: column.update_action,
                type: :update,
                label: column.label,
                confirm: column.confirm
              },
              key: key,
              column: column.name,
              form: form,
              inputs: [Model.input(model, column)],
              title: title,
              submit: {:text, :save, []}
            })

          {:reply, %{ok: true}, Core.put(socket, panel: panel)}

        # not theirs to see on this record, and so not theirs to change
        :hidden ->
          {:reply, %{ok: false}, socket}

        :error ->
          message = {:text, :record_gone, []}

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
         %{record: record, cells: %{}} <- Core.table(socket).entry.failed[key] do
      {:noreply,
       socket
       |> Reading.put_failure(key, record, column.name, nil)
       |> Reading.put_row(key, record)}
    else
      _ -> {:noreply, socket}
    end
  end

  # Sent by the hook when a person presses Escape on a row's actions cell
  # that shows the message of an action that failed: the message is given up.
  def on({:dismiss, key}, socket) do
    case Core.table(socket).entry.failed[key] do
      %{record: record, action: message} when not is_nil(message) ->
        {:noreply,
         socket |> Reading.put_action_failure(key, record, nil) |> Reading.put_row(key, record)}

      _none ->
        {:noreply, socket}
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
         |> Reading.put_failure(key, record, column.name, nil)
         |> Reading.put_row(key, record)
         |> Notify.told(outcome.event)}

      {:error, %Operation.Failure{record: %_{} = record, message: message, places: places}} ->
        # what was typed into a sensitive cell is not kept, and not shown
        typed = if column.sensitive?, do: "", else: typed

        {:reply, %{ok: false},
         socket
         |> Reading.put_failure(key, record, column.name, {typed, message, places})
         |> Reading.put_row(key, record)
         |> Core.say({:text, :not_saved, column: column.label, message: message})}

      # The record is gone, or no longer this person's to read: there is
      # nothing to show the row from, so it stays as it is, and the hook
      # marks the cell with the message. A veto says no in the same way.
      {_error_or_halted, message_or_failure} ->
        message = message(message_or_failure)

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
         |> Reading.put_failure(key, record, column.name, nil)
         |> Reading.put_row(key, record)
         |> Notify.told(outcome.event)}

      {:error, %Operation.Failure{record: %_{} = record, message: message, chosen: chosen}} ->
        {:reply, %{ok: false},
         socket
         |> Core.put(picker: nil)
         |> Reading.put_failure(
           key,
           record,
           column.name,
           {chosen_text(column, chosen, Core.table(socket).caller.time_zone), message, []}
         )
         |> Reading.put_row(key, record)
         |> Core.say({:text, :not_saved, column: column.label, message: message})}

      {_error_or_halted, message_or_failure} ->
        message = message(message_or_failure)

        {:reply, %{ok: false, error: Text.say(message)},
         socket
         |> Core.put(picker: nil)
         |> Core.say({:text, :not_saved, column: column.label, message: message})}
    end
  end

  # The message of a failure, or of a veto.
  def message(%Operation.Failure{message: message}), do: message

  def message(message), do: message

  # What a reference cell shows of a record that was chosen for it: its
  # label, as far as this person may see it. Nothing for no record.
  defp chosen_text(_column, nil, _zone), do: ""

  defp chosen_text(%{reference: %{label_field: label}} = column, chosen, zone),
    do: Format.format(column, Map.get(chosen, label), zone)
end
