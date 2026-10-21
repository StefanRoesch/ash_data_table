defmodule AshDataTable.Panel do
  @moduledoc false
  # The action panel: the one value a table holds while a person gives the
  # inputs of one action, or ticks the values of one filter, and everything
  # about its life (stage 9d). What it opens with, what its form holds and
  # shows as the person types, the groups added and taken away, the records
  # chosen in the picker, the fields asked to be emptied, what its button
  # runs and what came of that. No socket: the live core's adapter
  # (`AshDataTable.Live.Core.Panel`) puts what this gives into the entry,
  # with the uploads (LiveView's, `AshDataTable.Live.Core.Files`), the live
  # region and focus.
  #
  # A panel is of one kind of a closed set, and the kind is matched here and
  # nowhere else; `for` holds what it is about:
  #
  #   * `:cell` - a cell edited in the panel (an array, a map cell, a
  #     union): `key` (the row's, as its DOM id has it), `column` (its name)
  #     and `action`, the column's update action as the panel knows an
  #     action;
  #   * `:row` - a row action with inputs: `key` and `action`;
  #   * `:table` - a table action with inputs: `action`;
  #   * `:create` - the table's create action: `action`;
  #   * `:bulk` - an action on the selected rows: `action` and `selection`
  #     (`:all`, or `{:rows, rows}`, claims);
  #   * `:filter` - the values of a filter for several of them: `column` and
  #     `operator`. No action, no form: what is ticked is `values`.
  #
  # The form is built through `AshDataTable.Act` (a cell's through
  # `AshDataTable.Edit`), which keeps every call of AshPhoenix and Ash; what
  # the form gives an action and what it shows is here (`values/4`,
  # `gaps/3`, `errors/4`, `places/2`, `unchosen/4`, `clearable/3`,
  # `unchanged?/4`), and `Act` and `Edit` ask it where they run one. A
  # value made of fields travels in the form through
  # `AshDataTable.GroupValue`.
  #
  # Nothing of it is drawn as it is: a part is given what `shown/2` makes
  # of it (`AshDataTable.Present.Panel`).

  alias AshDataTable.Act
  alias AshDataTable.Edit
  alias AshDataTable.Errors
  alias AshDataTable.GroupValue
  alias AshDataTable.Model
  alias AshDataTable.Pick
  alias AshDataTable.Present
  alias AshDataTable.Typed

  # Besides `kind` and `for`:
  #
  #   * `form` the action's form (`AshPhoenix.Form`), nil for a filter's;
  #     `inputs` the fields, one per input the person has; `given` what the
  #     table gives the action itself (a row's key to a generic action, the
  #     field that joins a nested table's new record to its row);
  #   * `title`, `submit` (the text of its button) and `question` (asked
  #     before it runs, nil for none), message terms;
  #   * `time_zone` the page's, in which its fields show and take datetimes;
  #   * `values` what a filter's panel has ticked;
  #   * `typed` what its form sent last; `used` the fields a person has been
  #     in, by name, and `touched` the fields inside groups, by the names on
  #     the way to them; `submitted?` whether its button was used;
  #   * `groups` what each field made of groups holds, as its form sends it;
  #   * for the fields given by choosing related records: `chosen` what the
  #     panel knows of the records they hold (by field, and by a record's
  #     key as the field writes it, what the record is called, `label`: the
  #     value of the column it is called by, with that column and the zone,
  #     which the part formats, and what the row of its table is named by;
  #     nil for a key of a record this person may not read); `refs` what
  #     the field of an argument holds, by the name it is sent under, the
  #     keys of its records in their order (an attribute's field holds what
  #     the form holds for it); `picked` the fields whose records were chosen
  #     in the picker, and `picked_with` what the picker's read action was
  #     given for each key chosen there;
  #   * `clearable` the sensitive fields a person can ask to be emptied (of
  #     the panel of an update action on a row), and `cleared` those they
  #     have asked for;
  #   * `errors` what the action said, by field (nil for none of them, a
  #     list for the way to a field inside a value), each text once as
  #     `once` makes it (the live layer's, which says them in this process),
  #     and `places` which values of its arrays they are about;
  #   * for the fields that take a file: `file_errors` what the action said
  #     of such an argument when it last ran, by field, with the entry
  #     LiveView knew the file by that it was given; `refused_files` what
  #     was last read out of the files LiveView does not take; and `spent`
  #     the entries an action has been given, which are LiveView's to drop.
  defstruct [
    :kind,
    :form,
    :title,
    :submit,
    :question,
    for: %{},
    inputs: [],
    given: %{},
    time_zone: "Etc/UTC",
    values: [],
    typed: %{},
    used: MapSet.new(),
    touched: MapSet.new(),
    submitted?: false,
    groups: %{},
    chosen: %{},
    refs: %{},
    picked: MapSet.new(),
    picked_with: %{},
    clearable: [],
    cleared: MapSet.new(),
    errors: %{},
    places: %{},
    once: &Function.identity/1,
    file_errors: %{},
    refused_files: [],
    spent: MapSet.new()
  ]

  @type t :: %__MODULE__{}
  @type kind :: :cell | :row | :table | :create | :bulk | :filter

  @doc """
  Opens a panel of `kind` for `for`, of the person's `model`: the form of
  its action, read as the person (the record of a row once more), and what
  each field starts with. Nothing runs.

  `for` holds what the kind is about: `key` and `pk` (the row's primary
  key) and `column` for `:cell`, `key`, `pk` and `action` for `:row`,
  `action` for `:table` and `:create`, `action`, `selection` and `count`
  (how many records, nil for not known) for `:bulk`, `column`, `operator`
  and `values` (ticked now) for `:filter`.

  `opts`: `id` (the table's: the form is `ID-panel`), `time_zone`, `reader`
  (who asks, as `AshDataTable.Query.read/3` takes it), `chooser` (who reads
  what a picker reads, `AshDataTable.Pick.reader/2`), `given` (of a create:
  what the table gives it), `question` (of a selection's: what it asks
  first), and what the live layer says in words: `named` (what a record is
  called, nil for nothing; the title names it), `entry` (a chosen record as
  the panel knows it, `{:ok, {key, %{label, row}}}` or `:error`) and `once`.

  `{:error, message}` where the record is gone, or no longer this person's;
  `:refused` for a cell whose value they may not see on this record.
  """
  @spec open(kind, map, Model.t(), keyword) :: {:ok, t} | {:error, Errors.message()} | :refused
  def open(:cell, %{key: key, pk: pk, column: column}, model, opts) do
    case Edit.open(model, column, pk, form_id(opts), opts[:reader]) do
      {:ok, record, form} ->
        # the column's update action, as the panel knows an action
        action = %Model.Action{
          name: column.update_action,
          type: :update,
          label: column.label,
          confirm: column.confirm
        }

        %__MODULE__{
          kind: :cell,
          for: %{key: key, column: column.name, action: action},
          form: form,
          inputs: [Model.input(model, column)],
          title: titled(column.label, record, opts),
          submit: {:text, :save, []},
          question: action.confirm
        }
        |> started(&Map.get(record, &1.name), %{}, opts)
        |> then(&{:ok, &1})

      # not theirs to see on this record, and so not theirs to change
      :hidden ->
        :refused

      :error ->
        {:error, {:text, :record_gone, []}}
    end
  end

  # A row action: the record is read again, as the person, and the form of
  # the action on it is what the panel shows. A field starts with the
  # record's value; a generic action accepts no attribute of the record: its
  # arguments start with their defaults, and it is given the row's key. An
  # argument that is everything a relationship is to hold starts with the
  # records that are related now.
  def open(:row, %{key: key, pk: pk, action: action}, model, opts) do
    case Act.open(model, action, pk, form_id(opts), opts[:reader]) do
      {:ok, record, form, inputs} ->
        {held, given} =
          case action.type do
            :action -> {& &1.default, Act.given(action, pk)}
            _update_or_destroy -> {&Map.get(record, &1.name), %{}}
          end

        related = Act.related(inputs, record, opts[:reader])

        %__MODULE__{
          kind: :row,
          for: %{key: key, action: action},
          form: form,
          inputs: inputs,
          title: titled(action.label, record, opts),
          submit: {:text, :run, []},
          question: action.confirm,
          given: given,
          clearable: clearable(action, inputs, record)
        }
        |> started(held, related, opts)
        |> then(&{:ok, &1})

      :error ->
        {:error, {:text, :record_gone, []}}
    end
  end

  def open(:table, %{action: action}, model, opts) do
    %__MODULE__{
      kind: :table,
      for: %{action: action},
      form: Act.open_generic(model, action, form_id(opts), opts[:reader]),
      inputs: action.inputs,
      title: action.label,
      submit: {:text, :run, []},
      question: action.confirm
    }
    |> started(& &1.default, %{}, opts)
    |> then(&{:ok, &1})
  end

  def open(:create, %{action: action}, model, opts) do
    %__MODULE__{
      kind: :create,
      for: %{action: action},
      form: Act.open_create(model, action, form_id(opts), opts[:reader]),
      inputs: action.inputs,
      title: action.label,
      submit: {:text, :create, []},
      question: action.confirm,
      given: Keyword.get(opts, :given, %{})
    }
    |> started(& &1.default, %{}, opts)
    |> then(&{:ok, &1})
  end

  # Its fields start empty, but for an argument's default: there is no one
  # record to take a value from. What they hold is given to the action on
  # every record. The selection is kept with the panel, as a row's key is
  # with the panel of a row.
  def open(:bulk, %{action: action, selection: selection, count: count}, model, opts) do
    title =
      case count do
        nil -> {:text, :bulk_on_all, action: action.label}
        count -> {:text, :bulk_on, count: count, action: action.label}
      end

    %__MODULE__{
      kind: :bulk,
      for: %{action: action, selection: selection},
      form: Act.open_bulk(model, action, form_id(opts), opts[:reader]),
      inputs: Model.bulk_inputs(action),
      title: title,
      submit: {:text, :run, []},
      question: opts[:question]
    }
    |> started(fn _input -> nil end, %{}, opts)
    |> then(&{:ok, &1})
  end

  # One field, a box per value, ticked as the filter applies; no action, no
  # question.
  def open(:filter, %{column: column, operator: operator, values: values}, _model, opts) do
    %__MODULE__{
      kind: :filter,
      for: %{column: column.name, operator: operator},
      inputs: [Model.filter_input(column)],
      values: values,
      title: {:text, :filter, column: column.label},
      submit: {:text, :apply, []}
    }
    |> started(fn _input -> nil end, %{}, opts)
    |> then(&{:ok, &1})
  end

  defp form_id(opts), do: "#{Keyword.fetch!(opts, :id)}-panel"

  # What a panel is headed by: the action, and what the record is called.
  defp titled(label, record, opts) do
    case Keyword.get(opts, :named, fn _record -> nil end).(record) do
      nil -> label
      name -> {:text, :action_on, action: label, record: name}
    end
  end

  # What each field starts with: `held` gives the value of an input; the
  # fields given by choosing related records the records they hold
  # (`related`, by field, for an argument that starts with the records
  # related now), the fields made of groups what their forms send.
  defp started(panel, held, related, opts) do
    zone = Keyword.fetch!(opts, :time_zone)
    panel = %{panel | time_zone: zone, once: Keyword.get(opts, :once, panel.once)}
    entry = Keyword.get(opts, :entry, &bare(&1, &2, zone))

    started =
      for %{editor: editor} = input <- panel.inputs,
          editor in [:reference, :references],
          into: %{} do
        entries =
          case {input.kind, Map.fetch(related, input.name)} do
            {:argument, {:ok, records}} ->
              for record <- records, {:ok, entry} <- [entry.(input, record)], do: entry

            {:argument, :error} ->
              for value <- List.wrap(input.default), do: known(input, value, entry, opts)

            {:attribute, _none} ->
              value = held.(input)

              if is_nil(value) or is_struct(value, Ash.ForbiddenField),
                do: [],
                else: [known(input, value, entry, opts)]
          end

        # one record where the field holds one: several that are related now
        # are not what it would hold
        entries = if editor == :reference and length(entries) > 1, do: [], else: entries

        {input, Enum.uniq_by(entries, &elem(&1, 0))}
      end

    chosen = Map.new(started, fn {input, entries} -> {input.name, Map.new(entries)} end)

    refs =
      for {%{kind: :argument} = input, entries} <- started, into: %{} do
        {Atom.to_string(input.name), Enum.map(entries, &elem(&1, 0))}
      end

    # what each field made of groups starts with, as its form sends it
    groups =
      for input <- panel.inputs, Model.group?(input), into: %{} do
        {Atom.to_string(input.name), group(input, held.(input), panel.kind, zone)}
      end

    %{panel | chosen: chosen, refs: refs, groups: groups}
  end

  # A record a field starts with, by the key the field holds for it: read as
  # the person, through the picker's read action, for what it is called.
  # One they may not read there is held all the same, and called nothing.
  defp known(input, value, entry, opts) do
    with {:ok, record} <-
           Pick.current(input.reference, value, Keyword.get(opts, :chooser, opts[:reader])),
         {:ok, entry} <- entry.(input, record) do
      entry
    else
      :error -> {key_text(input, value, Keyword.fetch!(opts, :time_zone)), nil}
    end
  end

  # A chosen record without words: its key, called nothing.
  defp bare(input, record, zone) do
    with {:ok, value} <- Pick.value(input.reference, record),
         do: {:ok, {key_text(input, value, zone), %{label: nil, row: nil}}}
  end

  @doc """
  A key as a field of the panel writes it: an attribute's as the editor of
  its type does, an argument's as a key is written.
  """
  @spec key_text(Model.Input.t(), term, AshDataTable.Zone.t()) :: String.t()
  def key_text(%{kind: :attribute} = input, value, zone), do: Typed.of(input, value, zone)
  def key_text(_argument, value, _zone), do: to_string(Pick.written(value))

  # What a field made of groups starts with: the value it is given, as its
  # form sends it. Without a value, a list is empty, and a single value is
  # not there, unless a record is being created and cannot be without it:
  # then its fields are there to be filled in.
  defp group(%{editor: :groups} = input, value, _kind, zone),
    do: GroupValue.held(input, List.wrap(value), zone)

  # a union always sends its kind: none where it has no value
  defp group(%{editor: :union} = input, value, _kind, zone),
    do: GroupValue.held(input, value, zone)

  defp group(input, %{} = value, _kind, zone), do: GroupValue.held(input, value, zone)

  defp group(%{required?: true} = input, _none, :create, zone), do: GroupValue.blank(input, zone)

  defp group(_input, _none, _kind, _zone), do: nil

  @doc """
  What the panel's form holds now, `typed` as it sent it: the action is
  given it, as `AshPhoenix.Form.validate/3` does, and says what it makes of
  it, at the fields; nothing runs. A filter's panel keeps what is ticked.
  `model` is the person's, which names what is about no field.
  """
  @spec validate(t, Model.t(), map) :: t
  def validate(%__MODULE__{kind: :filter} = panel, _model, typed) do
    name = Atom.to_string(panel.for.column)

    values =
      case typed do
        %{^name => [_own | values]} -> Enum.filter(values, &is_binary/1)
        _none -> panel.values
      end

    %{panel | values: values, typed: typed}
  end

  def validate(%__MODULE__{} = panel, model, typed) do
    # a field whose record was chosen is one the person has been in
    used = MapSet.union(used(typed), panel.picked)

    %{panel | form: validated(panel, typed), used: used, typed: typed}
    |> sent(typed)
    |> assessed(model)
  end

  defp validated(panel, typed),
    do: Act.validate(panel.form, values(panel.inputs, typed, panel.given, panel.time_zone))

  @doc """
  The panel as its button was used, `typed` what its form sent: `{:ok,
  panel}` to run its action (`submission/2`), `{:gaps, panel}` where a wall
  time the page's zone does not have runs nothing (said at its field once
  `failed/4` has it), `{:filter, filter}` for a filter's panel: the column
  (`column`), its operator and the values that were ticked.
  """
  @spec submitted(t, map) :: {:ok, t} | {:gaps, t} | {:filter, map}
  def submitted(%__MODULE__{kind: :filter, for: %{column: column, operator: operator}}, typed) do
    name = Atom.to_string(column)

    values =
      case typed do
        %{^name => [_own | values]} -> Enum.filter(values, &is_binary/1)
        _none -> []
      end

    {:filter, %{column: column, operator: operator, values: values}}
  end

  def submitted(%__MODULE__{} = panel, typed) do
    if gaps(panel.inputs, typed, panel.time_zone) == %{},
      do: {:ok, sent(panel, typed)},
      else: {:gaps, sent(%{panel | typed: typed}, typed)}
  end

  @doc """
  What the panel's button runs, `typed` what its form sent: the write of
  `AshDataTable.Operation.submit/1` for its kind, with what the panel holds
  of it (`params`, its `form`, `inputs`, `time_zone`, the fields asked to
  be emptied, `cleared`, and `picked_with`). The names in it are the
  panel's, and are looked up again where the write is checked.
  """
  @spec submission(t, map) :: tuple
  def submission(%__MODULE__{} = panel, typed) do
    held = %{
      params: typed,
      form: panel.form,
      inputs: panel.inputs,
      time_zone: panel.time_zone,
      cleared: MapSet.to_list(panel.cleared),
      picked_with: panel.picked_with
    }

    case panel do
      %{kind: :cell, for: %{key: key, column: column}} -> {:submit_cell, key, column, held}
      %{kind: :row, for: %{key: key, action: action}} -> {:submit_row, key, action, held}
      %{kind: :table, for: %{action: action}} -> {:submit_table, action, held}
      %{kind: :create, for: %{action: action}} -> {:submit_create, action, held}
      %{kind: :bulk, for: %{action: action, selection: s}} -> {:submit_bulk, action, s, held}
    end
  end

  @doc """
  Whether what the panel's action runs with outlasts the event: a run on a
  selection, which is given copies of its files (`AshDataTable.Live.Core.Files`).
  """
  @spec outlasts?(t) :: boolean
  def outlasts?(%__MODULE__{kind: kind}), do: kind == :bulk

  @doc """
  What came of the panel's submission (`AshDataTable.Operation.submit/1`'s
  result): `:closed` for a write the model does not allow; `{:open, panel,
  message}` where it stays open with what the action said (at its fields,
  and `message` above them, nil for nothing); else `{:closed, done}`, what
  the table shows of it:

    * `{:saved, key, outcome}` - a cell's value was saved;
    * `{:ran, key, action, result}` - a row action ran, or did not with the
      record still there: the result as a row action's straight away;
    * `{:done, action, outcome}` - a table action ran;
    * `{:created, outcome}` - a record was created;
    * `{:start, action, run, files}` - a run on the selection, to be started
      beside the process.
  """
  @spec outcome(t, term) :: :closed | {:open, t, Errors.message() | nil} | {:closed, tuple}
  def outcome(_panel, :refused), do: :closed

  def outcome(panel, {:halted, message}), do: {:open, panel, message}

  def outcome(panel, {:error, %{form: %AshPhoenix.Form{} = form} = failure}) do
    panel = %{panel | form: form}
    panel = if failure.given, do: %{panel | given: failure.given}, else: panel

    {:open, panel, if(failure.unchosen != [], do: unchosen_said(failure.unchosen))}
  end

  def outcome(panel, {:error, %{unchosen: [_ | _] = inputs}}),
    do: {:open, panel, unchosen_said(inputs)}

  # the record is gone, or no longer this person's to read, or the value
  # is not theirs to change
  def outcome(panel, {:error, %{record: nil, message: message}}), do: {:open, panel, message}

  def outcome(%__MODULE__{kind: :bulk, for: %{action: action}}, {:start, run, files}),
    do: {:closed, {:start, action, run, files}}

  def outcome(%__MODULE__{kind: :cell, for: %{key: key}}, {:ok, outcome}),
    do: {:closed, {:saved, key, outcome}}

  def outcome(%__MODULE__{kind: :table, for: %{action: action}}, {:ok, outcome}),
    do: {:closed, {:done, action, outcome}}

  def outcome(%__MODULE__{kind: :create}, {:ok, outcome}), do: {:closed, {:created, outcome}}

  def outcome(%__MODULE__{kind: :row, for: %{key: key, action: action}}, result),
    do: {:closed, {:ran, key, action, result}}

  # What the panel says of the fields whose key names a record the person
  # could not have chosen: nothing ran.
  defp unchosen_said(inputs) do
    {:join, " ",
     for(
       input <- inputs,
       do: {:text, :error_on_field, field: input.label, message: {:text, :record_gone, []}}
     )}
  end

  @doc """
  The panel stays open with what the action said (`outcome/2`): its errors
  at the fields, all shown now, and `message` above them (nil for none).
  `files` is what the action said of a file at its field, by name, with the
  entry LiveView knew the file by that it was given, where the action has
  run (nil where it has not: a panel that was never given a file).
  """
  @spec failed(t, Model.t(), Errors.message() | nil, %{optional(atom) => term} | nil) :: t
  def failed(%__MODULE__{} = panel, model, message, files) do
    panel = assessed(%{panel | submitted?: true}, model)

    panel =
      if files,
        do: %{
          panel
          | file_errors:
              Map.new(files, fn {name, ref} -> {name, {ref, Map.get(panel.errors, name, [])}} end)
        },
        else: panel

    if message,
      do: %{panel | errors: Map.update(panel.errors, nil, [message], &[message | &1])},
      else: panel
  end

  @doc """
  Whether the panel's action has run since `open` was the open panel: its
  form is then another than the one the panel held, which was never given a
  file.
  """
  @spec ran?(t, t | nil) :: boolean
  def ran?(%__MODULE__{form: form}, open), do: form != (open && open.form)

  @doc """
  What the live region says of a panel that stayed open (`failed/4`):
  `said` is what is read out of each field, `{input, text}` (nil for none of
  them), and inside it what is said at a field inside a group, with the way
  to it.
  """
  @spec said(t, [{Model.Input.t() | nil, Errors.message()}]) :: Errors.message()
  def said(%__MODULE__{} = panel, said) do
    said =
      for {input, text} <- said do
        if input, do: {:text, :error_on_field, field: input.label, message: text}, else: text
      end

    inside =
      for {[name | _] = place, texts} <- panel.errors,
          input = Enum.find(panel.inputs, &(&1.name == name)),
          text <- texts,
          do: {:text, :error_on_field, field: field_called(input, tl(place)), message: text}

    message = {:join, "; ", said ++ inside}

    case panel do
      %{kind: :cell, for: %{action: action}} ->
        {:text, :not_saved, column: action.label, message: message}

      %{for: %{action: action}} ->
        {:text, :action_not_done, action: action.label, message: message}
    end
  end

  # What a field inside a group is called, for the live region: the labels
  # on the way to it, with the place of a value of an array ("Milestones 2
  # Title").
  defp field_called(%{label: label} = field, [index | rest]) when is_integer(index) do
    position = {:text, :value_position, column: label, position: index + 1}
    field_called(%{field | label: position, cell_type: :map}, rest)
  end

  defp field_called(%{label: label} = field, [name | rest]) do
    # of a union, a field of one of its kinds
    fields =
      Map.get(field, :fields) || Enum.flat_map(Map.get(field, :members) || [], &(&1.fields || []))

    case Enum.find(fields, &(&1.name == name)) do
      nil -> label
      field -> field_called(%{field | label: {:join, " ", [label, field.label]}}, rest)
    end
  end

  defp field_called(%{label: label}, []), do: label

  @doc """
  Adds a value to a field made of groups, or takes one away: `path` is the
  way to the group, as the names it is sent under (`AshDataTable.GroupValue.change/5`),
  a claim followed through the input's fields only. The action is told as
  it is of anything typed. `{:ok, panel, focus}`, `focus` the id segments of
  where focus goes (`AshDataTable.Ids.field/2`); `:error` for a path that
  leads nowhere.
  """
  @spec change(t, Model.t(), [String.t()], :add | :remove) :: {:ok, t, list} | :error
  def change(%__MODULE__{} = panel, model, [name | rest], change) do
    with %{} = input <-
           Enum.find(panel.inputs, &(Model.group?(&1) and Atom.to_string(&1.name) == name)),
         {:ok, held, focus} <-
           GroupValue.change(input, panel.groups[name], rest, change, panel.time_zone) do
      groups = Map.put(panel.groups, name, held)
      # every group as the panel holds it, with what the form sent last
      typed = Map.merge(panel.typed, groups)
      used = MapSet.put(panel.used, name)

      panel = %{
        panel
        | form: validated(%{panel | typed: typed}, typed),
          typed: typed,
          groups: groups,
          used: used
      }

      {:ok, assessed(panel, model), [name | focus]}
    else
      _none -> :error
    end
  end

  def change(_panel, _model, _path, _change), do: :error

  @doc """
  "Clear" beside a sensitive field of a row action's panel, and "Keep",
  which takes it back: the field `name` (as text) is asked to be emptied,
  or no longer. The action is given it without a value when it runs. Only
  for a field the panel offers it for (`clearable/3`); `:error` else.
  """
  @spec clear(t, String.t()) :: {:ok, t, atom} | :error
  def clear(%__MODULE__{clearable: clearable, cleared: cleared} = panel, name) do
    case Enum.find(clearable, &(Atom.to_string(&1) == name)) do
      nil ->
        :error

      input ->
        cleared =
          if input in cleared,
            do: MapSet.delete(cleared, input),
            else: MapSet.put(cleared, input)

        {:ok, %{panel | cleared: cleared}, input}
    end
  end

  @doc """
  The input of the panel given by choosing related records, by its name as
  text; nil for none.
  """
  @spec reference(t, term) :: Model.Input.t() | nil
  def reference(%__MODULE__{inputs: inputs}, name) do
    Enum.find(
      inputs,
      &(&1.editor in [:reference, :references] and Atom.to_string(&1.name) == name)
    )
  end

  @doc """
  The keys a field of an argument given by choosing holds, as it writes
  them, in their order: `name` the input's (an atom) or the name it is
  sent under. Nil for a field the panel keeps no keys of.
  """
  @spec keys(t | nil, atom | String.t()) :: [String.t()] | nil
  def keys(%__MODULE__{refs: refs}, name), do: Map.get(refs, to_string(name))
  def keys(nil, _name), do: nil

  @doc """
  What the panel knows of the records a field given by choosing holds, by
  key as the field writes it (`%{label, row}`, nil for one this person may
  not read); `name` the input's.
  """
  @spec known(t | nil, atom) :: map
  def known(%__MODULE__{chosen: chosen}, name), do: Map.get(chosen, name, %{})
  def known(nil, _name), do: %{}

  @doc """
  Puts keys into a field of the panel that is given by choosing, as if its
  form had sent them, after a choice in the picker or a key taken out
  (`unpick`). The field is one the person has been in; the action is told
  as it is of anything typed.
  """
  @spec hold(t, Model.t(), Model.Input.t(), [String.t()]) :: t
  def hold(%__MODULE__{} = panel, model, input, keys) do
    name = Atom.to_string(input.name)

    sent =
      case input.editor do
        :references -> ["" | keys]
        :reference -> List.first(keys, "")
      end

    typed = Map.put(panel.typed, name, sent)
    picked = MapSet.put(panel.picked, name)

    %{
      panel
      | form: validated(panel, typed),
        typed: typed,
        refs:
          if(is_map_key(panel.refs, name), do: Map.put(panel.refs, name, keys), else: panel.refs),
        picked: picked,
        used: MapSet.union(panel.used, picked)
    }
    |> assessed(model)
  end

  @doc """
  The record chosen in the picker for a field that holds one: `chosen` is
  its key as the field writes it and what the panel knows of it (`{"",
  nil}` for none), `arguments` what the picker's read action was given, with
  which the key is looked up once more when the action runs.
  """
  @spec choose(t, Model.t(), Model.Input.t(), {String.t(), map | nil}, map) :: t
  def choose(%__MODULE__{} = panel, model, input, {text, known}, arguments) do
    panel = %{
      panel
      | chosen: Map.put(panel.chosen, input.name, %{text => known}),
        picked_with: Map.put(panel.picked_with, input.name, {text, arguments})
    }

    hold(panel, model, input, if(text == "", do: [], else: [text]))
  end

  @doc """
  The records chosen in the picker for a field that holds several: `kept`
  the keys it held and keeps, in their order, and `added` the records that
  were chosen besides, each its key and what the panel knows of it, with
  `arguments` what the picker's read action was given.
  """
  @spec choose(t, Model.t(), Model.Input.t(), [String.t()], [{String.t(), map}], map) :: t
  def choose(%__MODULE__{} = panel, model, input, kept, added, arguments) do
    with_arguments = Map.new(added, fn {text, _known} -> {text, arguments} end)

    picked_with =
      Map.update(panel.picked_with, input.name, with_arguments, fn
        %{} = before -> Map.merge(before, with_arguments)
        _other -> with_arguments
      end)

    panel = %{
      panel
      | chosen:
          Map.put(panel.chosen, input.name, Map.merge(known(panel, input.name), Map.new(added))),
        picked_with: picked_with
    }

    hold(panel, model, input, kept ++ Enum.map(added, &elem(&1, 0)))
  end

  @doc "The fields of the panel that take a file."
  @spec file_inputs(t | nil) :: [Model.Input.t()]
  def file_inputs(%__MODULE__{inputs: inputs}), do: Enum.filter(inputs, &(&1.editor == :file))
  def file_inputs(nil), do: []

  @doc """
  What the action said of the file of a field, `ref` the entry LiveView
  knows the field's file by now (nil for none): what it said when it last
  ran, of the file it was given then or of having been given none, until
  another file is chosen. A file that was chosen and not yet given has had
  nothing said of it.
  """
  @spec file_errors(t, Model.Input.t(), term) :: [Errors.message()]
  def file_errors(%__MODULE__{file_errors: told}, input, ref) do
    case {Map.get(told, input.name), ref} do
      # the file the action was given, for as long as LiveView lists it
      {{given, texts}, given} -> texts
      # no file since
      {{_given, texts}, nil} -> texts
      _another_file_or_never_run -> []
    end
  end

  @doc "What the action said at a field (`input`, nil for none of them)."
  @spec errors_at(t, Model.Input.t() | nil) :: [Errors.message()]
  def errors_at(%__MODULE__{errors: errors}, input), do: Map.get(errors, input && input.name, [])

  @doc "The panel with what was last read out of the files LiveView does not take."
  @spec refused(t, list) :: t
  def refused(%__MODULE__{} = panel, refused), do: %{panel | refused_files: refused}

  @doc """
  The panel with more entries of its uploads that an action has been
  given (`refs`): those are LiveView's to drop.
  """
  @spec spend(t, [term]) :: t
  def spend(%__MODULE__{spent: spent} = panel, refs),
    do: %{panel | spent: MapSet.union(spent, MapSet.new(refs))}

  @doc "The entries of the panel's uploads an action has been given; none for no panel."
  @spec spent(t | nil) :: MapSet.t()
  def spent(%__MODULE__{spent: spent}), do: spent
  def spent(nil), do: MapSet.new()

  @doc "The action of the panel; nil for a filter's."
  @spec action(t) :: Model.Action.t() | nil
  def action(%__MODULE__{for: made_for}), do: Map.get(made_for, :action)

  @doc "The column a cell's or a filter's panel is of; nil for any other."
  @spec column(t) :: atom | nil
  def column(%__MODULE__{for: made_for}), do: Map.get(made_for, :column)

  @doc "The row a panel is of, by the key in its DOM id; nil for none."
  @spec row(t) :: String.t() | nil
  def row(%__MODULE__{for: made_for}), do: Map.get(made_for, :key)

  @doc """
  What a panel is made for, as a request held for the host tells two
  panels apart (`AshDataTable.Live.Core.Opener.Host`): its kind, its action's
  name, its row and its column.
  """
  @spec made_for(t) :: tuple
  def made_for(%__MODULE__{kind: kind} = panel) do
    action = action(panel)
    {kind, action && action.name, row(panel), column(panel)}
  end

  @doc """
  What a part draws of the open panel (`AshDataTable.Present.Panel`, with
  an `AshDataTable.Present.Field` per input): its texts, whether its
  question is asked only when something changed (`asks/1`), what each field
  shows (`field/3`), what is said of none of them. `upload_errors` is what
  the live layer says at each file field, by name. Nothing sensitive is in
  it: a sensitive field holds what was typed into it in this panel, else
  nothing; a chosen record is called by its label, scrubbed.
  """
  @spec shown(t, map) :: Present.Panel.t()
  def shown(%__MODULE__{} = panel, upload_errors \\ %{}) do
    %Present.Panel{
      title: panel.title,
      ask: asks(panel),
      question: panel.question,
      submit: panel.submit,
      method: method(panel),
      destructive?: destructive?(panel),
      errors: panel.errors[nil],
      fields:
        for input <- panel.inputs do
          shown = field(panel, input, upload_errors)

          %Present.Field{
            name: input.name,
            path: [Atom.to_string(input.name)],
            form_name: shown.form_name,
            input: input,
            value: shown.value,
            errors: shown.errors,
            places: shown.places,
            chosen: panel.chosen[input.name],
            clear: shown.clear
          }
        end,
      inside: %{
        errors: panel.errors,
        touched: panel.touched,
        submitted?: panel.submitted?,
        time_zone: panel.time_zone
      }
    }
  end

  @doc """
  Whether the panel's question is asked only when something changed: of
  the panel of a cell (a list, a map cell, a union), `"changed"`; else nil,
  asked whenever its button is used.
  """
  @spec asks(t) :: String.t() | nil
  def asks(%__MODULE__{kind: :cell}), do: "changed"
  def asks(%__MODULE__{}), do: nil

  @doc "Whether the panel's action destroys the record."
  @spec destructive?(t) :: boolean
  def destructive?(%__MODULE__{} = panel), do: match?(%{type: :destroy}, action(panel))

  @doc "The HTTP method of the panel's form, as `AshPhoenix.Form` says it."
  @spec method(t) :: String.t()
  def method(%__MODULE__{form: nil}), do: "post"
  def method(%__MODULE__{form: form}), do: form.method

  @doc """
  What a field of the panel shows (`shown/2`): the
  name of its control (`form_name`), what the control holds (`value`), the
  errors shown at it and the places of the values of an array they are
  about, and for a sensitive field that can be emptied `clear`
  (`:offered`, or `:asked`). `upload_errors` is what the live layer says
  at each file field, by name.
  """
  @spec field(t, Model.Input.t(), map) :: map
  def field(%__MODULE__{} = panel, input, upload_errors) do
    errors = shown(panel, input, upload_errors)

    %{
      form_name: form_name(panel.form, input.name),
      value: held(panel, input),
      errors: errors,
      places: if(errors == [], do: [], else: Map.get(panel.places, input.name, [])),
      clear:
        cond do
          input.name in panel.cleared -> :asked
          input.name in panel.clearable -> :offered
          true -> nil
        end
    }
  end

  # The name of a field's control, as a form names it: under the form's
  # name (`panel[title]`); a filter's has no form, and is named so all the
  # same.
  defp form_name(nil, name), do: "panel[#{name}]"
  defp form_name(%{name: nil}, name), do: Atom.to_string(name)
  defp form_name(%{name: form}, name), do: "#{form}[#{name}]"

  @doc """
  What a field of the panel holds, as its control holds it: a filter's the
  values ticked; a field made of groups as its form sends it; the field of
  an argument that is given by choosing related records their keys, as the
  panel keeps them (a list for several, one key or "" for one); a sensitive
  field what was typed into it in this panel, never what the record has,
  nor a default; a datetime that was typed as it was typed, a wall time in
  the page's zone; and any other what the action's form holds for it,
  written as the editor of its type writes it: what the person typed, once
  they have; else the value of the record; or, for an input that has no
  record to take one from (an argument, an attribute of a record that is
  being created), its default.
  """
  @spec held(t, Model.Input.t()) :: term
  def held(%__MODULE__{kind: :filter, values: values}, _input), do: values

  def held(%__MODULE__{} = panel, input) do
    name = Atom.to_string(input.name)

    cond do
      Model.group?(input) ->
        panel.groups[name]

      is_map_key(panel.refs, name) and input.editor == :references ->
        panel.refs[name]

      is_map_key(panel.refs, name) ->
        List.first(panel.refs[name], "")

      AshDataTable.Resource.Exposing.sensitive?(input) ->
        case panel.typed do
          %{^name => typed} when is_binary(typed) -> typed
          _nothing_typed -> ""
        end

      # the form holds the instant it was given as
      is_map_key(panel.typed, name) and AshDataTable.Zone.zoned?(input.type) ->
        written(input, GroupValue.taken(input, panel.typed[name], panel.time_zone), false, panel)

      true ->
        written(
          input,
          AshPhoenix.Form.value(panel.form, input.name),
          panel.kind == :create or input.kind == :argument,
          panel
        )
    end
  end

  # What a field holds, as the editor of its type writes it. An attribute
  # that is empty on a record is empty in the field, whatever its default.
  # The field of an array holds a list: the values as they were typed, else
  # those of the record or of the default; without any it is empty.
  defp written(%{cell_type: {:array, _item}} = input, values, default?, panel) do
    cond do
      is_list(values) -> Typed.of(input, values, panel.time_zone)
      default? and is_list(input.default) -> Typed.of(input, input.default, panel.time_zone)
      true -> []
    end
  end

  defp written(_input, typed, _default?, _panel) when is_binary(typed), do: typed

  defp written(%{default: default} = input, nil, true, panel) when not is_nil(default),
    do: Typed.of(input, default, panel.time_zone)

  defp written(_input, nil, _default?, _panel), do: ""

  defp written(input, value, _default?, panel), do: Typed.of(input, value, panel.time_zone)

  # The errors of a field that are shown: all of them once the person has
  # used "Run", and until then those of the fields they have been in. Of a
  # file: what the action said of the file it was given (`upload_errors`,
  # with what LiveView says of the file before it). Of a union: once they
  # have been at its choice, or in its value.
  defp shown(_panel, %{editor: :file} = input, upload_errors),
    do: Map.get(upload_errors, input.name, [])

  defp shown(panel, %{editor: :union} = input, _upload_errors) do
    if panel.submitted? or GroupValue.touched?(panel.touched, [Atom.to_string(input.name)]),
      do: Map.get(panel.errors, input.name, []),
      else: []
  end

  defp shown(panel, input, _upload_errors) do
    if panel.submitted? or Atom.to_string(input.name) in panel.used,
      do: Map.get(panel.errors, input.name, []),
      else: []
  end

  # The panel with what its form sent for its fields made of groups, and
  # with the fields in them a person has been in. A group that was not sent
  # is not there. And with what it sent for the fields of the arguments
  # that are given by choosing related records: the keys, as they were sent.
  defp sent(panel, typed) do
    groups =
      for {name, _held} <- panel.groups, into: %{} do
        {name, with(held when not is_map(held) <- typed[name], do: nil)}
      end

    refs =
      for {name, held} <- panel.refs, into: %{} do
        case typed do
          %{^name => [_own | keys]} -> {name, Enum.filter(keys, &(is_binary(&1) and &1 != ""))}
          %{^name => key} when is_binary(key) -> {name, if(key == "", do: [], else: [key])}
          _not_sent -> {name, held}
        end
      end

    %{panel | groups: groups, refs: refs, touched: touched(typed, [])}
  end

  # The fields a person has been in, by the names they are sent under, from
  # the outside in. As `used/1`, for the fields inside a group.
  defp touched(typed, path) do
    for {name, held} <- typed,
        not String.starts_with?(name, "_unused_"),
        not is_map_key(typed, "_unused_" <> name),
        reduce: MapSet.new() do
      touched ->
        touched = MapSet.put(touched, path ++ [name])
        if is_map(held), do: MapSet.union(touched, touched(held, path ++ [name])), else: touched
    end
  end

  # The fields of the panel a person has been in, by name. The browser says
  # which they have not (`_unused_NAME`, as for
  # `Phoenix.Component.used_input?/1`), and the action is not given that.
  defp used(typed) do
    for {name, _value} <- typed,
        not String.starts_with?(name, "_unused_"),
        not is_map_key(typed, "_unused_" <> name),
        into: MapSet.new(),
        do: name
  end

  # The panel with what its form's errors say, by field, each text once at
  # a field, and which values of its arrays they are about.
  defp assessed(panel, model) do
    # a cell that is not this person's to change says so as a cell does
    refusal =
      if panel.kind == :cell,
        do: {:text, :edit_not_allowed, []},
        else: {:text, :action_not_allowed, []}

    # a wall time the page's zone does not have: said at its field, in
    # place of what the action makes of the text it was given for it
    gaps = gaps(panel.inputs, panel.typed, panel.time_zone)

    errors =
      Map.new(errors(panel.form, model, panel.inputs, refusal), fn {field, messages} ->
        {field, panel.once.(messages)}
      end)

    %{
      panel
      | errors: own(Map.merge(errors, gaps), panel),
        places: places(panel.form, panel.inputs)
    }
  end

  # The form of a selection's panel is of the action on a record that holds
  # nothing (`AshDataTable.Act.open_bulk/4`). What it says about a field of
  # the panel is about what was typed; what it says about anything else is
  # about that record, which is nobody's, and is not shown.
  defp own(errors, %{kind: :bulk}), do: Map.delete(errors, nil)
  defp own(errors, _panel), do: errors

  # ## What a form gives an action, and what it shows
  #
  # An input that is a map cell (an embedded resource, a map, an array of
  # either) is given as a map of its fields, as an API gives it: by the
  # names of the fields the table offers, each as it was typed, and nothing
  # else that was sent (`AshDataTable.GroupValue.taken/3`). Ash casts it,
  # through the embedded resource's own actions. An error about a field of
  # such a value is shown at that field (`errors/4`). A union is given as its
  # kind and that kind's value, as Ash takes a union from outside.
  #
  # An input that is sensitive (`AshDataTable.Sensitive`) is typed hidden,
  # into a field that starts empty whatever the record holds. Left empty it
  # is not given to the action at all: an update keeps what the record has,
  # and a create or an argument is given nothing, which the action answers
  # as it answers any input that is missing. So it cannot be emptied by
  # leaving it empty: an update action is told to empty one by name, those
  # a person asked to clear that can be cleared on the record as it is now
  # (`clearable/3`, `cleared/4`), which are given nil, as what the table
  # gives itself. Nothing the form sends says so.
  #
  # An input that takes a file is never taken from what the browser sent:
  # the table gives it, from the upload the panel holds.
  #
  # An input that is given by choosing a related record holds that record's
  # key, and a key from the browser is a claim like any other: before an
  # action runs, a key that was put there is looked up as the person,
  # through the read action the picker offers its records through
  # (`unchosen/4`). One that names nothing they could have chosen runs
  # nothing. So does an argument that hands the keys of several records to
  # a relationship, but for those of the records that are related already
  # where the argument is everything the relationship is to hold
  # (`AshDataTable.Act.related/3`): those are nobody's choice.

  @doc """
  What an action is given of what a panel's form sent: the values of
  `inputs`, by name, as they were typed, and no others; a datetime as the
  instant it is in `zone`, the time zone of the page; and `given`, what the
  table gives the action itself, which nothing from the browser replaces.
  A datetime the zone does not have is text the action does not take
  (`AshDataTable.GroupValue.given/3`), and the panel says why at its field
  (`gaps/3`).
  """
  @spec values([Model.Input.t()], map) :: map
  def values(inputs, params), do: values(inputs, params, %{}, AshDataTable.Zone.utc())

  @spec values([Model.Input.t()], map, AshDataTable.Zone.t()) :: map
  def values(inputs, params, zone), do: values(inputs, params, %{}, zone)

  @spec values([Model.Input.t()], map, map, AshDataTable.Zone.t()) :: map
  def values(inputs, params, given, zone) when is_map(params) do
    for input <- inputs,
        name = Atom.to_string(input.name),
        given?(input, params, name),
        into: %{} do
      {value, _gaps} =
        GroupValue.given(input, GroupValue.taken(input, params[name], zone), zone)

      {name, value}
    end
    |> Map.merge(given)
  end

  def values(_inputs, _params, given, _zone), do: given

  @doc """
  Where the inputs of a panel hold a wall time that the time zone of the
  page does not have (`AshDataTable.Zone`), as `errors/4` names the places
  of errors: the input, or the way to a field of a value inside it. Each
  with the message that says so.
  """
  @spec gaps([Model.Input.t()], map, AshDataTable.Zone.t()) :: %{
          optional(atom | [atom | non_neg_integer]) => [Errors.message()]
        }
  def gaps(inputs, params, zone) when is_map(params) do
    for input <- inputs,
        name = Atom.to_string(input.name),
        given?(input, params, name),
        path <- GroupValue.gaps(input, GroupValue.taken(input, params[name], zone), zone),
        into: %{} do
      # at the field of the value, as an error of Ash's about it is; one of
      # the values of an array of datetimes is at the array's field
      place =
        case path |> Enum.reverse() |> Enum.drop_while(&is_integer/1) |> Enum.reverse() do
          [] -> input.name
          way -> [input.name | way]
        end

      {place, [{:text, :no_such_time, zone: zone}]}
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
  Whether what the field of a map cell sent is what the cell holds already:
  `value` as the record has it. Compared as the field itself would send
  the value, in `zone`, the time zone of the page.
  """
  @spec unchanged?(map, term, term) :: boolean
  def unchanged?(input, sent, value), do: unchanged?(input, sent, value, AshDataTable.Zone.utc())

  @spec unchanged?(map, term, term, AshDataTable.Zone.t()) :: boolean
  def unchanged?(input, sent, value, zone),
    do:
      GroupValue.taken(input, sent, zone) ==
        GroupValue.taken(input, GroupValue.held(input, value, zone), zone)

  @doc """
  The inputs of a row action that a person can ask to be emptied on this
  record, by name: the sensitive attributes an update action accepts and
  takes without a value (`required?`), which the record holds a value for
  that this person sees. A sensitive field starts empty and gives the
  action nothing while it is empty, so this is the one way to empty it.

  None for any other action: a create has nothing to empty, a destroy
  takes the record away, and an argument holds nothing between two runs.
  """
  @spec clearable(Model.Action.t(), [Model.Input.t()], Ash.Resource.record() | nil) :: [atom]
  def clearable(%Model.Action{type: :update}, inputs, %_{} = record) do
    for %{kind: :attribute, sensitive?: true, required?: false, name: name} <- inputs,
        value = Map.get(record, name),
        not is_struct(value, Ash.ForbiddenField),
        not AshDataTable.Resource.Exposing.empty?(value),
        do: name
  end

  def clearable(%Model.Action{}, _inputs, _record), do: []

  @doc """
  What the action is given for the inputs a person asked to clear (`asked`,
  by name): nil, for those that can be cleared on the record as it is now
  (`clearable/3`).
  """
  @spec cleared(Model.Action.t(), [Model.Input.t()], Ash.Resource.record(), [atom]) :: map
  def cleared(action, inputs, record, asked) do
    for name <- clearable(action, inputs, record), name in asked, into: %{} do
      {Atom.to_string(name), nil}
    end
  end

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
  records that are related now (`AshDataTable.Act.related/3`).

  `opts` are those of `AshDataTable.Pick.reader/2`, and `:picked_with`:
  what the picker's read action was given for a key that was chosen there.
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
           key <- List.wrap(GroupValue.taken(input, sent, AshDataTable.Zone.utc())),
           is_binary(key) and key != "",
           do: key
         ) do
      [] ->
        false

      keys ->
        held = holds(input, record, opts)

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
  defp holds(_input, nil, _opts), do: MapSet.new()

  defp holds(%{kind: :attribute, name: name}, record, _opts) do
    case Map.get(record, name) do
      nil -> MapSet.new()
      %Ash.ForbiddenField{} -> MapSet.new()
      held -> MapSet.new([Pick.written(held)])
    end
  end

  defp holds(%{reference: %{related?: true} = reference}, record, opts) do
    for related <- Pick.related(reference, record, opts),
        {:ok, value} <- [Pick.value(reference, related)],
        into: MapSet.new(),
        do: Pick.written(value)
  end

  defp holds(_input, _record, _opts), do: MapSet.new()

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
  What a form's errors say to a person: by input, for the errors about one
  of `inputs`, and under `nil` for the others. An error about a field of a
  value inside the record (a field of a map cell) is under the way to that
  field: the input, the places of values in an array, and the fields on the
  way (`[:client, :address, :city]`, `[:milestones, 1, :title]`). What Ash
  says of a record that an argument hands to a relationship, without a text
  of its own, is under that argument: that the record is not available.
  See `AshDataTable.Errors` for what is shown of an error; `refusal` is
  what a refusal reads as. Each term once at a field: the live layer says
  each text once (`once`).
  """
  @spec errors(AshPhoenix.Form.t(), Model.t(), [Model.Input.t()], Errors.message()) ::
          %{optional(atom | nil | [atom | non_neg_integer]) => [Errors.message()]}
  def errors(form, model, inputs, refusal \\ {:text, :action_not_allowed, []})

  def errors(nil, _model, _inputs, _refusal), do: %{}

  def errors(form, %Model{} = model, inputs, refusal) do
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
               {:field, place} ->
                 {place, Errors.ash(error, nested_sensitive?(inputs, path, field))}

               # at the group, which says which of its fields is meant
               {:group, place} ->
                 {single(place), named(field, error, nested_sensitive?(inputs, path, field))}

               nil ->
                 {nil, Errors.nested_text(model, path, field, error)}
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
          %Ash.Error.Query.NotFound{} -> {:text, :record_gone, []}
          _nothing_to_say -> {:text, :action_failed, []}
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
    case Enum.find(inputs, &(&1.name == name and &1.editor in [:group, :groups, :union])) do
      nil ->
        nil

      input ->
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
  defp named(field, error, sensitive?) do
    {:text, :error_on_field,
     field: {:label, AshDataTable.Resource.Words.humanize(field)},
     message: Errors.ash(error, sensitive?)}
  end

  # Whether an error inside a value is about a `sensitive?` field of it: its
  # variables are masked then, as at a field of the panel.
  defp nested_sensitive?(inputs, [name | rest], field) do
    case Enum.find(inputs, &(&1.name == name)) do
      nil ->
        false

      input ->
        Map.get(input, :sensitive?, false) or Errors.sensitive_within?(input, rest ++ [field])
    end
  end

  defp nested_sensitive?(_inputs, _path, _field), do: false

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
  @spec places(AshPhoenix.Form.t() | nil, [Model.Input.t()]) ::
          %{optional(atom) => [non_neg_integer]}
  def places(nil, _inputs), do: %{}

  def places(form, inputs) do
    for input <- inputs, places = Errors.places(form, input), places != [], into: %{} do
      {input.name, places}
    end
  end
end
