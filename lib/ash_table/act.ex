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
  #
  # An input that is a map cell (an embedded resource, a map, an array of
  # either) is given as a map of its fields, as an API gives it: by the
  # names of the fields the table offers, each as it was typed, and nothing
  # else that was sent (`typed/2`). Ash casts it, through the embedded
  # resource's own actions. An error about a field of such a value is shown
  # at that field (`errors/4`).
  #
  # An input that is given by choosing a related record (`editor: :reference`)
  # holds that record's key, and a key from the browser is a claim like any
  # other: before an action runs, a key that was put there is looked up as
  # the person, through the read action the picker offers its records
  # through (`unchosen/4`). One that names nothing they could have chosen
  # runs nothing.

  alias AshTable.Errors
  alias AshTable.Format
  alias AshTable.Model
  alias AshTable.Model.Action
  alias AshTable.Pick
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
      # hidden as a whole, or a map cell with a field that is hidden in it
      input.kind == :attribute and
        AshTable.Resource.Embedding.hidden?(Map.get(record, input.name))
    end)
  end

  @doc """
  The form of a row action that is to run on several records at once, for
  the action panel. `id` is the id of the form.

  A form is of an action on one record, and here there is none to name: the
  form is of the action on a record that holds nothing, not even the
  defaults of its attributes. It is what the person types into, and what
  tells them what the action makes of a value as such (a text that is no
  number, an argument that is too short, a required input that is empty).
  What the action makes of it on each record is known when it has run.
  """
  @spec open_bulk(Model.t(), Action.t(), String.t(), keyword) :: form
  def open_bulk(%Model{resource: resource}, %Action{} = action, id, opts) do
    blank =
      resource
      |> Ash.Resource.Info.attributes()
      |> Enum.reduce(struct(resource), &Map.put(&2, &1.name, nil))

    form(blank, action, id, Query.reader_opts(opts))
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
  `{:error, form}`, the form with the action's errors, or
  `{:unchosen, inputs}`, the inputs whose value names a record the person
  could not have chosen (`unchosen/4`).
  """
  @spec submit_row(Model.t(), Action.t(), map, map, String.t(), keyword) ::
          {:ok, Ash.Resource.record()}
          | :destroyed
          | :gone
          | {:error, form}
          | {:unchosen, [Model.Input.t()]}
          | {:error, nil, String.t()}
  def submit_row(%Model{} = model, %Action{} = action, key, params, id, opts) do
    chooser = opts
    opts = Query.reader_opts(opts)

    case Record.fetch(model, key, opts) do
      {:ok, record} ->
        inputs = inputs(action, record)

        case unchosen(inputs, params, record, chooser) do
          [] -> submit(model, form(record, action, id, opts), taken(inputs, params, %{}), opts)
          unchosen -> {:unchosen, unchosen}
        end

      :error ->
        {:error, nil, Text.t(:record_gone)}
    end
  end

  @doc """
  Runs the table's create action with the inputs a person gave in its
  panel. `given` is what the table itself gives the action: the field that
  joins a record created in a nested table to its row.

  Returns `{:ok, record}` with everything the table's columns show loaded,
  `:gone` when the record was created and is not this person's to read,
  `{:error, form}`, or `{:unchosen, inputs}` as `submit_row/6` does.
  """
  @spec submit_create(Model.t(), Action.t(), map, map, String.t(), keyword) ::
          {:ok, Ash.Resource.record()} | :gone | {:error, form} | {:unchosen, [Model.Input.t()]}
  def submit_create(%Model{} = model, %Action{type: :create} = action, params, given, id, opts) do
    case unchosen(action.inputs, params, nil, opts) do
      [] ->
        submit(
          model,
          open_create(model, action, id, opts),
          taken(action.inputs, params, given),
          opts
        )

      unchosen ->
        {:unchosen, unchosen}
    end
  end

  @doc """
  The inputs among `inputs` whose value, in what a panel's form sent, names
  a record this person could not have chosen: an input that is given by
  choosing a related record, with a key that is none of a record they may
  read through the picker's read action.

  Left alone are an input that is empty, one that holds what `record` holds
  already (nil where there is no record: a create, a selection), which
  nobody chose, and one whose value is no key at all, which the action
  says itself.

  `opts` are those of `AshTable.Pick.reader/2`, and `:picked_with`: what the
  picker's read action was given for a key that was chosen there.
  """
  @spec unchosen([Model.Input.t()], map, Ash.Resource.record() | nil, keyword) ::
          [Model.Input.t()]
  def unchosen(inputs, params, record, opts) when is_map(params) do
    for %{editor: :reference, reference: reference, type: {type, constraints}} = input <- inputs,
        typed = params[Atom.to_string(input.name)],
        typed not in [nil, ""],
        {:ok, value} when not is_nil(value) <- [Ash.Type.cast_input(type, typed, constraints)],
        is_nil(record) or not held?(record, input.name, value),
        Pick.current(reference, value, chosen_with(opts, input, typed)) == :error do
      input
    end
  end

  def unchosen(_inputs, _params, _record, _opts), do: []

  # A key that was chosen in the picker is looked up as it was found there:
  # with what the picker's read action was given then (`:picked_with`: by
  # input, the key as it was written and those arguments). Any other key
  # through the action as it is.
  defp chosen_with(opts, %{name: name}, typed) do
    case Keyword.get(opts, :picked_with, %{}) do
      %{^name => {^typed, arguments}} -> Keyword.put(opts, :arguments, arguments)
      _typed_or_none -> Keyword.delete(opts, :arguments)
    end
  end

  # two keys that are written alike are the same key
  defp held?(record, name, value) do
    case Map.get(record, name) do
      nil -> false
      %Ash.ForbiddenField{} -> false
      held -> written(held) == written(value)
    end
  end

  defp written(value), do: if(String.Chars.impl_for(value), do: to_string(value), else: value)

  @doc """
  What an action is given of what a panel's form sent: the values of
  `inputs`, by name, as they were typed, and no others.
  """
  @spec values([Model.Input.t()], map) :: map
  def values(inputs, params), do: taken(inputs, params, %{})

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

  @doc """
  The options of a form of the panel. What the form cannot put at a field
  is read from its raw errors.

  The form builds no forms nested in it (`auto?: false`): the value of an
  embedded resource is given to the action as a map of its fields, as the
  value of a map is, and as an API gives it. AshPhoenix would nest a form
  for an embedded resource and none for a map, and the two are edited
  alike.
  """
  @spec form_opts(String.t()) :: keyword
  def form_opts(id),
    do: [as: "panel", id: id, warn_on_unhandled_errors?: false, forms: [auto?: false]]

  # The values of the inputs, by name, as they were typed, and what the table
  # gives itself, which nothing from the browser replaces.
  defp taken(inputs, params, given) when is_map(params) do
    for input <- inputs,
        name = Atom.to_string(input.name),
        given?(input, params, name),
        into: %{} do
      {name, typed(input, params[name])}
    end
    |> Map.merge(given)
  end

  defp taken(_inputs, _params, given), do: given

  # A map cell always says what it holds: a group that is not there is no
  # value, and a list without groups is the empty list.
  defp given?(%{editor: editor}, _params, _name) when editor in [:group, :groups], do: true
  defp given?(_input, params, name), do: is_map_key(params, name)

  @doc """
  What a field of the panel holds, of what its form sent for it.

  A form cannot send a list without values, so the field of an array sends
  one entry of its own before its values (see the panel's `field/1`), which
  is left out here: what remains is the values as they were typed, and the
  empty list when there are none.

  The field of a map cell sends its inputs by name, with a mark of its own
  (`_present`), and nothing at all while it has no value: what remains is
  the inputs by name, as they were typed, or nil. An array of them sends
  each value under a number of its own, which says their order and nothing
  else: what remains is the list of them. Only what the fields say is
  taken, whatever else was sent.
  """
  @spec typed(map, term) :: term
  def typed(%{cell_type: :map, fields: [_ | _] = fields}, %{} = sent) do
    for %{name: name} = field <- fields, field.input? or field.key?, reduce: %{} do
      taken ->
        key = Atom.to_string(name)

        cond do
          field.input? -> Map.put(taken, key, inner(field, sent[key]))
          # the key of an embedded resource, as it came: Ash matches by it
          is_binary(sent[key]) and sent[key] != "" -> Map.put(taken, key, sent[key])
          true -> taken
        end
    end
  end

  def typed(%{cell_type: :map, fields: [_ | _]}, _nothing), do: nil

  def typed(%{cell_type: {:array, :map}, fields: [_ | _]} = field, %{} = sent),
    do: for({_key, item} <- items(sent), do: typed(%{field | cell_type: :map}, item))

  def typed(%{cell_type: {:array, :map}, fields: [_ | _]}, _nothing), do: []
  def typed(%{cell_type: {:array, _item}}, [_own | values]), do: values
  def typed(_input, typed), do: typed

  # A field of a map cell always sends something: nothing is the value it
  # has when it is empty.
  defp inner(%{cell_type: cell_type} = field, sent) when cell_type in [:map, {:array, :map}],
    do: typed(field, sent)

  defp inner(%{cell_type: {:array, _item}} = field, sent) when is_list(sent),
    do: typed(field, sent)

  defp inner(%{cell_type: {:array, _item}}, _nothing), do: []
  defp inner(%{cell_type: :boolean}, sent), do: to_string(sent == "true")
  defp inner(_field, sent) when is_binary(sent), do: sent
  defp inner(_field, _nothing), do: ""

  @doc """
  The values of an array of map cells as its field sent them, in their
  order: each with the number it was sent under.
  """
  @spec items(term) :: [{String.t(), map}]
  def items(%{} = sent) do
    numbered =
      for {key, %{} = item} <- sent, {number, ""} <- [Integer.parse(key)], do: {number, key, item}

    for {_number, key, item} <- Enum.sort(numbered), do: {key, item}
  end

  def items(_sent), do: []

  @doc """
  What the field of a map cell sends for a value it holds: the opposite of
  `typed/2`. `held` is the value as its editor holds it
  (`AshTable.Format.input/2`). It is what the field starts with.
  """
  @spec sent(map, term) :: term
  def sent(%{cell_type: :map, fields: [_ | _] = fields}, %{} = held) do
    for %{name: name} = field <- fields, field.input? or field.key?, into: %{"_present" => ""} do
      key = Atom.to_string(name)
      {key, sent(field, held[key])}
    end
  end

  def sent(%{cell_type: :map, fields: [_ | _]}, _nothing), do: nil

  def sent(%{cell_type: {:array, :map}, fields: [_ | _]} = field, held) do
    for {item, number} <- Enum.with_index(List.wrap(held)), into: %{"_present" => ""} do
      {Integer.to_string(number), sent(%{field | cell_type: :map}, item)}
    end
  end

  def sent(%{cell_type: {:array, _item}}, held), do: ["" | List.wrap(held)]
  def sent(_field, nil), do: ""
  def sent(_field, held), do: held

  @doc """
  What the field of a map cell sends for a new value: its inputs empty, but
  for those that have a default, and a value inside it that cannot be left
  out started the same way.
  """
  @spec blank(map) :: map
  def blank(%{fields: fields}) do
    for %{name: name, input?: true} = field <- fields, into: %{"_present" => ""} do
      started =
        cond do
          not is_nil(field.default) ->
            sent(field, Format.input(field, field.default))

          field.cell_type == :map and field.required? and is_list(field.fields) ->
            blank(field)

          true ->
            sent(field, Format.input(field, nil))
        end

      {Atom.to_string(name), started}
    end
  end

  @doc """
  Whether what the field of a map cell sent is what the cell holds already:
  `value` as the record has it. Compared as the field itself would send
  the value.
  """
  @spec unchanged?(map, term, term) :: boolean
  def unchanged?(input, sent, value),
    do: typed(input, sent) == typed(input, sent(input, Format.input(input, value)))

  @doc """
  What a form's errors say to a person: by input, for the errors about one
  of `inputs`, and under `nil` for the others. An error about a field of a
  value inside the record (a field of a map cell) is under the way to that
  field: the input, the places of values in an array, and the fields on the
  way (`[:client, :address, :city]`, `[:milestones, 1, :title]`). See
  `AshTable.Errors` for what is shown of an error; `refusal` is what a
  refusal reads as.
  """
  @spec errors(form, Model.t(), [Model.Input.t()], String.t()) ::
          %{optional(atom | nil | [atom | non_neg_integer]) => [String.t()]}
  def errors(form, %Model{} = model, inputs, refusal \\ Text.t(:action_not_allowed)) do
    at_fields =
      for {field, error} <- Errors.at_fields(form) do
        case Enum.find(inputs, &(&1.name == field)) do
          nil -> {nil, Errors.at_field(model, nil, field, error)}
          input -> {field, Errors.at_value(input, error)}
        end
      end

    without_field =
      for message <- Errors.without_fields(form, refusal), do: {nil, message}

    # about a field of a value inside the record: at that field, where the
    # panel has it, by the way to it
    nested =
      for {path, field, error} <- Errors.nested(form),
          placed =
            (case place(inputs, path, field, error) do
               {:field, place} -> {place, Text.error(error)}
               # at the group, which says which of its fields is meant
               {:group, place} -> {single(place), named(field, error)}
               nil -> {nil, Errors.nested_text(model, path, field, error)}
             end),
          not is_nil(elem(placed, 1)),
          do: placed

    grouped = Enum.group_by(at_fields ++ nested ++ without_field, &elem(&1, 0), &elem(&1, 1))
    Map.new(grouped, fn {field, messages} -> {field, Enum.uniq(messages)} end)
  end

  # Where the panel shows an error about a field of a value inside the
  # record: the way to the field, as far as the panel has it (the input,
  # the places of the values of arrays, the fields on the way). An error
  # about something the panel has no field for is shown at the group it is
  # in. Nil when the panel has no input for the value at all.
  #
  # Ash says the place of a value of an array of embedded resources in the
  # error's path, and that of an array of maps among its variables, if at
  # all.
  defp place(inputs, [name | rest], field, {_message, vars}) do
    with %{fields: [_ | _]} = input <-
           Enum.find(inputs, &(&1.name == name and &1.editor in [:group, :groups])) do
      {place, at} = Enum.reduce_while(rest, {[name], input}, &step/2)

      {place, at} =
        case {at.cell_type, List.last(place), vars[:index]} do
          {{:array, :map}, last, index} when not is_integer(last) and is_integer(index) ->
            {place ++ [index], at}

          _placed ->
            {place, at}
        end

      cond do
        # the values of an array are told apart by their places
        match?({:array, :map}, at.cell_type) and not is_integer(List.last(place)) ->
          {:group, place}

        Enum.any?(at.fields || [], &(&1.name == field and &1.input?)) ->
          {:field, place ++ [field]}

        # Ash says of some errors of a value inside a value that they are
        # about the value around it. Where one value in it, and no other,
        # has a field of that name, that is the field.
        true ->
          case inside(at, field) do
            [way] -> {:field, place ++ way}
            _none_or_several -> {:group, place}
          end
      end
    else
      _no_group -> nil
    end
  end

  # The ways from a value to a field of that name in the values inside it,
  # not through an array.
  defp inside(%{fields: fields}, name) do
    for %{cell_type: :map, fields: [_ | _], input?: true} = inner <- fields || [],
        way <-
          if(Enum.any?(inner.fields, &(&1.name == name and &1.input?)), do: [[name]], else: []) ++
            inside(inner, name),
        do: [inner.name | way]
  end

  # the errors of an input as a whole are under its name
  defp single([name]), do: name
  defp single(place), do: place

  # The message of an error about a field the panel has no place for, after
  # the field's name in words.
  defp named(field, error) do
    Text.t(:error_on_field,
      field: Text.label(Model.humanize(field)),
      message: Text.error(error)
    )
  end

  defp step(index, {place, %{cell_type: {:array, :map}} = at})
       when is_integer(index) do
    if is_integer(List.last(place)),
      do: {:halt, {place, at}},
      else: {:cont, {place ++ [index], at}}
  end

  defp step(name, {place, at}) when is_atom(name) do
    listed? = match?({:array, :map}, at.cell_type) and not is_integer(List.last(place))

    case not listed? && Enum.find(at.fields || [], &(&1.name == name and is_list(&1.fields))) do
      %{} = field -> {:cont, {place ++ [name], field}}
      _none -> {:halt, {place, at}}
    end
  end

  defp step(_other, acc), do: {:halt, acc}

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
