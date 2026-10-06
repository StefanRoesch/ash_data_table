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
      %{name: ^cell} -> message
      %{label: label} -> Text.t(:error_on_field, field: label, message: message)
      nil -> message
    end
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
