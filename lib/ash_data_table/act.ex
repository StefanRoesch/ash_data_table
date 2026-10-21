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
  # What a panel's form gives an action, and the rules it is given by (a
  # map cell, a union, a sensitive input, a file, a key of a related record,
  # the fields asked to be emptied), are the panel's
  # (`AshDataTable.Panel.values/4`, `unchosen/4`, `cleared/4`): this module
  # asks it where it runs an action with what a form sent, and keeps every
  # call of AshPhoenix and Ash. A key from the browser is a claim like any
  # other: one that names nothing the person could have chosen runs nothing.
  #
  # A generic action is given no record: it is run through the same form
  # (`AshPhoenix.Form.for_action/3`, which builds an `Ash.ActionInput` and
  # runs it with `Ash.run_action/2`), with the values of its arguments. One
  # that is a row action (`record_argument`) is given the primary key of its
  # row as that argument, by the table: the record is read first, as the
  # person, as for any row action, and the key is the one the table holds,
  # never one the browser sent. What such an action returns is no row: the
  # table says it (`AshDataTable.Format.said/3`) and reads again.

  require Logger

  alias AshDataTable.Errors
  alias AshDataTable.Model
  alias AshDataTable.Model.Action
  alias AshDataTable.Panel
  alias AshDataTable.Pick
  alias AshDataTable.Query
  alias AshDataTable.Record

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
          | {:error, Ash.Resource.record() | nil, Errors.message()}

  @doc """
  Runs a row action straight away, without inputs, on the record with the
  primary key `key`. Takes the options of `AshDataTable.Query.read/3` that say
  who is asking.
  """
  @spec run(Model.t(), Action.t(), map, keyword) :: result
  def run(%Model{} = model, %Action{type: :action} = action, key, opts) when is_map(key) do
    case Record.fetch(model, key, opts) do
      {:ok, record} ->
        case run_generic(model, action, given(action, key), opts) do
          {:done, value} ->
            {:done, value}

          {:error, message} ->
            case Record.load(model, record, opts) do
              {:ok, record} -> {:error, record, message}
              :error -> {:error, nil, message}
            end
        end

      :error ->
        {:error, nil, {:text, :record_gone, []}}
    end
  end

  def run(%Model{} = model, %Action{} = action, key, opts) when is_map(key) do
    given = from_page(action, opts)

    case Record.fetch(model, key, opts) do
      {:ok, record} ->
        case submit(model, form(record, action, "action", opts), given, opts) do
          {:error, form} ->
            message = Errors.joined(messages(form, model))

            case Record.load(model, record, opts) do
              {:ok, record} -> {:error, record, message}
              :error -> {:error, nil, message}
            end

          ran ->
            ran
        end

      :error ->
        {:error, nil, {:text, :record_gone, []}}
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
    with {:ok, record} <- Record.fetch(model, key, opts) do
      {:ok, record, open_generic(model, action, id, opts), action.inputs}
    end
  end

  def open(%Model{} = model, %Action{} = action, key, id, opts) when is_map(key) do
    from_page(action, opts)

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
  def open_generic(
        %Model{resource: resource},
        %Action{type: :action, name: name} = action,
        id,
        opts
      ) do
    from_page(action, opts)

    AshPhoenix.Form.for_action(
      resource,
      name,
      form_opts(id) ++ Query.action_opts(opts, resource, name)
    )
  end

  @doc """
  What the page gives an action itself: the arguments its declaration says
  the page fills (`page_argument`), by name, with the values of the page's
  `page_arguments` (the `page_values` of `opts`). Nothing from the
  browser replaces them. Raises for one the page gives no value, when the
  action opens and when it runs: that is a mistake of the page's.
  """
  @spec from_page(Action.t(), keyword) :: map
  def from_page(%Action{page_arguments: []}, _opts), do: %{}

  def from_page(%Action{page_arguments: names} = action, opts) do
    given =
      case opts[:page_values] do
        %{page_arguments: %{} = given} -> given
        _nothing -> %{}
      end

    for name <- names, into: %{} do
      case Query.given(given, name) do
        {:ok, value} ->
          {Atom.to_string(name), value}

        :error ->
          raise ArgumentError,
                "the action `#{action.name}` of the table takes its argument `#{name}` from the " <>
                  "page (`page_argument :#{name}`), but the page's `page_arguments` give it no " <>
                  "value. Give one: `page_arguments: %{#{name}: ...}`, or a function that " <>
                  "returns such a map."
      end
    end
  end

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
  @spec run_generic(Model.t(), Action.t(), map, keyword) ::
          {:done, term} | {:error, Errors.message()}
  def run_generic(%Model{} = model, %Action{type: :action} = action, given, opts)
      when is_map(given) do
    case submit_generic(model, action, %{}, given, "action", opts) do
      {:done, value} -> {:done, value}
      {:error, %AshPhoenix.Form{} = form} -> {:error, Errors.joined(messages(form, model))}
      {:error, nil, message} -> {:error, message}
    end
  end

  @doc """
  Runs a generic action with the inputs a person gave in its panel, and
  with `given`, what the table itself gives it.

  Returns `{:done, value}`, `{:error, form}` with the action's errors,
  `{:unchosen, inputs}` as `submit_row/6` does (`opts` are then those of
  `AshDataTable.Panel.unchosen/4`), or
  `{:error, nil, message}` for a failure that is not of the action's
  saying: Ash raises what goes wrong inside a generic action, where it
  returns it for the others. That is for whoever runs the application, in
  the log.
  """
  @spec submit_generic(Model.t(), Action.t(), map, map, String.t(), keyword) ::
          {:done, term}
          | {:error, form}
          | {:unchosen, [Model.Input.t()]}
          | {:error, nil, Errors.message()}
  def submit_generic(%Model{} = model, %Action{type: :action} = action, params, given, id, opts) do
    # an argument whose records are chosen (`reference` in the block) holds
    # keys, and a key from the browser is a claim, as for any other action
    case Panel.unchosen(action.inputs, params, nil, opts) do
      [] ->
        form = open_generic(model, action, id, opts)
        given = Map.merge(given, from_page(action, opts))

        case AshPhoenix.Form.submit(form,
               params: Panel.values(action.inputs, params, given, model.time_zone)
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

      {:error, nil, {:text, :action_failed, []}}
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

    from_page(action, opts)
    form(blank, action, id, opts)
  end

  @doc "The form of the table's create action. `id` is the id of the form."
  @spec open_create(Model.t(), Action.t(), String.t(), keyword) :: form
  def open_create(%Model{} = model, %Action{type: :create} = action, id, opts) do
    AshPhoenix.Form.for_create(
      model.resource,
      action.name,
      form_opts(id) ++ Query.action_opts(opts, model.resource, action.name)
    )
  end

  @doc """
  The form with what the person has typed so far, as the action sees it:
  `AshPhoenix.Form.validate/3`, with `params` what the panel's form gives
  the action (`AshDataTable.Panel.values/4`).
  """
  @spec validate(form, map) :: form
  def validate(form, params), do: AshPhoenix.Form.validate(form, params)

  @doc """
  Runs a row action with the inputs a person gave in its panel. The record
  is read again, as the person; the values are taken for the inputs they
  have on the record as it is now.

  Returns what `run/4` returns, but for an action that did not run:
  `{:error, form}`, the form with the action's errors, or
  `{:unchosen, inputs}`, the inputs whose value names a record the person
  could not have chosen (`AshDataTable.Panel.unchosen/4`).

  `opts` are those of `AshDataTable.Panel.unchosen/4`, and `:files`: the files the panel's
  uploads hold, by the name of the argument each is for. They are the
  table's to give, as what it gives itself. And `:cleared`: the names of
  the inputs a person asked to empty, which an update action is given
  without a value where they can be (`AshDataTable.Panel.cleared/4`).
  """
  @spec submit_row(Model.t(), Action.t(), map, map, String.t(), keyword) ::
          {:ok, Ash.Resource.record()}
          | {:done, term}
          | :destroyed
          | :gone
          | {:error, form}
          | {:unchosen, [Model.Input.t()]}
          | {:error, nil, Errors.message()}
  def submit_row(%Model{} = model, %Action{type: :action} = action, key, params, id, opts) do
    given = Map.merge(files(opts), given(action, key))

    case Record.fetch(model, key, opts) do
      {:ok, _record} -> submit_generic(model, action, params, given, id, opts)
      :error -> {:error, nil, {:text, :record_gone, []}}
    end
  end

  def submit_row(%Model{} = model, %Action{} = action, key, params, id, opts) do
    case Record.fetch(model, key, opts) do
      {:ok, record} ->
        inputs = inputs(action, record)

        case Panel.unchosen(inputs, params, record, opts) do
          [] ->
            given =
              files(opts)
              |> Map.merge(Panel.cleared(action, inputs, record, Keyword.get(opts, :cleared, [])))
              |> Map.merge(from_page(action, opts))

            submit(
              model,
              form(record, action, id, opts),
              Panel.values(inputs, params, given, model.time_zone),
              opts
            )

          unchosen ->
            {:unchosen, unchosen}
        end

      :error ->
        {:error, nil, {:text, :record_gone, []}}
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
    case Panel.unchosen(action.inputs, params, nil, opts) do
      [] ->
        submit(
          model,
          open_create(model, action, id, opts),
          Panel.values(action.inputs, params, given, model.time_zone),
          opts
        )

      unchosen ->
        {:unchosen, unchosen}
    end
  end

  defp files(opts), do: Keyword.get(opts, :files, %{})

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

  defp submit(model, form, params, opts) do
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

  defp form(%resource{} = record, %Action{type: :update, name: name}, id, opts),
    do:
      AshPhoenix.Form.for_update(
        record,
        name,
        form_opts(id) ++ Query.action_opts(opts, resource, name)
      )

  defp form(%resource{} = record, %Action{type: :destroy, name: name}, id, opts),
    do:
      AshPhoenix.Form.for_destroy(
        record,
        name,
        form_opts(id) ++ Query.action_opts(opts, resource, name)
      )

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

  # Everything a form's errors say, as the messages of an action that failed.
  defp messages(form, %Model{} = model) do
    case Errors.of_form(form, model, nil, {:text, :action_not_allowed, []}) do
      [] -> [{:text, :action_failed, []}]
      messages -> messages
    end
  end
end
