defmodule AshDataTable.Act do
  @moduledoc false
  # Runs what a table lets a person run besides a cell's edit: a row action
  # on the record of a row, and the table's create action. The table adds
  # nothing of its own: the action is the resource's, run through
  # `AshPhoenix.Form` with the person's actor, tenant and authorization, and
  # what it returns is what the table shows.
  #
  # The record of a row is read again first, as the person (`AshDataTable.Record`),
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
  # An input that is a union is given as its kind and that kind's value, as
  # Ash takes a union from outside (`typed/2`).
  #
  # An input that is sensitive (`AshDataTable.Sensitive`) is typed hidden, into a
  # field that starts empty whatever the record holds. Left empty it is not
  # given to the action at all: an update keeps what the record has, and a
  # create or an argument is given nothing, which the action answers as it
  # answers any input that is missing.
  #
  # So a sensitive input cannot be emptied by leaving it empty. An update
  # action is told to empty one by name: the panel says which of its fields
  # a person asked to clear (`:cleared`), and those among them that can be
  # cleared on the record as it is now (`clearable/3`) are given nil, as
  # what the table gives itself. Nothing the form sends says so.
  #
  # An input that takes a file is never taken from what the browser sent:
  # the table gives it, from the upload the panel holds, as what it gives
  # itself.
  #
  # An input that is given by choosing a related record (`editor: :reference`)
  # holds that record's key, and a key from the browser is a claim like any
  # other: before an action runs, a key that was put there is looked up as
  # the person, through the read action the picker offers its records
  # through (`unchosen/4`). One that names nothing they could have chosen
  # runs nothing.
  #
  # So does an argument that hands the keys of several records to a
  # relationship (`editor: :references`): every key in it is looked up the
  # same way, but for those of the records that are related already where
  # the argument is everything the relationship is to hold (`related/3`).
  # Those are nobody's choice: they were there.
  #
  # A generic action is given no record: it is run through the same form
  # (`AshPhoenix.Form.for_action/3`, which builds an `Ash.ActionInput` and
  # runs it with `Ash.run_action/2`), with the values of its arguments. One
  # that is a row action (`record_argument`) is given the primary key of its
  # row as that argument, by the table: the record is read first, as the
  # person, as for any row action, and the key is the one the table holds,
  # never one the browser sent. What such an action returns is no row: the
  # table says it (`said/2`) and reads again.

  require Logger

  alias AshDataTable.Errors
  alias AshDataTable.Format
  alias AshDataTable.Model
  alias AshDataTable.Model.Action
  alias AshDataTable.Pick
  alias AshDataTable.Query
  alias AshDataTable.Record
  alias AshDataTable.Text
  alias AshDataTable.Typed

  @typedoc "A form of `AshPhoenix.Form`."
  @type form :: AshPhoenix.Form.t()

  @typedoc """
  What became of a row action:

    * `{:ok, record}` - it ran. The record is as the action returned it, with
      everything the table's columns show loaded;
    * `{:done, value}` - a generic action ran, and returned `value` (nil
      when it returns nothing);
    * `:destroyed` - it ran, and the record is no more;
    * `:gone` - it ran, and the record is no longer this person's to read;
    * `{:error, record, message}` - it did not run. The record is as it is
      stored; nil when it can no longer be read by this person.
  """
  @type result ::
          {:ok, Ash.Resource.record()}
          | {:done, term}
          | :destroyed
          | :gone
          | {:error, Ash.Resource.record() | nil, String.t()}

  @doc """
  Runs a row action straight away, without inputs, on the record with the
  primary key `key`. Takes the options of `AshDataTable.Query.read/3` that say
  who is asking.
  """
  @spec run(Model.t(), Action.t(), map, keyword) :: result
  def run(%Model{} = model, %Action{type: :action} = action, key, opts) when is_map(key) do
    opts = Query.reader_opts(opts)

    with {:ok, record} <- Record.fetch(model, key, opts) do
      case run_generic(model, action, given(action, key), opts) do
        {:done, value} ->
          {:done, value}

        {:error, message} ->
          case Record.load(model, record, opts) do
            {:ok, record} -> {:error, record, message}
            :error -> {:error, nil, message}
          end
      end
    else
      :error -> {:error, nil, Text.t(:record_gone)}
    end
  end

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
  def open(%Model{} = model, %Action{type: :action} = action, key, id, opts) when is_map(key) do
    with {:ok, record} <- Record.fetch(model, key, Query.reader_opts(opts)) do
      {:ok, record, open_generic(model, action, id, opts), action.inputs}
    end
  end

  def open(%Model{} = model, %Action{} = action, key, id, opts) when is_map(key) do
    opts = Query.reader_opts(opts)

    with {:ok, record} <- Record.fetch(model, key, opts) do
      {:ok, record, form(record, action, id, opts), inputs(action, record)}
    end
  end

  @doc """
  The form of a generic action, for the action panel: of a table action,
  and of a generic action that is to run on several records at once, whose
  form is of the action without the argument a row gives. `id` is the id of
  the form.
  """
  @spec open_generic(Model.t(), Action.t(), String.t(), keyword) :: form
  def open_generic(%Model{resource: resource}, %Action{type: :action, name: name}, id, opts),
    do: AshPhoenix.Form.for_action(resource, name, form_opts(id) ++ Query.reader_opts(opts))

  @doc """
  What the table itself gives a generic action that runs on the record
  with the primary key `key`: that key, as the argument the action's
  declaration names. Nothing for any other action.
  """
  @spec given(Action.t(), map) :: map
  def given(%Action{type: :action, record_argument: name}, key)
      when not is_nil(name) and map_size(key) == 1 do
    [value] = Map.values(key)
    %{Atom.to_string(name) => value}
  end

  def given(%Action{}, _key), do: %{}

  @doc """
  Runs a generic action straight away, with `given` as its arguments: what
  the table gives itself, and for an action that runs on several records
  what its panel held.

  Returns `{:done, value}` with what the action returned (nil when it
  returns nothing), or `{:error, message}` with what it said.
  """
  @spec run_generic(Model.t(), Action.t(), map, keyword) :: {:done, term} | {:error, String.t()}
  def run_generic(%Model{} = model, %Action{type: :action} = action, given, opts)
      when is_map(given) do
    case submit_generic(model, action, %{}, given, "action", opts) do
      {:done, value} -> {:done, value}
      {:error, %AshPhoenix.Form{} = form} -> {:error, Enum.join(messages(form, model), "; ")}
      {:error, nil, message} -> {:error, message}
    end
  end

  @doc """
  Runs a generic action with the inputs a person gave in its panel, and
  with `given`, what the table itself gives it.

  Returns `{:done, value}`, `{:error, form}` with the action's errors,
  `{:unchosen, inputs}` as `submit_row/6` does (`opts` are then those of
  `unchosen/4`), or
  `{:error, nil, message}` for a failure that is not of the action's
  saying: Ash raises what goes wrong inside a generic action, where it
  returns it for the others. That is for whoever runs the application, in
  the log.
  """
  @spec submit_generic(Model.t(), Action.t(), map, map, String.t(), keyword) ::
          {:done, term}
          | {:error, form}
          | {:unchosen, [Model.Input.t()]}
          | {:error, nil, String.t()}
  def submit_generic(%Model{} = model, %Action{type: :action} = action, params, given, id, opts) do
    # an argument whose records are chosen (`reference` in the block) holds
    # keys, and a key from the browser is a claim, as for any other action
    case unchosen(action.inputs, params, nil, opts) do
      [] ->
        form = open_generic(model, action, id, opts)

        case AshPhoenix.Form.submit(form,
               params: taken(action.inputs, params, given, model.time_zone)
             ) do
          :ok -> {:done, nil}
          {:ok, value} -> {:done, value}
          {:error, form} -> {:error, form}
        end

      unchosen ->
        {:unchosen, unchosen}
    end
  rescue
    error ->
      Logger.error(
        "ash_data_table: the action `#{action.name}` of #{inspect(model.resource)} failed: " <>
          Exception.message(error)
      )

      {:error, nil, Text.t(:action_failed)}
  end

  @doc """
  What a generic action returned, as a person is told it: a value that can
  be said in a word or a line. That is text, a number, yes or no, a date, a
  datetime, and a name (an atom: a value of an enum by its label). Nil for
  everything else, and for nothing: the table then says no more than that
  the action is done.

  The value is looked at, not the type the action declares: Ash does not
  cast what a generic action returns.
  """
  @spec said(Action.t(), term) :: String.t() | nil
  def said(action, value), do: said(action, value, AshDataTable.Zone.utc())

  @spec said(Action.t(), term, AshDataTable.Zone.t()) :: String.t() | nil
  def said(%Action{} = action, value, zone) do
    text =
      case value do
        nil -> nil
        value when is_boolean(value) -> Format.format(%{cell_type: :boolean}, value, zone)
        value when is_binary(value) -> if String.valid?(value), do: value
        value when is_number(value) -> Format.format(%{cell_type: :number}, value, zone)
        %Decimal{} -> Format.format(%{cell_type: :number}, value, zone)
        %Date{} -> Format.format(%{cell_type: :date}, value, zone)
        # an instant as the clocks of the page's zone show it
        %DateTime{} -> Format.format(%{cell_type: :datetime}, value, zone)
        %NaiveDateTime{} -> Format.format(%{cell_type: :datetime}, value, zone)
        value when is_atom(value) -> by_name(action.returns, value, zone)
        _records_and_everything_else -> nil
      end

    if is_binary(text) and String.trim(text) != "", do: text
  end

  defp by_name(%{cell_type: :enum} = returns, value, zone),
    do: Format.format(returns, value, zone)

  defp by_name(_returns, value, zone), do: Format.format(%{cell_type: :other}, value, zone)

  @doc """
  The inputs of a row action that a person can ask to be emptied on this
  record, by name: the sensitive attributes an update action accepts and
  takes without a value (`required?`), which the record holds a value for
  that this person sees. A sensitive field starts empty and gives the
  action nothing while it is empty, so this is the one way to empty it.

  None for any other action: a create has nothing to empty, a destroy
  takes the record away, and an argument holds nothing between two runs.
  """
  @spec clearable(Action.t(), [Model.Input.t()], Ash.Resource.record() | nil) :: [atom]
  def clearable(%Action{type: :update}, inputs, %_{} = record) do
    for %{kind: :attribute, sensitive?: true, required?: false, name: name} <- inputs,
        value = Map.get(record, name),
        not is_struct(value, Ash.ForbiddenField),
        not AshDataTable.Resource.Exposing.empty?(value),
        do: name
  end

  def clearable(%Action{}, _inputs, _record), do: []

  # What the action is given for the inputs a person asked to clear: nil,
  # for those that can be cleared on the record as it is now.
  defp cleared(action, inputs, record, opts) do
    asked = Keyword.get(opts, :cleared, [])

    for name <- clearable(action, inputs, record), name in asked, into: %{} do
      {Atom.to_string(name), nil}
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
        AshDataTable.Resource.Embedding.hidden?(Map.get(record, input.name))
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
  def open_bulk(%Model{} = model, %Action{type: :action} = action, id, opts),
    do: open_generic(model, action, id, opts)

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
  `given` is what the table itself gives the action, and `zone` the time
  zone of the page, in which a datetime was typed (`AshDataTable.Zone`).
  """
  @spec validate(form, [Model.Input.t()], map, map, AshDataTable.Zone.t()) :: form
  def validate(form, inputs, params, given, zone) do
    AshPhoenix.Form.validate(form, taken(inputs, params, given, zone))
  end

  @doc """
  Runs a row action with the inputs a person gave in its panel. The record
  is read again, as the person; the values are taken for the inputs they
  have on the record as it is now.

  Returns what `run/4` returns, but for an action that did not run:
  `{:error, form}`, the form with the action's errors, or
  `{:unchosen, inputs}`, the inputs whose value names a record the person
  could not have chosen (`unchosen/4`).

  `opts` are those of `unchosen/4`, and `:files`: the files the panel's
  uploads hold, by the name of the argument each is for. They are the
  table's to give, as what it gives itself. And `:cleared`: the names of
  the inputs a person asked to empty, which an update action is given
  without a value where they can be (`clearable/3`).
  """
  @spec submit_row(Model.t(), Action.t(), map, map, String.t(), keyword) ::
          {:ok, Ash.Resource.record()}
          | {:done, term}
          | :destroyed
          | :gone
          | {:error, form}
          | {:unchosen, [Model.Input.t()]}
          | {:error, nil, String.t()}
  def submit_row(%Model{} = model, %Action{type: :action} = action, key, params, id, opts) do
    given = Map.merge(files(opts), given(action, key))

    case Record.fetch(model, key, Query.reader_opts(opts)) do
      {:ok, _record} -> submit_generic(model, action, params, given, id, opts)
      :error -> {:error, nil, Text.t(:record_gone)}
    end
  end

  def submit_row(%Model{} = model, %Action{} = action, key, params, id, opts) do
    chooser = opts
    opts = Query.reader_opts(opts)

    case Record.fetch(model, key, opts) do
      {:ok, record} ->
        inputs = inputs(action, record)

        case unchosen(inputs, params, record, chooser) do
          [] ->
            submit(
              model,
              form(record, action, id, opts),
              taken(
                inputs,
                params,
                Map.merge(files(chooser), cleared(action, inputs, record, chooser)),
                model.time_zone
              ),
              opts
            )

          unchosen ->
            {:unchosen, unchosen}
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
          taken(action.inputs, params, given, model.time_zone),
          opts
        )

      unchosen ->
        {:unchosen, unchosen}
    end
  end

  defp files(opts), do: Keyword.get(opts, :files, %{})

  @doc """
  The inputs among `inputs` whose value, in what a panel's form sent, names
  a record this person could not have chosen: an input that is given by
  choosing related records, with a key that is none of a record they may
  read through the picker's read action.

  Left alone are an input that is empty, a key that `record` holds already
  (nil where there is no record: a create, a selection), which nobody
  chose, and a value that is no key at all, which the action says itself.
  What a record holds already is its attribute, for an attribute; for an
  argument that is everything a relationship is to hold, the keys of the
  records that are related now (`related/3`).

  `opts` are those of `AshDataTable.Pick.reader/2`, and `:picked_with`: what the
  picker's read action was given for a key that was chosen there.
  """
  @spec unchosen([Model.Input.t()], map, Ash.Resource.record() | nil, keyword) ::
          [Model.Input.t()]
  def unchosen(inputs, params, record, opts) when is_map(params) do
    for %{editor: editor} = input <- inputs,
        editor in [:reference, :references],
        refused?(input, params[Atom.to_string(input.name)], record, opts),
        do: input
  end

  def unchosen(_inputs, _params, _record, _opts), do: []

  # Whether one of the keys an input was sent names a record the person
  # could not have chosen.
  defp refused?(input, sent, record, opts) do
    case for(
           key <- List.wrap(typed(input, sent, AshDataTable.Zone.utc())),
           is_binary(key) and key != "",
           do: key
         ) do
      [] ->
        false

      keys ->
        held = held(input, record, opts)

        Enum.any?(keys, fn typed ->
          with {:ok, value} when not is_nil(value) <- key(input, typed),
               false <- MapSet.member?(held, Pick.written(value)) do
            Pick.current(input.reference, value, chosen_with(opts, input, typed)) == :error
          else
            _held_or_no_key -> false
          end
        end)
    end
  end

  # What was typed, as a key: as the input's type casts it, and for a list
  # of keys the type of its values.
  defp key(%{type: {{:array, type}, constraints}}, typed),
    do: Ash.Type.cast_input(type, typed, constraints[:items] || [])

  defp key(%{type: {type, constraints}}, typed), do: Ash.Type.cast_input(type, typed, constraints)

  # The keys a record holds already for an input, as they are written.
  defp held(_input, nil, _opts), do: MapSet.new()

  defp held(%{kind: :attribute, name: name}, record, _opts) do
    case Map.get(record, name) do
      nil -> MapSet.new()
      %Ash.ForbiddenField{} -> MapSet.new()
      held -> MapSet.new([Pick.written(held)])
    end
  end

  defp held(%{reference: %{related?: true} = reference}, record, opts) do
    for related <- Pick.related(reference, record, opts),
        {:ok, value} <- [Pick.value(reference, related)],
        into: MapSet.new(),
        do: Pick.written(value)
  end

  defp held(_input, _record, _opts), do: MapSet.new()

  # A key that was chosen in the picker is looked up as it was found there:
  # with what the picker's read action was given then (`:picked_with`: by
  # input, the key as it was written and those arguments; for an input of
  # several keys, those arguments by key). Any other key through the action
  # as it is.
  defp chosen_with(opts, %{name: name}, typed) do
    case Keyword.get(opts, :picked_with, %{}) do
      %{^name => {^typed, arguments}} -> Keyword.put(opts, :arguments, arguments)
      %{^name => %{^typed => arguments}} -> Keyword.put(opts, :arguments, arguments)
      _typed_or_none -> Keyword.delete(opts, :arguments)
    end
  end

  @doc """
  The records that are related now, by input, for the inputs among `inputs`
  that start with them: an argument that is everything a relationship is to
  hold (`reference.related?`). Read as the person, as Ash reads them when
  the action runs (`AshDataTable.Pick.related/3`). `opts` are the options of
  `AshDataTable.Query.read/3` that say who is asking.
  """
  @spec related([Model.Input.t()], Ash.Resource.record(), keyword) ::
          %{optional(atom) => [Ash.Resource.record()]}
  def related(inputs, record, opts) do
    for %{kind: :argument, reference: %{related?: true} = reference} = input <- inputs,
        into: %{},
        do: {input.name, Pick.related(reference, record, opts)}
  end

  @doc """
  What an action is given of what a panel's form sent: the values of
  `inputs`, by name, as they were typed, and no others; a datetime as the
  instant it is in `zone`, the time zone of the page.
  """
  @spec values([Model.Input.t()], map) :: map
  def values(inputs, params), do: values(inputs, params, AshDataTable.Zone.utc())

  @spec values([Model.Input.t()], map, AshDataTable.Zone.t()) :: map
  def values(inputs, params, zone), do: taken(inputs, params, %{}, zone)

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
  # gives itself, which nothing from the browser replaces. A datetime that
  # was typed is a wall time in the page's zone, and given as the instant it
  # is; one the zone does not have is text the action does not take
  # (`AshDataTable.Zone.given/3`), and the panel says why at its field.
  defp taken(inputs, params, given, zone) when is_map(params) do
    for input <- inputs,
        name = Atom.to_string(input.name),
        given?(input, params, name),
        into: %{} do
      {value, _gaps} = AshDataTable.Zone.given(input, typed(input, params[name], zone), zone)
      {name, value}
    end
    |> Map.merge(given)
  end

  defp taken(_inputs, _params, given, _zone), do: given

  @doc """
  Where the inputs of a panel hold a wall time that the time zone of the
  page does not have (`AshDataTable.Zone`), as `errors/4` names the places of
  errors: the input, or the way to a field of a value inside it. Each with
  the message that says so.
  """
  @spec gaps([Model.Input.t()], map, AshDataTable.Zone.t()) :: %{
          optional(atom | [atom | non_neg_integer]) => [String.t()]
        }
  def gaps(inputs, params, zone) when is_map(params) do
    for input <- inputs,
        name = Atom.to_string(input.name),
        given?(input, params, name),
        path <- AshDataTable.Zone.gaps(input, typed(input, params[name], zone), zone),
        into: %{} do
      # at the field of the value, as an error of Ash's about it is; one of
      # the values of an array of datetimes is at the array's field
      place =
        case path |> Enum.reverse() |> Enum.drop_while(&is_integer/1) |> Enum.reverse() do
          [] -> input.name
          way -> [input.name | way]
        end

      {place, [Text.t(:no_such_time, zone: zone)]}
    end
  end

  def gaps(_inputs, _params, _zone), do: %{}

  # A map cell always says what it holds: a group that is not there is no
  # value, and a list without groups is the empty list. So does a union: no
  # kind is no value.
  defp given?(%{editor: editor}, _params, _name) when editor in [:group, :groups, :union],
    do: true

  # A file is never taken from what the form sent: the table gives it, from
  # the upload (`given`).
  defp given?(%{editor: :file}, _params, _name), do: false

  # A sensitive input starts empty whatever the record holds, so an empty
  # one says nothing: it is given only once something is typed into it.
  # Otherwise an action would empty what its panel never showed.
  defp given?(%{sensitive?: true}, params, name),
    do: is_binary(params[name]) and params[name] != ""

  defp given?(_input, params, name), do: is_map_key(params, name)

  @doc """
  What a field of the panel holds, of what its form sent for it.

  A form cannot send a list without values, so the field of an array sends
  one entry of its own before its values (see the panel's `field/1`), which
  is left out here: what remains is the values as they were typed, and the
  empty list when there are none.

  So does the field of an argument that holds the keys of several related
  records, which sends one entry per record that was chosen.

  The field of a map cell sends its inputs by name, with a mark of its own
  (`_present`), and nothing at all while it has no value: what remains is
  the inputs by name, as they were typed, or nil. An array of them sends
  each value under a number of its own, which says their order and nothing
  else: what remains is the list of them. Only what the fields say is
  taken, whatever else was sent.
  """
  @spec typed(map, term) :: term
  def typed(input, sent), do: typed(input, sent, AshDataTable.Zone.utc())

  @spec typed(map, term, AshDataTable.Zone.t()) :: term
  def typed(%{cell_type: :map, fields: [_ | _] = fields}, %{} = sent, zone) do
    for %{name: name} = field <- fields, field.input? or field.key?, reduce: %{} do
      taken ->
        key = Atom.to_string(name)

        cond do
          field.input? -> Map.put(taken, key, inner(field, sent[key], zone))
          # the key of an embedded resource, as it came: Ash matches by it
          is_binary(sent[key]) and sent[key] != "" -> Map.put(taken, key, sent[key])
          true -> taken
        end
    end
  end

  def typed(%{cell_type: :map, fields: [_ | _]}, _nothing, _zone), do: nil

  def typed(%{cell_type: {:array, :map}, fields: [_ | _]} = field, %{} = sent, zone),
    do: for({_key, item} <- items(sent), do: typed(%{field | cell_type: :map}, item, zone))

  def typed(%{cell_type: {:array, :map}, fields: [_ | _]}, _nothing, _zone), do: []

  # The field of a union sends the kind and that kind's value. What remains
  # is the two as Ash takes them from outside (`Ash.Type.Union.cast_input/2`):
  # the kind by its name, and the value as its own field gives it. No kind
  # is no value.
  def typed(%{cell_type: :union, members: [_ | _]} = field, sent, zone) do
    case kind(field, sent, zone) do
      nil ->
        nil

      {member, held} ->
        %{
          "_union_type" => Atom.to_string(member.name),
          "_union_value" => member |> inner(held, zone) |> tagged(member)
        }
    end
  end

  def typed(%{cell_type: {:array, _item}}, [_own | values], _zone), do: values
  # the keys of the records that were chosen: sent as an array is
  def typed(%{editor: :references}, [_own | values], _zone),
    do: Enum.filter(values, &is_binary/1)

  def typed(%{editor: :references}, _nothing, _zone), do: []
  def typed(_input, typed, _zone), do: typed

  @doc """
  The kind a union's field holds, of what its form sent for it, and what it
  holds for that kind, as the kind's own field sends it. Nil for no kind,
  and for one the union does not have.

  The field says which kind its value was given for (`_of`). A value that
  was given for another kind is not this kind's: the person has just chosen
  this one, and it starts as a new value of it does (`fresh/1`).
  """
  @spec kind(map, term) :: {Model.Field.t(), term} | nil
  def kind(field, sent), do: kind(field, sent, AshDataTable.Zone.utc())

  @spec kind(map, term, AshDataTable.Zone.t()) :: {Model.Field.t(), term} | nil
  def kind(%{members: [_ | _] = members}, %{"_union_type" => named} = sent, zone)
      when is_binary(named) do
    with %{} = member <- Enum.find(members, &(Atom.to_string(&1.name) == named)) do
      held = if Map.get(sent, "_of", named) == named, do: sent["_union_value"]
      {member, if(is_nil(held), do: fresh(member, zone), else: held)}
    end
  end

  def kind(_field, _sent, _zone), do: nil

  @doc "What the field of a kind of a union sends for a new value of that kind."
  @spec fresh(map, AshDataTable.Zone.t()) :: term
  def fresh(%{cell_type: :map, fields: [_ | _]} = member, zone), do: blank(member, zone)
  def fresh(_member, _zone), do: ""

  # A union that tells its kinds apart by a key of the value is given that
  # key with the value: it is the kind's, not the person's to type.
  defp tagged(%{} = value, %{tag: {key, held}}) when not is_nil(held),
    do: Map.put(value, to_string(key), held)

  defp tagged(value, _member), do: value

  # A field of a map cell always sends something: nothing is the value it
  # has when it is empty.
  defp inner(%{cell_type: cell_type} = field, sent, zone)
       when cell_type in [:map, {:array, :map}, :union],
       do: typed(field, sent, zone)

  defp inner(%{cell_type: {:array, _item}} = field, sent, zone) when is_list(sent),
    do: typed(field, sent, zone)

  defp inner(%{cell_type: {:array, _item}}, _nothing, _zone), do: []
  defp inner(%{cell_type: :boolean}, sent, _zone), do: to_string(sent == "true")
  defp inner(_field, sent, _zone) when is_binary(sent), do: sent
  defp inner(_field, _nothing, _zone), do: ""

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
  `typed/3`. `held` is the value as its editor holds it
  (`AshDataTable.Typed.of/3`). It is what the field starts with.
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

  # A union: the kind, which kind the value is of, and the value as that
  # kind's field sends it. Without a value it sends that it has no kind.
  def sent(%{cell_type: :union, members: [_ | _] = members}, %{"_union_type" => named} = held) do
    case Enum.find(members, &(Atom.to_string(&1.name) == named)) do
      nil ->
        %{"_union_type" => "", "_of" => ""}

      member ->
        %{
          "_union_type" => named,
          "_of" => named,
          "_union_value" => sent(member, held["_union_value"])
        }
    end
  end

  def sent(%{cell_type: :union, members: [_ | _]}, _nothing),
    do: %{"_union_type" => "", "_of" => ""}

  def sent(%{cell_type: {:array, _item}}, held), do: ["" | List.wrap(held)]
  def sent(_field, nil), do: ""
  def sent(_field, held), do: held

  @doc """
  What the field of a map cell sends for a new value: its inputs empty, but
  for those that have a default, and a value inside it that cannot be left
  out started the same way.
  """
  @spec blank(map) :: map
  def blank(field), do: blank(field, AshDataTable.Zone.utc())

  @spec blank(map, AshDataTable.Zone.t()) :: map
  def blank(%{fields: fields}, zone) do
    for %{name: name, input?: true} = field <- fields, into: %{"_present" => ""} do
      started =
        cond do
          not is_nil(field.default) ->
            sent(field, Typed.of(field, field.default, zone))

          field.cell_type == :map and field.required? and is_list(field.fields) ->
            blank(field, zone)

          true ->
            sent(field, Typed.of(field, nil, zone))
        end

      {Atom.to_string(name), started}
    end
  end

  @doc """
  Whether what the field of a map cell sent is what the cell holds already:
  `value` as the record has it. Compared as the field itself would send
  the value, in `zone`, the time zone of the page.
  """
  @spec unchanged?(map, term, term) :: boolean
  def unchanged?(input, sent, value), do: unchanged?(input, sent, value, AshDataTable.Zone.utc())

  @spec unchanged?(map, term, term, AshDataTable.Zone.t()) :: boolean
  def unchanged?(input, sent, value, zone),
    do:
      typed(input, sent, zone) ==
        typed(input, sent(input, Typed.of(input, value, zone)), zone)

  @doc """
  What a form's errors say to a person: by input, for the errors about one
  of `inputs`, and under `nil` for the others. An error about a field of a
  value inside the record (a field of a map cell) is under the way to that
  field: the input, the places of values in an array, and the fields on the
  way (`[:client, :address, :city]`, `[:milestones, 1, :title]`). What Ash
  says of a record that an argument hands to a relationship, without a text
  of its own, is under that argument: that the record is not available.
  See `AshDataTable.Errors` for what is shown of an error; `refusal` is what a
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

    grouped =
      Enum.group_by(
        at_fields ++ nested ++ managed(form, inputs) ++ without_field,
        &elem(&1, 0),
        &elem(&1, 1)
      )

    Map.new(grouped, fn {field, messages} -> {field, Enum.uniq(messages)} end)
  end

  # What Ash says of a record an argument hands to a relationship, where it
  # says it without a message for a person: at the field of that argument.
  # Ash puts such an error under the argument's name and the place of the
  # record in what was given (`path: [:labels, 0]`: the change gives the
  # argument as the `meta[:id]` of what it manages), and the commonest of
  # them has no text of its own: the record a key names was not found, by
  # an action that looks it up to relate it, or among the related records
  # by one that takes it away. The panel would otherwise stay open and say
  # nothing.
  defp managed(form, inputs) do
    for %{class: :invalid, path: [name | _rest]} = error <- AshPhoenix.Form.raw_errors(form),
        is_atom(name),
        not Errors.about_field?(error),
        is_nil(Errors.without_field(error)),
        %{} = input <-
          [
            Enum.find(
              inputs,
              &(&1.kind == :argument and is_map(&1.reference) and &1.name == name)
            )
          ] do
      text =
        case error do
          %Ash.Error.Query.NotFound{} -> Text.t(:record_gone)
          _nothing_to_say -> Text.t(:action_failed)
        end

      {input.name, text}
    end
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
    with %{} = input <-
           Enum.find(inputs, &(&1.name == name and &1.editor in [:group, :groups, :union])) do
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

        Enum.any?(fields_at(at), &(&1.name == field and &1.input?)) ->
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
  defp inside(at, name) do
    for %{cell_type: cell_type, input?: true} = inner <- fields_at(at),
        cell_type in [:map, :union],
        fields_at(inner) != [],
        way <-
          if(Enum.any?(fields_at(inner), &(&1.name == name and &1.input?)),
            do: [[name]],
            else: []
          ) ++
            inside(inner, name),
        do: [inner.name | way]
  end

  # The fields a value has where the panel shows it: those of a map cell,
  # and for a union those of its kinds that are made of fields. Ash does not
  # say which kind an error is about; the panel shows one kind at a time,
  # and a field of it is found by its name.
  defp fields_at(%{cell_type: :union, members: members}),
    do: Enum.flat_map(members || [], &(&1.fields || []))

  defp fields_at(%{fields: fields}), do: fields || []
  defp fields_at(_other), do: []

  # the errors of an input as a whole are under its name
  defp single([name]), do: name
  defp single(place), do: place

  # The message of an error about a field the panel has no place for, after
  # the field's name in words.
  defp named(field, error) do
    Text.t(:error_on_field,
      field: Text.label(AshDataTable.Resource.Words.humanize(field)),
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

    case not listed? &&
           Enum.find(
             fields_at(at),
             &(&1.name == name and (is_list(&1.fields) or is_list(&1.members)))
           ) do
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
