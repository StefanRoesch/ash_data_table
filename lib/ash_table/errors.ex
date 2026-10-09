defmodule AshTable.Errors do
  @moduledoc false
  # What an error of an action says to a person. The table shows what the
  # action returned, on two conditions:
  #
  #   * Only an error the action returned on purpose is shown: one of Ash's
  #     "invalid" class, such as a validation that failed or an argument that
  #     is not valid. An error of the "unknown" or "framework" class is
  #     somebody's mistake or a failure underneath (a database error, a crash
  #     in a change), and its text is not for the person at the table.
  #
  #   * A field is named only when the person has a column for it. An error
  #     about a field whose column was left out for them, or which is no
  #     column of the table at all, is shown without the field's name.
  #
  # The messages themselves go through `AshTable.Text.error/1`, where the host
  # translates them; the words around them are the table's own.

  alias AshTable.Model
  alias AshTable.Text

  @doc """
  The text of a message about `field`, as it is shown on a cell of the column
  `cell` (nil when it is not shown on a cell). `model` is the table as the
  person meets it.
  """
  @spec at_field(Model.t(), atom | nil, term, {String.t(), keyword}) :: String.t()
  def at_field(%Model{} = model, cell, field, {_message, _vars} = error) do
    message = Text.error(error)

    case Enum.find(model.columns, &(&1.name == field)) do
      # one value of an array is named with its column wherever it is shown
      %{name: name, label: label} = column ->
        if name == cell or place(column, error),
          do: at_value(column, error),
          else: Text.t(:error_on_field, field: label, message: message)

      nil ->
        message
    end
  end

  @doc """
  The text of a message about a field that is an array, as it is shown at
  that field: `field` is its column, or its input in the action panel.

  An error about one value of an array says which: the value is called what
  its control is called in the array's editor, by the field's label and the
  value's place, counted from 1 ("Tags 2: is invalid"). Not in a multiple
  choice, whose boxes have no places. An error about the array as a whole,
  or about any other field, is its message.
  """
  @spec at_value(map, {String.t(), keyword | map}) :: String.t()
  def at_value(%{label: label} = field, {_message, _vars} = error) do
    case place(field, error) do
      nil ->
        Text.error(error)

      place ->
        Text.t(:error_on_field,
          field: Text.t(:value_position, column: label, position: place + 1),
          message: Text.error(error)
        )
    end
  end

  @doc """
  The place, counted from 0, of the value of an array that an error is
  about, when `field` (a column or an input) is an array that is edited
  value by value; nil for every other error.
  """
  @spec place(map, {String.t(), keyword | map}) :: non_neg_integer | nil
  def place(%{cell_type: {:array, item}}, {_message, vars}) when item != :enum do
    case Enum.find(vars, &match?({:index, _index}, &1)) do
      {:index, index} when is_integer(index) and index >= 0 -> index
      _none -> nil
    end
  end

  def place(_field, _error), do: nil

  @doc """
  The places of the values of the array `field` (a column or an input) that
  the errors of a form are about, counted from 0.
  """
  @spec places(AshPhoenix.Form.t(), map) :: [non_neg_integer]
  def places(form, %{name: name} = field) do
    Enum.uniq(for {^name, error} <- at_fields(form), place = place(field, error), do: place)
  end

  @doc """
  The text of an error that is not about a field, or nil when it has none
  that a person should read.
  """
  @spec without_field(term) :: String.t() | nil
  def without_field(%{class: :invalid, message: message} = error) when is_binary(message),
    do: Text.error({message, Map.get(error, :vars) || []})

  def without_field(_error), do: nil

  @doc "Whether an error is about a field, and so reaches a person as one of a form's errors."
  @spec about_field?(term) :: boolean
  def about_field?(%{field: field}) when not is_nil(field), do: true
  def about_field?(%{fields: [_ | _]}), do: true
  def about_field?(_error), do: false

  @doc """
  What the errors of a form say to a person, each message once: those about
  a field as they are shown on a cell of the column `cell` (nil when they
  are not shown on a cell), then those about none. `refusal` is what a
  refusal reads as: Ash's own text for one is "forbidden", or the breakdown
  of the policies, neither of which is for the person at the table.
  """
  @spec of_form(AshPhoenix.Form.t(), Model.t(), atom | nil, String.t()) :: [String.t()]
  def of_form(form, %Model{} = model, cell, refusal) do
    at_fields =
      for {field, {message, vars}} <- at_fields(form),
          do: at_field(model, cell, field, {message, vars})

    Enum.uniq(at_fields ++ without_fields(form, refusal))
  end

  @doc """
  The errors of a form that are about a field, each with its message and
  variables apart: those the form has put at a field, and those about one
  value of a field that is an array.

  An error about one value has the value's place among its variables here,
  as `index`, counted from 0. Ash says the place in the error itself: among
  its variables, and for some errors also as its path (`path: [1]`). A form
  drops the variable from the errors it puts at a field, so those are read
  from the form's raw errors too, and take the place of the form's own.

  An error that has its place as its path the form puts nowhere: it takes a
  path for the way to a form nested in it, and an array of plain values has
  none. It is read from the raw errors as well, through the protocol the
  form itself reads an error with. An error with any other path is about a
  field of something nested in the record, which only has the name in
  common with a field of the record, and is left where the form leaves it.
  """
  @spec at_fields(AshPhoenix.Form.t()) :: [{atom, {String.t(), keyword}}]
  def at_fields(form) do
    placed =
      for {field, {message, vars}} <- AshPhoenix.Form.errors(form, format: :raw),
          is_binary(message),
          do: {field, {message, vars}}

    at_values =
      for %{class: :invalid} = error <- AshPhoenix.Form.raw_errors(form),
          index = index(error),
          about_field?(error),
          AshPhoenix.FormData.Error.impl_for(error),
          {field, message, vars} <- List.wrap(AshPhoenix.FormData.Error.to_form_error(error)),
          is_binary(message),
          do: {field, {message, Keyword.put(Keyword.new(vars), :index, index)}}

    # what the form has placed of these, without the place
    without_place =
      for {field, {message, vars}} <- at_values,
          do: {field, {message, Keyword.delete(vars, :index)}}

    Enum.reject(placed, fn {field, {message, vars}} ->
      {field, {message, Keyword.delete(Keyword.new(vars), :index)}} in without_place
    end) ++ at_values
  end

  # The place of the value of an array that an error is about: its path,
  # when that is one place, else what it says among its variables. An error
  # with any other path is about something nested in the record.
  defp index(%{path: [index]}) when is_integer(index), do: index

  defp index(%{path: [], vars: vars}) when is_list(vars) or is_map(vars) do
    case Enum.find(vars, &match?({:index, _index}, &1)) do
      {:index, index} when is_integer(index) -> index
      _none -> nil
    end
  end

  defp index(_error), do: nil

  @doc "The texts of a form's errors that are about no field, a refusal among them as `refusal`."
  @spec without_fields(AshPhoenix.Form.t(), String.t()) :: [String.t()]
  def without_fields(form, refusal) do
    for error <- AshPhoenix.Form.raw_errors(form),
        not about_field?(error),
        message = if(match?(%{class: :forbidden}, error), do: refusal, else: without_field(error)),
        do: message
  end

  @doc """
  What a failed read says to a person: the messages of the errors the read
  action returned on purpose, each one once. Empty when there is none, which
  is when the table says no more than that the records could not be loaded.
  """
  @spec of_read(term, Model.t()) :: [String.t()]
  def of_read(error, %Model{} = model) do
    case Ash.Error.to_error_class(error) do
      %Ash.Error.Invalid{errors: errors} ->
        errors |> Enum.flat_map(&texts(&1, model)) |> Enum.uniq()

      _other ->
        []
    end
  end

  # As `AshPhoenix.Form` reads an error for a form: through the protocol
  # that says which field an error is about, with its message and variables.
  defp texts(%{class: :invalid} = error, model) do
    cond do
      not about_field?(error) ->
        List.wrap(without_field(error))

      AshPhoenix.FormData.Error.impl_for(error) ->
        for {field, message, vars} <- List.wrap(AshPhoenix.FormData.Error.to_form_error(error)),
            is_binary(message),
            do: at_field(model, nil, field, {message, vars})

      true ->
        []
    end
  end

  defp texts(_error, _model), do: []
end
