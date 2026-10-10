defmodule AshTable.Edit do
  @moduledoc false
  # Saves one cell: the column's update action, run on the record with the
  # cell's value as its only input. The table adds nothing of its own; what
  # the value becomes, and whether it is accepted, is the action's.
  #
  # The table does not keep the records it shows, so the record is read again
  # first, by primary key and as the person saving (`AshTable.Record`).
  #
  # A reference cell is saved the same way (`refer/5`): its one input is the
  # relationship's foreign key, or the argument of the action that hands a
  # key to the relationship, and its value that of the record the person
  # chose, which is read first, as them (`AshTable.Pick`).

  alias AshTable.Act
  alias AshTable.Errors
  alias AshTable.Format
  alias AshTable.Model
  alias AshTable.Model.Column
  alias AshTable.Pick
  alias AshTable.Query
  alias AshTable.Record
  alias AshTable.Text

  @typedoc """
  What became of a save:

    * `{:ok, record}` - saved, or left as it was because the value is the one
      the record already has. The record is as the action returned it, with
      the table's calculations and aggregates loaded;
    * `{:error, record, message, places}` - not saved. The record is as it
      is stored. `places` says which values of an array the action's errors
      are about, counted from 0; empty for every other column;
    * `{:error, nil, message}` - not saved, and the record can no longer be
      read by this person.
  """
  @type result ::
          {:ok, Ash.Resource.record()}
          | {:error, Ash.Resource.record(), String.t(), [non_neg_integer]}
          | {:error, nil, String.t()}

  @doc """
  Saves `typed`, what a cell's editor holds, as the value of `column` on the
  record with the primary key `key`: the text of the editor, and for an
  array the texts of its values (see `typed?/2`).

  Takes the options of `AshTable.Query.read/3` that say who is asking.
  """
  @spec save(Model.t(), Column.t(), map, String.t() | [String.t()], [Query.option()]) :: result
  def save(%Model{} = model, %Column{editable?: true} = column, key, typed, opts)
      when is_map(key) and (is_binary(typed) or is_list(typed)) do
    opts = Query.reader_opts(opts)

    case Record.fetch(model, key, opts) do
      {:ok, record} -> save_record(model, column, record, typed, opts)
      :error -> {:error, nil, Text.t(:record_gone)}
    end
  end

  @typedoc """
  What became of a choice of a related record:

    * `{:ok, record}` - saved, or left as it was because the chosen record
      is the one the row already has;
    * `:changed` - asked for with `ask?: true`: the chosen record is another
      than the row has, and nothing was saved. For a column whose question
      has yet to be asked;
    * `:unavailable` - the browser named a record that this person may not
      read through the picker's read action, or none at all. Nothing was
      saved;
    * `{:error, record, message, chosen}` - not saved. The record is as it
      is stored, and `chosen` the record that was chosen, nil for none;
    * `{:error, nil, message}` - not saved, and the row's record can no
      longer be read by this person.
  """
  @type referred ::
          {:ok, Ash.Resource.record()}
          | :changed
          | :unavailable
          | {:error, Ash.Resource.record(), String.t(), Ash.Resource.record() | nil}
          | {:error, nil, String.t()}

  @doc """
  Saves the choice of a related record as the value of the reference
  `column` on the record with the primary key `key`: the column's update
  action, with one input. That is the relationship's foreign key, or, where
  the action takes the record through an argument that it hands to the
  relationship, that argument (`reference.argument`).

  `named` is the chosen record as the browser names it: its primary key
  (the key's value, or the list of its values), or nil for no record. It is
  a claim. The record is read by it, as the person, through the read action
  the picker shows its rows through, and what the action is given is that
  record's value of the attribute the input holds
  (`reference.value_attribute`: the relationship's destination attribute,
  or the key the argument names a record by); a key that names nothing they
  may read there saves nothing.

  Takes the options of `AshTable.Query.read/3` that say who is asking,
  `:authorize_given` (see `AshTable.Pick.reader/2`), and `:ask?`, with which
  a choice that would change the row is not saved.
  """
  @spec refer(Model.t(), Column.t(), map, term, keyword) :: referred
  def refer(
        %Model{} = model,
        %Column{editable?: true, kind: :reference, reference: reference} = column,
        key,
        named,
        opts
      )
      when is_map(key) do
    ask? = Keyword.get(opts, :ask?, false)
    # the chosen record is read as the picker's table reads
    chooser = opts
    opts = Query.reader_opts(opts)

    with {:ok, record} <- Record.fetch(model, key, opts),
         {:ok, chosen, value} <- referred(reference, named, chooser) do
      held = Map.get(record, reference.source_attribute)

      cond do
        # a key this person may not see on this record is not theirs to change
        match?(%Ash.ForbiddenField{}, held) ->
          not_referred(model, record, Text.t(:edit_not_allowed), chosen, opts)

        # the record the row already has calls nothing
        (is_nil(chosen) and is_nil(held)) or
            (not is_nil(chosen) and Pick.current?(reference, chosen, held)) ->
          unchanged(model, record, opts)

        ask? ->
          :changed

        true ->
          submit_key(model, column, record, chosen, value, opts)
      end
    else
      :error -> {:error, nil, Text.t(:record_gone)}
      :unavailable -> :unavailable
    end
  end

  # The record that was chosen, with what it makes the foreign key.
  defp referred(_reference, nil, _opts), do: {:ok, nil, nil}

  defp referred(reference, named, opts) do
    with {:ok, chosen} <- Pick.chosen(reference, named, opts),
         {:ok, value} <-
           Pick.value(%{reference | destination_attribute: reference.value_attribute}, chosen) do
      {:ok, chosen, value}
    else
      :error -> :unavailable
    end
  end

  defp not_referred(model, record, message, chosen, opts) do
    case Record.load(model, record, opts) do
      {:ok, record} -> {:error, record, message, chosen}
      :error -> {:error, nil, message}
    end
  end

  defp submit_key(model, column, record, chosen, value, opts) do
    # the foreign key, or the argument that hands the key to the relationship
    key = Atom.to_string(column.reference.argument || column.reference.source_attribute)

    record
    |> AshPhoenix.Form.for_update(
      column.update_action,
      [as: "cell", warn_on_unhandled_errors?: false, forms: [auto?: false]] ++ opts
    )
    |> AshPhoenix.Form.submit(params: %{key => value})
    |> case do
      {:ok, saved} ->
        case Record.load(model, saved, opts) do
          {:ok, saved} -> {:ok, saved}
          :error -> {:error, nil, Text.t(:record_gone)}
        end

      {:error, form} ->
        not_referred(model, record, message(form, column, model), chosen, opts)
    end
  end

  @doc """
  Opens a map cell, or the cell of a union, for editing: the record with
  the primary key `key` as it was read for the person, and the form of the
  column's update action on it, for the side panel. `id` is the id of the
  form.

  `:hidden` when the value, or something in it, is not this person's to
  see, and so not theirs to change; `:error` when the record can no longer
  be read by them.
  """
  @spec open(Model.t(), Column.t(), map, String.t(), keyword) ::
          {:ok, Ash.Resource.record(), AshPhoenix.Form.t()} | :hidden | :error
  def open(%Model{} = model, %Column{editable?: true, editor: editor} = column, key, id, opts)
      when editor in [:group, :groups, :union] and is_map(key) do
    opts = Query.reader_opts(opts)

    with {:ok, record} <- Record.fetch(model, key, opts) do
      if AshTable.Resource.Embedding.hidden?(Map.get(record, column.name)),
        do: :hidden,
        else: {:ok, record, form(record, column, id, opts)}
    end
  end

  @doc """
  Saves what the side panel's form sent for a map cell or a union, as the
  value of `column` on the record with the primary key `key`: the column's
  update action, with the column's attribute as its one input, given as a
  map of its fields (a list of them for an array), and for a union as its
  kind and that kind's value. `input` is the column as the panel's one
  input (`AshTable.Model.input/2`), and `id` the id of the form.

  Returns `{:ok, record}` when it was saved, and when what was sent is what
  the record holds, for which nothing is called; `{:error, form}`, the form
  with the action's errors; and `{:error, nil, message}` when the record
  can no longer be read by this person, or the value is not theirs to
  change.
  """
  @spec put(Model.t(), Column.t(), Model.Input.t(), map, map, String.t(), keyword) ::
          {:ok, Ash.Resource.record()}
          | {:error, AshPhoenix.Form.t()}
          | {:error, nil, String.t()}
  def put(%Model{} = model, %Column{editable?: true} = column, input, key, params, id, opts)
      when is_map(key) and is_map(params) do
    opts = Query.reader_opts(opts)
    name = Atom.to_string(column.name)

    case Record.fetch(model, key, opts) do
      {:ok, record} ->
        value = Map.get(record, column.name)

        cond do
          AshTable.Resource.Embedding.hidden?(value) ->
            {:error, nil, Text.t(:edit_not_allowed)}

          # A value that is the one the cell already holds calls nothing.
          Act.unchanged?(input, params[name], value) ->
            unchanged(model, record, opts)

          true ->
            record
            |> form(column, id, opts)
            |> AshPhoenix.Form.submit(params: Act.values([input], params))
            |> case do
              {:ok, saved} ->
                case Record.load(model, saved, opts) do
                  {:ok, saved} -> {:ok, saved}
                  :error -> {:error, nil, Text.t(:record_gone)}
                end

              {:error, form} ->
                {:error, form}
            end
        end

      :error ->
        {:error, nil, Text.t(:record_gone)}
    end
  end

  defp form(record, column, id, opts),
    do: AshPhoenix.Form.for_update(record, column.update_action, Act.form_opts(id) ++ opts)

  @doc """
  Whether `typed` is what an editor of `column` holds: one text, and for an
  array a list of texts, one per value. Anything else is nothing the table's
  editors send.
  """
  @spec typed?(Column.t(), term) :: boolean
  # a reference cell has no editor that holds a text: see `refer/5`
  def typed?(%Column{kind: :reference}, _typed), do: false
  # nor has a map cell, which is edited in the side panel: see `put/7`
  def typed?(%Column{cell_type: cell_type}, _typed)
      when cell_type in [:map, {:array, :map}, :union, {:array, :union}],
      do: false

  def typed?(%Column{cell_type: {:array, _item}}, typed),
    do: is_list(typed) and Enum.all?(typed, &is_binary/1)

  def typed?(%Column{}, typed), do: is_binary(typed)

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
  defp failed(model, record, message, opts, places \\ []) do
    case Record.load(model, record, opts) do
      {:ok, record} -> {:error, record, message, places}
      :error -> {:error, nil, message}
    end
  end

  defp submit(model, column, record, typed, opts) do
    record
    # what the form cannot put at a field is read from its raw errors below
    |> AshPhoenix.Form.for_update(
      column.update_action,
      [as: "cell", warn_on_unhandled_errors?: false, forms: [auto?: false]] ++ opts
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
        failed(model, record, message(form, column, model), opts, Errors.places(form, column))
    end
  end

  # What the action returned, as the text shown on the cell. The form holds
  # the errors that are about a field, each with its message and variables
  # apart for translation; a refusal and other errors without a field are
  # among its raw errors. See `AshTable.Errors` for what is shown of them.
  #
  # The field of a reference cell is the foreign key its edit writes. Where
  # the edit gives an argument, what the action says of the relationship is
  # about the cell.
  defp message(form, column, model) do
    field =
      case column do
        %Column{kind: :reference, reference: %{argument: nil, source_attribute: key}} -> key
        %Column{name: name} -> name
      end

    case Errors.of_form(form, model, field, Text.t(:edit_not_allowed)) do
      [] -> Text.t(:save_failed)
      messages -> Enum.join(messages, "; ")
    end
  end
end
