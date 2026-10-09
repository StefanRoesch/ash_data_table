defmodule AshTable.Act do
  @moduledoc false
  # Runs what a table lets a person run besides a cell's edit: a row action
  # on the record of a row, and the table's create action. The table adds
  # nothing of its own: the action is the resource's, run through
  # `AshPhoenix.Form` with the person's actor, tenant and authorization, and
  # what it returns is what the table shows.
  #
  # The record of a row is read again first, as the person (`AshTable.Record`),
  # when an action's panel is opened and once more when the action runs: a
  # key is all the table keeps of a row, and what was true when the panel
  # opened need not be when "Run" is used.
  #
  # What comes from the browser is the values of the action's inputs and
  # nothing else. They are taken by the names of the inputs the table offers
  # this person for this record: an attribute the person may not see, on any
  # record or on this one, is no input of theirs, and a field of a nested
  # table's create action that joins the new record to its row is given by
  # the table, never by the form.

  alias AshTable.Errors
  alias AshTable.Model
  alias AshTable.Model.Action
  alias AshTable.Query
  alias AshTable.Record
  alias AshTable.Text

  @typedoc "A form of `AshPhoenix.Form`."
  @type form :: AshPhoenix.Form.t()

  @typedoc """
  What became of a row action:

    * `{:ok, record}` - it ran. The record is as the action returned it, with
      everything the table's columns show loaded;
    * `:destroyed` - it ran, and the record is no more;
    * `:gone` - it ran, and the record is no longer this person's to read;
    * `{:error, record, message}` - it did not run. The record is as it is
      stored; nil when it can no longer be read by this person.
  """
  @type result ::
          {:ok, Ash.Resource.record()}
          | :destroyed
          | :gone
          | {:error, Ash.Resource.record() | nil, String.t()}

  @doc """
  Runs a row action straight away, without inputs, on the record with the
  primary key `key`. Takes the options of `AshTable.Query.read/3` that say
  who is asking.
  """
  @spec run(Model.t(), Action.t(), map, keyword) :: result
  def run(%Model{} = model, %Action{} = action, key, opts) when is_map(key) do
    opts = Query.reader_opts(opts)

    with {:ok, record} <- Record.fetch(model, key, opts) do
      case submit(model, form(record, action, "action", opts), %{}, opts) do
        {:error, form} ->
          message = Enum.join(messages(form, model), "; ")

          case Record.load(model, record, opts) do
            {:ok, record} -> {:error, record, message}
            :error -> {:error, nil, message}
          end

        ran ->
          ran
      end
    else
      :error -> {:error, nil, Text.t(:record_gone)}
    end
  end

  @doc """
  Opens a row action for the record with the primary key `key`: the record
  as it was read for the person, the form of the action on it, and the
  inputs this person has on this record. `id` is the id of the form.
  """
  @spec open(Model.t(), Action.t(), map, String.t(), keyword) ::
          {:ok, Ash.Resource.record(), form, [Model.Input.t()]} | :error
  def open(%Model{} = model, %Action{} = action, key, id, opts) when is_map(key) do
    opts = Query.reader_opts(opts)

    with {:ok, record} <- Record.fetch(model, key, opts) do
      {:ok, record, form(record, action, id, opts), inputs(action, record)}
    end
  end

  @doc """
  The inputs of a row action that the person has on this record: without
  the attributes that are hidden from them on it. The action would not stop
  them (field policies are about reading); the table does, as for a cell.
  """
  @spec inputs(Action.t(), Ash.Resource.record()) :: [Model.Input.t()]
  def inputs(%Action{inputs: inputs}, record) do
    Enum.reject(inputs, fn input ->
      input.kind == :attribute and match?(%Ash.ForbiddenField{}, Map.get(record, input.name))
    end)
  end

  @doc "The form of the table's create action. `id` is the id of the form."
  @spec open_create(Model.t(), Action.t(), String.t(), keyword) :: form
  def open_create(%Model{} = model, %Action{type: :create} = action, id, opts) do
    AshPhoenix.Form.for_create(
      model.resource,
      action.name,
      form_opts(id) ++ Query.reader_opts(opts)
    )
  end

  @doc """
  The form with what the person has typed so far, as the action sees it:
  `AshPhoenix.Form.validate/3`, with the values of `inputs` and no others.
  `given` is what the table itself gives the action.
  """
  @spec validate(form, [Model.Input.t()], map, map) :: form
  def validate(form, inputs, params, given \\ %{}) do
    AshPhoenix.Form.validate(form, taken(inputs, params, given))
  end

  @doc """
  Runs a row action with the inputs a person gave in its panel. The record
  is read again, as the person; the values are taken for the inputs they
  have on the record as it is now.

  Returns what `run/4` returns, but for an action that did not run:
  `{:error, form}`, the form with the action's errors.
  """
  @spec submit_row(Model.t(), Action.t(), map, map, String.t(), keyword) ::
          {:ok, Ash.Resource.record()}
          | :destroyed
          | :gone
          | {:error, form}
          | {:error, nil, String.t()}
  def submit_row(%Model{} = model, %Action{} = action, key, params, id, opts) do
    opts = Query.reader_opts(opts)

    case Record.fetch(model, key, opts) do
      {:ok, record} ->
        submit(
          model,
          form(record, action, id, opts),
          taken(inputs(action, record), params, %{}),
          opts
        )

      :error ->
        {:error, nil, Text.t(:record_gone)}
    end
  end

  @doc """
  Runs the table's create action with the inputs a person gave in its
  panel. `given` is what the table itself gives the action: the field that
  joins a record created in a nested table to its row.

  Returns `{:ok, record}` with everything the table's columns show loaded,
  `:gone` when the record was created and is not this person's to read, or
  `{:error, form}`.
  """
  @spec submit_create(Model.t(), Action.t(), map, map, String.t(), keyword) ::
          {:ok, Ash.Resource.record()} | :gone | {:error, form}
  def submit_create(%Model{} = model, %Action{type: :create} = action, params, given, id, opts) do
    submit(model, open_create(model, action, id, opts), taken(action.inputs, params, given), opts)
  end

  defp submit(model, form, params, opts) do
    opts = Query.reader_opts(opts)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, %_{} = record} when form.type != :destroy ->
        # the row is shown from what the action returns
        case Record.load(model, record, opts) do
          {:ok, record} -> {:ok, record}
          :error -> :gone
        end

      {:error, form} ->
        {:error, form}

      # a destroy action: `:ok`, or the record it destroyed
      _destroyed ->
        :destroyed
    end
  end

  defp form(record, %Action{type: :update, name: name}, id, opts),
    do: AshPhoenix.Form.for_update(record, name, form_opts(id) ++ opts)

  defp form(record, %Action{type: :destroy, name: name}, id, opts),
    do: AshPhoenix.Form.for_destroy(record, name, form_opts(id) ++ opts)

  # what the form cannot put at a field is read from its raw errors
  defp form_opts(id), do: [as: "panel", id: id, warn_on_unhandled_errors?: false]

  # The values of the inputs, by name, as they were typed, and what the table
  # gives itself, which nothing from the browser replaces.
  defp taken(inputs, params, given) when is_map(params) do
    for input <- inputs,
        name = Atom.to_string(input.name),
        is_map_key(params, name),
        into: %{} do
      {name, typed(input, params[name])}
    end
    |> Map.merge(given)
  end

  defp taken(_inputs, _params, given), do: given

  # What a field of the panel holds. A form cannot send a list without
  # values, so the field of an array sends one entry of its own before its
  # values (see the panel's `field/1`), which is left out here: what remains
  # is the values as they were typed, and the empty list when there are none.
  defp typed(%{cell_type: {:array, _item}}, [_own | values]), do: values
  defp typed(_input, typed), do: typed

  @doc """
  What a form's errors say to a person: by input, for the errors about one
  of `inputs`, and under `nil` for the others. See `AshTable.Errors` for
  what is shown of an error.
  """
  @spec errors(form, Model.t(), [Model.Input.t()]) :: %{optional(atom | nil) => [String.t()]}
  def errors(form, %Model{} = model, inputs) do
    at_fields =
      for {field, error} <- Errors.at_fields(form) do
        case Enum.find(inputs, &(&1.name == field)) do
          nil -> {nil, Errors.at_field(model, nil, field, error)}
          input -> {field, Errors.at_value(input, error)}
        end
      end

    without_field =
      for message <- Errors.without_fields(form, Text.t(:action_not_allowed)), do: {nil, message}

    grouped = Enum.group_by(at_fields ++ without_field, &elem(&1, 0), &elem(&1, 1))
    Map.new(grouped, fn {field, messages} -> {field, Enum.uniq(messages)} end)
  end

  @doc """
  The values of the arrays among `inputs` that a form's errors are about:
  by input, their places, counted from 0. Only the inputs that have any.
  """
  @spec places(form, [Model.Input.t()]) :: %{optional(atom) => [non_neg_integer]}
  def places(form, inputs) do
    for input <- inputs, places = Errors.places(form, input), places != [], into: %{} do
      {input.name, places}
    end
  end

  @doc "Everything a form's errors say, as the messages of an action that failed."
  @spec messages(form, Model.t()) :: [String.t()]
  def messages(form, %Model{} = model) do
    case Errors.of_form(form, model, nil, Text.t(:action_not_allowed)) do
      [] -> [Text.t(:action_failed)]
      messages -> messages
    end
  end
end
