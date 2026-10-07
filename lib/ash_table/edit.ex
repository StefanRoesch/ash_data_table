defmodule AshTable.Edit do
  @moduledoc false
  # Saves one cell: the column's update action, run on the record with the
  # cell's value as its only input. The table adds nothing of its own; what
  # the value becomes, and whether it is accepted, is the action's.
  #
  # The table does not keep the records it shows, so the record is read again
  # first, by primary key and as the person saving (`AshTable.Record`).

  alias AshTable.Errors
  alias AshTable.Format
  alias AshTable.Model
  alias AshTable.Model.Column
  alias AshTable.Query
  alias AshTable.Record
  alias AshTable.Text

  @typedoc """
  What became of a save:

    * `{:ok, record}` - saved, or left as it was because the value is the one
      the record already has. The record is as the action returned it, with
      the table's calculations and aggregates loaded;
    * `{:error, record, message}` - not saved. The record is as it is stored;
    * `{:error, nil, message}` - not saved, and the record can no longer be
      read by this person.
  """
  @type result ::
          {:ok, Ash.Resource.record()}
          | {:error, Ash.Resource.record() | nil, String.t()}

  @doc """
  Saves `typed`, the text of a cell's editor, as the value of `column` on the
  record with the primary key `key`.

  Takes the options of `AshTable.Query.read/3` that say who is asking.
  """
  @spec save(Model.t(), Column.t(), map, String.t(), [Query.option()]) :: result
  def save(%Model{} = model, %Column{editable?: true} = column, key, typed, opts)
      when is_map(key) and is_binary(typed) do
    opts = Query.reader_opts(opts)

    case Record.fetch(model, key, opts) do
      {:ok, record} -> save_record(model, column, record, typed, opts)
      :error -> {:error, nil, Text.t(:record_gone)}
    end
  end

  defp save_record(model, column, record, typed, opts) do
    case Map.get(record, column.name) do
      # A field this person may not see on this record is not theirs to
      # change either. The action would not stop them: field policies are
      # about reading.
      %Ash.ForbiddenField{} ->
        failed(model, record, Text.t(:edit_not_allowed), opts)

      # A value that is the one the cell already holds calls nothing.
      value ->
        if typed == Format.input(column, value),
          do: unchanged(model, record, opts),
          else: submit(model, column, record, typed, opts)
    end
  end

  defp unchanged(model, record, opts) do
    case Record.load(model, record, opts) do
      {:ok, record} -> {:ok, record}
      :error -> {:error, nil, Text.t(:record_gone)}
    end
  end

  # The row is shown again, with the cell marked: from the record as it is.
  defp failed(model, record, message, opts) do
    case Record.load(model, record, opts) do
      {:ok, record} -> {:error, record, message}
      :error -> {:error, nil, message}
    end
  end

  defp submit(model, column, record, typed, opts) do
    record
    # what the form cannot put at a field is read from its raw errors below
    |> AshPhoenix.Form.for_update(
      column.update_action,
      [as: "cell", warn_on_unhandled_errors?: false] ++ opts
    )
    |> AshPhoenix.Form.submit(params: %{Atom.to_string(column.name) => typed})
    |> case do
      # the row is shown from what the action returns
      {:ok, saved} ->
        case Record.load(model, saved, opts) do
          {:ok, saved} -> {:ok, saved}
          # saved, and no longer this person's to read
          :error -> {:error, nil, Text.t(:record_gone)}
        end

      {:error, form} ->
        failed(model, record, message(form, column, model), opts)
    end
  end

  # What the action returned, as the text shown on the cell. The form holds
  # the errors that are about a field, each with its message and variables
  # apart for translation; a refusal and other errors without a field are
  # among its raw errors. See `AshTable.Errors` for what is shown of them.
  defp message(form, column, model) do
    case Errors.of_form(form, model, column.name, Text.t(:edit_not_allowed)) do
      [] -> Text.t(:save_failed)
      messages -> Enum.join(messages, "; ")
    end
  end
end
