defmodule AshDataTable.Live.Core.Cells do
  @moduledoc false
  # Cells: save, clear, reveal, the choice for a reference
  # cell, discard, dismiss, and the panel of a map cell.

  alias AshDataTable.Format
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Opener
  alias AshDataTable.Live.Core.Picker
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Model
  alias AshDataTable.Operation
  alias AshDataTable.Table
  alias AshDataTable.Text

  # Sent by the hook when a person asks for the value of a sensitive cell:
  # the row by the key in its DOM id, and the column. The record is read
  # again, as the person, through the table's read action, and the answer
  # is the value as the cell would show it. It goes to the hook alone:
  # nothing of it is rendered, kept or said.
  #
  # Only a cell of a sensitive column this person has, in a row of the page.
  # A value Ash hides from them on this record is not given; whoever may
  # see the field may ask (`sensitive?` is no access rule).
  def step({:reveal, _key, name} = intent, table) do
    %{model: model} = table.entry

    case Operation.reveal(Core.operation(table, intent)) do
      {:ok, value} ->
        text = Format.format(Operation.column(model, name), value, model.time_zone)
        {table, %{ok: true, value: text}}

      {:error, message} ->
        {table, %{ok: false, error: Text.say(message)}}

      _hidden_or_refused ->
        {table, %{ok: false}}
    end
  end

  # Sent by the hook when a person has changed a cell's value and pressed
  # Enter or left the cell: the row by the key in its DOM id, the column, and
  # the value as it was typed.
  #
  # A column with a question asks it (`Opener.ask/4`): the hook asked it
  # before it sent the save, or the host asks it (controlled mode), what
  # was typed held until it answers, and the hook is told that the cell
  # waits (`held`).
  def step({:save, _key, _name, typed} = intent, table), do: asked(table, intent, typed)

  # Sent by the hook when a person uses "Clear" in the editor of a sensitive
  # cell: the row by the key in its DOM id, and the column. Nothing typed
  # says "no value" for such a cell (an empty editor saves nothing), so this
  # is asked for by name, and is the save of a cell in everything else: the
  # column has to be one this person edits and one that can be emptied, the
  # row one of the page, and the record is read again, as the person.
  def step({:clear, _key, _name} = intent, table), do: asked(table, intent, "")

  # Sent by the hook when a person opens the editor of a cell that is
  # edited in the side panel (an array, a map cell, a union): the row by the
  # key in its DOM id, and the column. The side panel opens with the
  # column's field, as a form of the column's update action
  # (`AshDataTable.Live.Core.Panel.open/4`); nothing is saved. The record is read
  # first, as the person.
  def step({:edit, key, name}, table) do
    %{model: model, rows: rows} = table.entry

    with %{editable?: true} = column <- Operation.column(model, name),
         true <- Model.in_panel?(column),
         %{} = row <- rows[key] do
      case Core.Panel.open(table, :cell, %{key: key, pk: row.pk, column: column}) do
        {:ok, table} ->
          {table, %{ok: true}}

        # not theirs to see on this record, and so not theirs to change
        :refused ->
          {table, %{ok: false}}

        {:error, message} ->
          {Core.say(table, {:text, :not_saved, column: column.label, message: message}),
           %{ok: false, error: Text.say(message)}}
      end
    else
      _ -> {table, %{ok: false}}
    end
  end

  # Sent by the hook when a person presses Escape on a cell whose save has
  # failed: the edit is given up, and the cell shows its record's value again.
  def step({:discard, key, name}, table) do
    with %{} = column <- Operation.column(table.entry.model, name),
         %{cells: %{}} <- table.entry.failed[key] do
      {table |> Reading.put_failure(key, column.name, nil) |> Reading.put_read(key), nil}
    else
      _ -> {table, nil}
    end
  end

  # The host's Confirm of a column's question (controlled mode): the save
  # or "Clear" runs, as it would have from the hook.
  def step({:confirmed, intent}, table), do: write(intent, table)

  # Sent by the hook when a person presses Escape on a button of a row's
  # actions cell that shows the message of an action that failed: the
  # message is given up.
  def step({:dismiss, key}, table) do
    case table.entry.failed[key] do
      %{action: message} when not is_nil(message) ->
        {table |> Reading.put_action_failure(key, nil) |> Reading.put_read(key), nil}

      _none ->
        {table, nil}
    end
  end

  # Whether the column of a cell asks before a value is given to it, for
  # one this person edits on a row of the page: then the question is asked
  # (`Opener.ask/4`), and the save runs, or waits for the host's answer
  # with the reply `held` and the `ref` of the request, by which the hook
  # knows the answer (`ash_data_table:answered`). Any other save goes the
  # way it goes, refused where it is no cell of theirs.
  defp asked(table, intent, value) do
    [_kind, key, name | _rest] = Tuple.to_list(intent)
    %{model: model, rows: rows} = table.entry

    with %{editable?: true, confirm: question} = column when is_binary(question) <-
           Operation.column(model, name),
         %{} = row <- rows[key] do
      about = %{action: column.update_action, key: row.pk, column: column, value: value}

      case Opener.ask(table, intent, question, about) do
        {:run, table} -> write(intent, table)
        {:held, reply, table} -> {table, reply}
      end
    else
      _other -> write(intent, table)
    end
  end

  # The save of a cell, or "Clear", through `AshDataTable.Operation`: what
  # the hook sends, or Confirm runs after a question the host asked.
  defp write({:save, key, name, typed} = intent, table) do
    case Operation.save(Core.operation(table, intent)) do
      # not a cell this table lets anyone edit: nothing a person can send
      # through the table, so nothing is shown for it either
      :refused -> {table, %{ok: false}}
      result -> saved(result, table, key, Operation.column(table.entry.model, name), typed)
    end
  end

  defp write({:clear, key, name} = intent, table) do
    case Operation.clear(Core.operation(table, intent)) do
      :refused -> {table, %{ok: false}}
      result -> saved(result, table, key, Operation.column(table.entry.model, name), "")
    end
  end

  # What became of the save of a cell, as the row and the hook are told it.
  # Either way the row is put back with what is true now: the action's
  # result, or the record as it is and the cell marked with what was typed.
  defp saved(result, table, key, column, typed) do
    case result do
      {:ok, %Operation.Outcome{record: record} = outcome} ->
        {table
         |> Reading.put_failure(key, column.name, nil)
         |> Reading.put_row(key, record)
         |> Core.notify(outcome.event), %{ok: true}}

      {:error, %Operation.Failure{record: %_{} = record, message: message}} ->
        # what was typed into a sensitive cell is not kept, and not shown
        typed = if column.sensitive?, do: "", else: typed

        {table
         |> Reading.put_failure(key, column.name, {typed, message})
         |> Reading.put_row(key, record)
         |> Core.say({:text, :not_saved, column: column.label, message: message}), %{ok: false}}

      # The record is gone, or no longer this person's to read: there is
      # nothing to show the row from, so it stays as it is, and the hook
      # marks the cell with the message. A veto says no in the same way.
      {_error_or_halted, message_or_failure} ->
        message = Operation.message(message_or_failure)

        {Core.say(table, {:text, :not_saved, column: column.label, message: message}),
         %{ok: false, error: Text.say(message)}}
    end
  end

  # The choice of a related record for a reference cell (`Operation.refer/1`).
  # A column with a question is asked first whether the choice changes the
  # row at all, and the hook asks the person; a choice that changes nothing
  # calls nothing. Then, as for any cell, the row is put back with what is
  # true now: the action's result, or the record as it is and the cell
  # marked, with what the chosen record is called in it.
  def referred(result, %Table{} = table, key, column) do
    case result do
      {:ask, question} ->
        {table, %{ask: Text.say(question)}}

      {:error, %Operation.Failure{unchosen: [_ | _]}} ->
        {Picker.unavailable(table), %{ok: false}}

      {:ok, %Operation.Outcome{record: record} = outcome} ->
        {table
         |> Table.put(picker: nil)
         |> Reading.put_failure(key, column.name, nil)
         |> Reading.put_row(key, record)
         |> Core.notify(outcome.event), %{ok: true}}

      {:error, %Operation.Failure{record: %_{} = record, message: message, chosen: chosen}} ->
        {table
         |> Table.put(picker: nil)
         |> Reading.put_failure(
           key,
           column.name,
           {chosen_text(column, chosen, table.caller.time_zone), message}
         )
         |> Reading.put_row(key, record)
         |> Core.say({:text, :not_saved, column: column.label, message: message}), %{ok: false}}

      {_error_or_halted, message_or_failure} ->
        message = Operation.message(message_or_failure)

        {table
         |> Table.put(picker: nil)
         |> Core.say({:text, :not_saved, column: column.label, message: message}),
         %{ok: false, error: Text.say(message)}}
    end
  end

  # What a reference cell shows of a record that was chosen for it: its
  # label, as far as this person may see it. Nothing for no record.
  defp chosen_text(_column, nil, _zone), do: ""

  defp chosen_text(%{reference: %{label_field: label}} = column, chosen, zone),
    do: Format.format(column, Map.get(chosen, label), zone)
end
