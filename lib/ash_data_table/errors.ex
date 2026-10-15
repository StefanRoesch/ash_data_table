defmodule AshDataTable.Errors do
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
  # What is said is a message term (`t:message/0`), never words: an action's
  # message with its variables (`{:ash, message, vars}`), which the host
  # translates, inside the table's own words around it (`{:text, key,
  # bindings}`) and the resource's names of fields (`{:label, name}`). The
  # drawing side makes the words, in the LiveView's process.

  alias AshDataTable.Model

  @typedoc """
  What the data layer says to a person, as a term: a text of the table's own
  by key with its bindings (a plural one has `count` among them), an
  action's message with its variables, the resource's wording, or several
  messages said as one, with a separator between them. A binding may
  itself be a message.
  """
  @type message ::
          {:text, atom, keyword}
          | {:ash, String.t(), keyword | map}
          | {:label, String.t()}
          | {:join, String.t(), [message]}

  @doc "Several messages said as one, each after the one before: one is itself."
  @spec joined([message, ...]) :: message
  def joined([message]), do: message
  def joined(messages), do: {:join, "; ", messages}

  @doc """
  Messages each once: one that says what another says is left out, as a
  text that is shown twice would be. Two say the same where they are of the
  same kind and key, or the same action message, with the same values in
  its placeholders: a variable the message does not name (Ash adds `index`
  and `field`) changes nothing, and a name is said as its text (`:medium`
  as `"medium"`).
  """
  @spec uniq([message]) :: [message]
  def uniq(messages), do: Enum.uniq_by(messages, &said/1)

  @doc "Whether two messages say the same (`uniq/1`)."
  @spec same?(message, message) :: boolean
  def same?(message, other), do: said(message) == said(other)

  defp said({:ash, message, vars}) do
    named = for [_, name] <- Regex.scan(~r/%\{(\w+)\}/, message), into: MapSet.new(), do: name

    vars =
      for {name, value} <- List.wrap(if(is_map(vars), do: Map.to_list(vars), else: vars)),
          (is_atom(name) or is_binary(name)) and
            (to_string(name) in named or to_string(name) == "count"),
          do: {to_string(name), said_value(value)}

    {:ash, message, Enum.sort(vars)}
  end

  defp said({:text, key, bindings}),
    do: {:text, key, Enum.sort(for {name, value} <- bindings, do: {name, said(value)})}

  defp said({:join, separator, messages}), do: {:join, separator, Enum.map(messages, &said/1)}
  defp said({:label, _text} = label), do: label
  defp said(value), do: said_value(value)

  defp said_value(value) when is_binary(value) or is_number(value), do: value
  defp said_value(value) when is_atom(value), do: to_string(value)
  defp said_value(value), do: inspect(value)

  @doc "An action's message with its variables, as a message."
  @spec ash({String.t(), keyword | map}) :: message
  def ash({message, vars}) when is_binary(message), do: {:ash, message, vars}

  @doc """
  The text of a message about `field`, as it is shown on a cell of the column
  `cell` (nil when it is not shown on a cell). `model` is the table as the
  person meets it.
  """
  @spec at_field(Model.t(), atom | nil, term, {String.t(), keyword}) :: message
  def at_field(%Model{} = model, cell, field, {_message, _vars} = error) do
    message = ash(error)

    case Enum.find(model.columns, &(&1.name == field)) do
      # one value of an array is named with its column wherever it is shown
      %{name: name, label: label} = column ->
        if name == cell or place(column, error),
          do: at_value(column, error),
          else: {:text, :error_on_field, field: label, message: message}

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
  @spec at_value(map, {String.t(), keyword | map}) :: message
  def at_value(%{label: label} = field, {_message, _vars} = error) do
    case place(field, error) do
      nil ->
        ash(error)

      place ->
        {:text, :error_on_field,
         field: {:text, :value_position, column: label, position: place + 1}, message: ash(error)}
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
  @spec without_field(term) :: message | nil
  def without_field(%{class: :invalid, message: message} = error) when is_binary(message),
    do: {:ash, message, Map.get(error, :vars) || []}

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
  @spec of_form(AshPhoenix.Form.t(), Model.t(), atom | nil, message) :: [message]
  def of_form(form, %Model{} = model, cell, refusal) do
    at_fields =
      for {field, {message, vars}} <- at_fields(form),
          do: at_field(model, cell, field, {message, vars})

    nested =
      for {path, field, error} <- nested(form),
          text = nested_text(model, path, field, error),
          do: text

    uniq(at_fields ++ nested ++ without_fields(form, refusal))
  end

  @doc """
  The errors of a form that are about a field of a value inside the record:
  of an embedded resource or a map, or of one of an array of them. Each
  with the way to that value (the record's attribute first, then the place
  of a value in an array, counted from 0, and the fields on the way), the
  field, and the message with its variables.

  Ash says the way as the error's path. A form puts such an error nowhere:
  the table gives the action the value as a map, and has no form nested in
  the action's for it. They are read from the form's raw errors, through
  the protocol the form itself reads an error with.
  """
  @spec nested(AshPhoenix.Form.t()) :: [{[atom | non_neg_integer], atom, {String.t(), keyword}}]
  def nested(form) do
    for %{class: :invalid, path: [name | _rest] = path} = error <-
          AshPhoenix.Form.raw_errors(form),
        is_atom(name),
        about_field?(error),
        AshPhoenix.FormData.Error.impl_for(error),
        {field, message, vars} <- List.wrap(AshPhoenix.FormData.Error.to_form_error(error)),
        is_binary(message),
        do: {path, field, {message, Keyword.new(vars)}}
  end

  @doc """
  The text of such an error where it is not shown at its field: the message
  after what the value and the field are called, from the outside in
  ("Client: Street: is required").

  Only for a value the person has a column for, which is called what its
  column is. Nil for any other: a path leads into whatever is nested in the
  record, a related record among it, whose field may be called what a
  column of this table is, and is not that column.
  """
  @spec nested_text(Model.t(), [atom | non_neg_integer], atom, {String.t(), keyword}) ::
          message | nil
  def nested_text(%Model{} = model, [name | rest], field, {_message, _vars} = error) do
    with %{label: label, cell_type: cell_type} when cell_type in [:map, {:array, :map}, :union] <-
           Enum.find(model.columns, &(&1.name == name)) do
      labels =
        Enum.reduce(rest ++ [field], [label], fn
          index, [label | labels] when is_integer(index) ->
            [{:text, :value_position, column: label, position: index + 1} | labels]

          name, labels ->
            [{:label, AshDataTable.Resource.Words.humanize(name)} | labels]
        end)

      Enum.reduce(labels, ash(error), fn label, message ->
        {:text, :error_on_field, field: label, message: message}
      end)
    else
      _no_such_column -> nil
    end
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
  @spec without_fields(AshPhoenix.Form.t(), message) :: [message]
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
  @spec of_read(term, Model.t()) :: [message]
  def of_read(error, %Model{} = model) do
    case Ash.Error.to_error_class(error) do
      %Ash.Error.Invalid{errors: errors} ->
        errors |> Enum.flat_map(&texts(&1, model)) |> uniq()

      _other ->
        []
    end
  end

  @doc """
  What an action that did not run on a record says to a person, where it
  was not run through a form: the messages of the errors it returned on
  purpose, each one once, a refusal among them as `refusal`. Empty when
  there is none that a person should read.
  """
  @spec of_action(term, Model.t(), message) :: [message]
  def of_action(error, %Model{} = model, refusal) do
    case Ash.Error.to_error_class(error) do
      %Ash.Error.Forbidden{} ->
        [refusal]

      %Ash.Error.Invalid{errors: errors} ->
        errors |> Enum.flat_map(&texts(&1, model)) |> uniq()

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

      # about a field of a value inside the record, which has only the name
      # in common with a field of the record
      match?(%{path: [name | _]} when is_atom(name), error) and
          not is_nil(AshPhoenix.FormData.Error.impl_for(error)) ->
        for {field, message, vars} <- List.wrap(AshPhoenix.FormData.Error.to_form_error(error)),
            is_binary(message),
            text = nested_text(model, error.path, field, {message, Keyword.new(vars)}),
            do: text

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
