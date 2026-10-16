defmodule AshDataTable.Operation do
  @moduledoc false
  # The one way a table writes (target.md 4.3, stage 3b). Each write is one
  # function, given one input value (`Operation.Input`), and each runs the
  # same steps in the same order:
  #
  #   1. the table's own checks: what the browser named (a row, a column, an
  #      action, a selection) is a claim, and is looked up in the model and
  #      among the rows of the page. A claim the model does not allow is
  #      refused, and nothing is said (`:refused`);
  #   2. the veto: the page's `before_action`, asked after the checks with
  #      what they found (`AshDataTable.Request`). It can only halt
  #      (`{:halted, message}`);
  #   3. the files of the panel, which LiveView holds while the action runs
  #      (`with_files`);
  #   4. the record read again, as the person, and the action run with what
  #      the page gives it (`page_values`: its context, private arguments and
  #      page arguments; `AshDataTable.Act`, `AshDataTable.Edit`,
  #      `AshDataTable.Bulk`, which read through `AshDataTable.Record`,
  #      `AshDataTable.Pick` and `AshDataTable.Query`).
  #
  # What came of it is an outcome (`Operation.Outcome`) or a failure
  # (`Operation.Failure`), its messages as terms. A record in an outcome is
  # never drawn as it is: the live layer puts it into the stream through
  # `AshDataTable.Present`. `reveal/1` is the one way to a sensitive value:
  # one cell, read again as the person.
  #
  # It runs in the LiveView's process, but for a run on a selection, which
  # it hands back to be started beside it (`{:start, run, files}`). A raise
  # in a write ends the LiveView as before, but in a generic action and a
  # run on a selection, which are rescued where they run (D10).

  alias AshDataTable.Act
  alias AshDataTable.Bulk
  alias AshDataTable.Edit
  alias AshDataTable.Errors
  alias AshDataTable.Event
  alias AshDataTable.Model
  alias AshDataTable.Query
  alias AshDataTable.Record
  alias AshDataTable.Request

  defmodule Input do
    @moduledoc false
    # What a write is given:
    #
    #   * `intent` what was asked (`AshDataTable.Intent`), names still text.
    #     A reference cell's choice is `{:refer, row, column, named,
    #     confirmed?, arguments}`: the live layer makes it of `picked` and
    #     the picker it opened, whose column is its own to name;
    #   * `model` the person's model, `state` the page's (a run on "all that
    #     match" reads under its filters), `parent` for a nested table the
    #     row it belongs to (`key`, `authorize?`, `arguments` of the table
    #     around it), else nil;
    #   * `opts` who asks (`AshDataTable.Caller.reader_opts/1`, and the
    #     table's listener as `origin`), and `picking` what a picker's read
    #     is told besides (`authorize_given`);
    #   * `rows` the rows of the page by the key in their DOM id, each with
    #     its primary key: what a row event names is looked up there;
    #   * `panel` the open action panel as the live layer keeps it (its
    #     form, inputs, what the table gives its action, the fields asked to
    #     be emptied, the records chosen), nil for none;
    #   * `read?` whether the table has read: a table that could not read
    #     offers no table action and no "all that match"; `offered` the
    #     table actions and the actions on a selection this person is
    #     offered now (none on a selection while a run is on its way);
    #   * `with_files` runs a function with the files of the panel's
    #     uploads, by argument name, while LiveView holds them; for a run on
    #     a selection, with copies the run outlasts the event with;
    #   * `veto` asks the page before a write: a function of the
    #     `AshDataTable.Request`, which the live layer makes of the page's
    #     `before_action`, and which answers `:cont` or `{:halt, message}`;
    #     `page_values` what the page gives every call to Ash
    #     (`AshDataTable.Query.page_values/0`): `context`, private arguments
    #     and page arguments. The live layer gives both; the defaults, which
    #     never halt and give nothing, are for a write without a page.
    defstruct [
      :intent,
      :model,
      :state,
      parent: nil,
      opts: [],
      picking: [],
      rows: %{},
      panel: nil,
      read?: false,
      offered: %{table: [], bulk: []},
      with_files: &__MODULE__.without_files/1,
      veto: &__MODULE__.cont/1,
      page_values: %{context: %{}, private_arguments: %{}, page_arguments: %{}}
    ]

    @type t :: %__MODULE__{}

    @doc false
    def without_files(run), do: run.(%{})

    @doc false
    def cont(_request), do: :cont
  end

  defmodule Outcome do
    @moduledoc false
    # A write that was done: the `record` as the action returned it, with
    # what the columns show loaded (nil for a generic action); `value` what
    # a generic action returned; `gone?` for a record that was destroyed,
    # or that is not the person's to read any more. `event` is what the
    # page is told of it (`AshDataTable.Event`), when it asks.
    defstruct record: nil, value: nil, gone?: false, event: nil

    @type t :: %__MODULE__{}
  end

  defmodule Failure do
    @moduledoc false
    # A write that was not done: the `record` as it is now (nil when it is
    # gone, or not the person's to read), the `message` the person is told,
    # the `places` of the values of an array it is about, the `form` with
    # the action's errors at its fields, the inputs (or the reference cell)
    # whose chosen record is not there any more (`unchosen`), the record
    # that was `chosen` for a reference cell, and what the table `given`
    # the action itself, as it was read again (a create in a nested table).
    defstruct record: nil,
              message: nil,
              places: [],
              form: nil,
              unchosen: [],
              chosen: nil,
              given: nil

    @type t :: %__MODULE__{}
  end

  @type result ::
          {:ok, Outcome.t()}
          | {:ask, Errors.message() | String.t()}
          | {:halted, Errors.message()}
          | {:error, Failure.t()}
          | :refused

  @gone {:text, :record_gone, []}

  @doc "Saves what was typed into a cell."
  @spec save(Input.t()) :: result
  def save(%Input{intent: {:save, key, name, typed}} = input) do
    with %{editable?: true} = column <- column(input.model, name),
         true <- Edit.typed?(column, typed),
         %{} = row <- input.rows[key],
         :cont <- asked(input, :cell, column, row) do
      input.model
      |> Edit.save(column, row.pk, typed, opts(input))
      |> edited()
      |> event(&Event.saved(input.model, column, row.pk, &1.record))
    else
      halted -> halted(halted)
    end
  end

  @doc "Empties a sensitive cell: no empty editor does."
  @spec clear(Input.t()) :: result
  def clear(%Input{intent: {:clear, key, name}} = input) do
    with %{editable?: true} = column <- column(input.model, name),
         true <- Edit.clearable?(column),
         %{} = row <- input.rows[key],
         :cont <- asked(input, :clear, column, row) do
      input.model
      |> Edit.clear(column, row.pk, opts(input))
      |> edited()
      |> event(&Event.saved(input.model, column, row.pk, &1.record))
    else
      halted -> halted(halted)
    end
  end

  @doc """
  The record chosen for a reference cell. A column with a question is
  asked first whether the choice changes the row at all (`{:ask,
  question}`), unless the person has answered it.
  """
  @spec refer(Input.t()) :: result
  def refer(%Input{intent: {:refer, key, name, named, confirmed?, arguments}} = input) do
    with %{editable?: true, kind: :reference} = column <-
           Enum.find(input.model.columns, &(&1.name == name)),
         %{} = row <- input.rows[key],
         :cont <- asked(input, :reference, column, row) do
      opts =
        [ask?: not is_nil(column.confirm) and not confirmed?, arguments: arguments] ++
          input.picking ++ opts(input)

      case Edit.refer(input.model, column, row.pk, named, opts) do
        :changed ->
          {:ask, column.confirm}

        :unavailable ->
          {:error, %Failure{message: @gone, unchosen: [column]}}

        {:ok, record} ->
          {:ok, %Outcome{record: record}}
          |> event(&Event.saved(input.model, column, row.pk, &1.record))

        {:error, %_{} = record, message, chosen} ->
          failed(record, message, chosen: chosen)

        {:error, nil, message} ->
          failed(nil, message)
      end
    else
      halted -> halted(halted)
    end
  end

  @doc """
  The value of one sensitive cell, of the record as it is read now, for
  this person: `{:ok, value}`, `:hidden` where Ash hides it from them on
  this record, `{:error, message}` for a record that is gone. Nothing else
  gives a sensitive value. Only a cell of a sensitive column of a row of
  the page.
  """
  @spec reveal(Input.t()) :: {:ok, term} | :hidden | {:error, Errors.message()} | :refused
  def reveal(%Input{intent: {:reveal, key, name}, model: model} = input) do
    with %{sensitive?: true} = column <- column(model, name),
         %{} = row <- input.rows[key] do
      opts = opts(input)

      with {:ok, record} <- Record.fetch(model, row.pk, opts),
           {:ok, record} <- with_column(model, column, record, opts) do
        case Model.Column.value(column, record) do
          %Ash.ForbiddenField{} -> :hidden
          value -> {:ok, value}
        end
      else
        _gone_or_refused -> {:error, @gone}
      end
    else
      _not_a_cell -> :refused
    end
  end

  # A calculation or an aggregate is loaded onto the record as the rows of a
  # page have it, through the table's read action.
  defp with_column(_model, %{kind: :attribute}, record, _opts), do: {:ok, record}

  defp with_column(model, column, record, opts),
    do: Query.load(record, %{model | columns: [column]}, [action: model.read_action] ++ opts)

  @doc """
  Runs an action that has no panel: a row action (`act`), and a table
  action (`table_act` for one without a question, `table_run` once its
  question is answered).
  """
  @spec run(Input.t()) :: result
  def run(%Input{intent: {:act, key, name}} = input) do
    with %Model.Action{panel?: false} = action <- action(input.model.actions, name),
         %{} = row <- input.rows[key],
         :cont <- asked(input, :row, action, key: row.pk) do
      input.model
      |> Act.run(action, row.pk, opts(input))
      |> ran()
      |> event(&Event.ran(input.model, action, row.pk, Act.from_page(action, opts(input)), &1))
    else
      halted -> halted(halted)
    end
  end

  def run(%Input{intent: {event, name}} = input) when event in [:table_act, :table_run] do
    with %Model.Action{panel?: false} = action <- table_action(input, name),
         true <- event == :table_run or is_nil(action.confirm),
         :cont <- asked(input, :table, action) do
      input.model
      |> Act.run_generic(action, %{}, opts(input))
      |> ran()
      |> event(&Event.ran(input.model, action, nil, Act.from_page(action, opts(input)), &1))
    else
      halted -> halted(halted)
    end
  end

  @doc """
  Runs the action of the open panel with what its form sent: the save of a
  map cell, a row action, a table action, a create, and an action on a
  selection, which is handed back to be started (`{:start, run, files}`).
  """
  @spec submit(Input.t()) :: result | {:start, (-> Bulk.outcome()), map}
  def submit(%Input{intent: {:panel_submit, params}, panel: %{} = panel} = input),
    do: submit(panel.kind, panel, params, input)

  def submit(%Input{}), do: :refused

  defp submit(:cell, %{key: key, column: name, inputs: [field]} = panel, params, input) do
    with %{} = column <-
           Enum.find(
             input.model.columns,
             &(&1.name == name and &1.editable? and Model.group?(&1))
           ),
         %{} = row <- input.rows[key],
         :cont <- asked(input, :map_cell, column, row) do
      input.with_files.(fn _files ->
        case Edit.put(input.model, column, field, row.pk, params, panel.form.id, opts(input)) do
          {:ok, record} ->
            event(
              {:ok, %Outcome{record: record}},
              &Event.saved(input.model, column, row.pk, &1.record)
            )

          {:error, %AshPhoenix.Form{} = form} ->
            {:error, %Failure{form: form}}

          {:error, nil, message} ->
            failed(nil, message)
        end
      end)
    else
      halted -> halted(halted)
    end
  end

  defp submit(:row, %{key: key, action: action} = panel, params, input) do
    with %{} = row <- input.rows[key],
         :cont <- asked(input, :row, action, key: row.pk) do
      input.with_files.(fn files ->
        opts = [files: files, cleared: MapSet.to_list(panel.cleared)] ++ chooser(input)

        input.model
        |> Act.submit_row(action, row.pk, params, panel.form.id, opts)
        |> ran()
        |> event(
          &Event.ran(input.model, action, row.pk, given(input, action, panel, params, files), &1)
        )
      end)
    else
      halted -> halted(halted)
    end
  end

  defp submit(:table, %{action: action} = panel, params, input) do
    with %Model.Action{} = action <- table_action(input, Atom.to_string(action.name)),
         :cont <- asked(input, :table, action) do
      input.with_files.(fn files ->
        input.model
        |> Act.submit_generic(action, params, files, panel.form.id, chooser(input))
        |> ran()
        |> event(
          &Event.ran(input.model, action, nil, given(input, action, panel, params, files), &1)
        )
      end)
    else
      halted -> halted(halted)
    end
  end

  # In a nested table the new record is joined to the row the table belongs
  # to: by that row's own value, read again now, as the person. Nothing the
  # form sends can say otherwise.
  defp submit(:create, %{action: action} = panel, params, input) do
    case asked(input, :create, action) do
      :cont ->
        input.with_files.(fn files ->
          case link(input, action) do
            {:ok, given} ->
              input.model
              |> Act.submit_create(
                action,
                params,
                Map.merge(files, given),
                panel.form.id,
                chooser(input)
              )
              |> created(given)
              |> event(
                &Event.ran(
                  input.model,
                  action,
                  nil,
                  given(input, action, panel, params, files),
                  &1
                )
              )

            :error ->
              failed(nil, @gone)
          end
        end)

      halted ->
        halted(halted)
    end
  end

  # What the action makes of a value as such is known without a record, and
  # is said at its field with the panel left open. Everything else an
  # action says depends on the record, and is said when it has run.
  defp submit(:bulk, %{action: action, selection: selection} = panel, params, input) do
    case asked(input, :bulk, action, selection: selected(selection)) do
      :cont ->
        input.with_files.(fn files ->
          form = Act.validate(panel.form, panel.inputs, params, files, panel.time_zone)
          errors = Act.errors(form, input.model, panel.inputs)
          chosen = Act.unchosen(panel.inputs, params, nil, chooser(input))

          cond do
            # at a field of the panel, or at a field of a value inside one
            Enum.any?(Map.keys(errors), &(not is_nil(&1))) ->
              {:error, %Failure{form: form}}

            chosen != [] ->
              {:error, %Failure{form: form, unchosen: chosen}}

            true ->
              given = Map.merge(Act.values(panel.inputs, params, panel.time_zone), files)
              start(input, action, selection, given, files)
          end
        end)

      halted ->
        halted(halted)
    end
  end

  @doc """
  Runs an action without a panel on a selection, once the person has
  answered its question: handed back to be started beside the LiveView,
  as a run takes as long as its records are many.
  """
  @spec bulk(Input.t()) :: {:start, (-> Bulk.outcome()), map} | {:halted, term} | :refused
  def bulk(%Input{intent: {:bulk_run, name, selection}} = input) do
    with {:ok, %Model.Action{panel?: false} = action, selection} <-
           bulk_action(input, name, selection),
         :cont <- asked(input, :bulk, action, selection: selected(selection)) do
      start(input, action, selection, %{}, %{})
    else
      halted -> halted(halted)
    end
  end

  # The rows are not looked up among those of the page, as a selection
  # outlives its page: they are claims, and the run reads each as the
  # person before anything is done to it (`AshDataTable.Bulk`).
  defp start(input, action, selection, given, files) do
    parent = input.parent || %{key: nil, authorize?: true, arguments: %{}}

    opts =
      [
        state: input.state,
        parent_key: parent.key,
        parent_authorize?: parent.authorize?,
        parent_arguments: parent.arguments
      ] ++ opts(input)

    model = input.model
    told = Map.merge(given, Act.from_page(action, opts))

    run = fn ->
      outcome = Bulk.run(model, action, selection, given, opts)
      Map.put(outcome, :event, Event.bulk(model, action, selection, told, outcome))
    end

    {:start, run, files}
  end

  @doc """
  What a nested table gives its create action: the field that joins the
  new record to the row the table belongs to, with that row's value. The
  row is read for it, as the person and through the read action of the
  table that shows it, with that table's arguments, and with authorization
  when either table authorizes: a key proves nothing. A table of its own
  gives nothing. `:error` for a row that is gone, or not the person's. The
  create panel asks it as it opens, and the create asks it again.
  """
  @spec link(Input.t(), Model.Action.t()) :: {:ok, map} | :error
  def link(_input, %Model.Action{link: nil}), do: {:ok, %{}}

  def link(%Input{parent: %{} = parent} = input, %Model.Action{link: {source, dest}}) do
    via = input.model.via

    opts =
      input
      |> opts()
      |> Keyword.update(:authorize?, true, &(&1 or parent.authorize?))

    case Query.get(via.source, via.source_read_action, parent.key, parent.arguments, opts) do
      {:ok, %_{} = row} ->
        case Map.get(row, source) do
          hidden when is_struct(hidden, Ash.ForbiddenField) or is_nil(hidden) -> :error
          value -> {:ok, %{Atom.to_string(dest) => value}}
        end

      _gone_or_refused ->
        :error
    end
  end

  def link(_input, _action), do: :error

  # Who reads what a picker reads, for the keys a panel holds: with what the
  # picker's read action was given when each was chosen.
  defp chooser(%Input{panel: panel} = input),
    do: [picked_with: panel.picked_with] ++ input.picking ++ opts(input)

  # Who asks, with what the page gives every call to Ash.
  defp opts(%Input{} = input), do: Keyword.put(input.opts, :page_values, input.page_values)

  # Asks the veto, with what the checks found: the action, and the column,
  # row or selection it is asked for.
  defp asked(input, from, %Model.Column{} = column, row) do
    veto(input, %Request{
      resource: input.model.resource,
      action: column.update_action,
      type: :update,
      from: from,
      column: column.name,
      key: row.pk
    })
  end

  defp asked(input, from, %Model.Action{} = action, more) do
    veto(
      input,
      struct!(
        %Request{
          resource: input.model.resource,
          action: action.name,
          type: action.type,
          from: from
        },
        more
      )
    )
  end

  defp asked(input, from, %Model.Action{} = action), do: asked(input, from, action, [])

  defp veto(input, %Request{} = request), do: input.veto.(request)

  defp selected(:all), do: :all
  defp selected({:rows, rows}), do: rows

  # What the page is told of a write that was done.
  defp event({:ok, %Outcome{} = outcome}, event), do: {:ok, %{outcome | event: event.(outcome)}}
  defp event(result, _event), do: result

  # What an action of a panel was given: what its form sent for the inputs,
  # its files, and what the page gives it.
  defp given(input, action, panel, params, files) do
    panel.inputs
    |> Act.values(params, panel.time_zone)
    |> Map.merge(files)
    |> Map.merge(Act.from_page(action, opts(input)))
  end

  defp edited({:ok, record}), do: {:ok, %Outcome{record: record}}

  defp edited({:error, %_{} = record, message, places}),
    do: failed(record, message, places: places)

  defp edited({:error, nil, message}), do: failed(nil, message)

  # What became of an action, run straight away or from its panel.
  defp ran({:ok, record}), do: {:ok, %Outcome{record: record}}
  defp ran({:done, value}), do: {:ok, %Outcome{value: value}}
  defp ran(removed) when removed in [:destroyed, :gone], do: {:ok, %Outcome{gone?: true}}
  defp ran({:error, %AshPhoenix.Form{} = form}), do: {:error, %Failure{form: form}}
  defp ran({:unchosen, inputs}), do: {:error, %Failure{unchosen: inputs}}
  defp ran({:error, record, message}), do: failed(record, message)
  defp ran({:error, message}), do: failed(nil, message)

  defp created({:ok, record}, _given), do: {:ok, %Outcome{record: record}}
  defp created(:gone, _given), do: {:ok, %Outcome{gone?: true}}
  defp created({:unchosen, inputs}, _given), do: {:error, %Failure{unchosen: inputs}}

  defp created({:error, %AshPhoenix.Form{} = form}, given),
    do: {:error, %Failure{form: form, given: given}}

  defp failed(record, message, more \\ []),
    do: {:error, struct!(%Failure{record: record, message: message}, more)}

  defp halted({:halt, message}), do: {:halted, message}
  defp halted(_refused), do: :refused

  # What the browser names is looked up here, and only here: the live
  # layer asks these too, where it chooses between opening a panel and a
  # write. A name is looked up as text, so that text from the outside is
  # never turned into an atom.

  @doc "The column of `model` a claim names, by its name as text; nil for none."
  @spec column(Model.t(), term) :: Model.Column.t() | nil
  def column(model, name) when is_binary(name),
    do: Enum.find(model.columns, &(Atom.to_string(&1.name) == name))

  def column(_model, _name), do: nil

  @doc "The action among `actions` a claim names, by its name as text; nil for none."
  @spec action([Model.Action.t()], term) :: Model.Action.t() | nil
  def action(actions, name) when is_binary(name),
    do: Enum.find(actions, &(Atom.to_string(&1.name) == name))

  def action(_actions, _name), do: nil

  @doc """
  The table action a claim names, among those offered now; nil for none. A
  table action is offered once the table has read.
  """
  @spec table_action(Input.t(), term) :: Model.Action.t() | nil
  def table_action(%Input{read?: true} = input, name), do: action(input.offered.table, name)
  def table_action(_input, _name), do: nil

  @doc """
  The action on a selection and the selection a claim names: the action
  among those offered now for a selection (none while a run is on its way),
  and the selection as far as it is one. "All that match" is of a table
  that has read; rows are at least one (`AshDataTable.Intent`). An event
  that says both is of every record where the table has read, and else of
  the rows.
  """
  @spec bulk_action(Input.t(), term, AshDataTable.Intent.selection()) ::
          {:ok, Model.Action.t(), Bulk.selection()} | :error
  def bulk_action(%Input{} = input, name, selection) do
    with %Model.Action{} = action <- action(input.offered.bulk, name),
         selection when not is_nil(selection) <- selection(selection, input.read?) do
      {:ok, action, selection}
    else
      _ -> :error
    end
  end

  defp selection(all, true) when all == :all or elem(all, 0) == :all, do: :all
  defp selection({_rows_or_all, rows}, _read?), do: {:rows, rows}
  defp selection(:all, false), do: nil
end
