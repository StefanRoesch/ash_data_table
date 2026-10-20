defmodule AshDataTable.Live.Core.Panel do
  @moduledoc false
  # The action panel: a row action, a table action, create, the
  # panel's events and its submit, and what came of a create or a run.

  import Phoenix.LiveView

  alias AshDataTable.Act
  alias AshDataTable.Event
  alias AshDataTable.Format
  alias AshDataTable.Geometry
  alias AshDataTable.GroupValue
  alias AshDataTable.Ids
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Bulk
  alias AshDataTable.Live.Core.Cells
  alias AshDataTable.Live.Core.Files
  alias AshDataTable.Live.Core.Notify
  alias AshDataTable.Live.Core.Picker
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Live.Core.Requests
  alias AshDataTable.Model
  alias AshDataTable.Operation
  alias AshDataTable.Pick
  alias AshDataTable.Text

  require AshDataTable.Live.Current, as: Current

  # Sent by the hook when a person uses the page's "Open" of a row: the row
  # by the key in its DOM id. The page is told the row's primary key
  # (`:row_opened`), whatever its `notify` says; nothing is read or
  # written. A key that names no row of the page gets nothing.
  def on({:open, key}, socket) do
    case Core.table(socket).entry do
      %{open_label: label, rows: %{^key => row}} when not is_nil(label) ->
        {:noreply, Notify.told(socket, Event.opened(row.pk), true)}

      _no_open_or_no_row ->
        {:noreply, socket}
    end
  end

  # Sent by the hook when a person uses a button of a row's actions cell,
  # once they have answered the question of an action that has one: the row
  # by the key in its DOM id, and the action by name.
  #
  # Nothing of it is taken on trust: the action has to be one this table
  # offers this person, and the row one of the page. Whether the action runs
  # straight away or opens its panel is the table's to say, not the event's.
  def on({:act, key, name}, socket), do: act(socket, key, name, false)

  # Sent by the button of a table action: the action by name. It has to be
  # one this table offers this person, and the table has to have read: a
  # table that could not read offers nothing.
  #
  # An action with inputs opens the action panel, and nothing runs. One
  # with a question has the hook ask it, and runs when the answer comes
  # (`table_run`). Any other runs now.
  def on({:table_act, name}, socket) do
    %{id: id, model: model} = Core.table(socket).entry

    case Operation.table_action(Core.operation(socket, {:table_act, name}), name) do
      %Model.Action{panel?: true} = action ->
        panel =
          panel(socket, & &1.default, %{
            kind: :table,
            action: action,
            key: nil,
            form: Act.open_generic(model, action, "#{id}-panel", Core.reader(socket)),
            inputs: action.inputs,
            title: action.label,
            submit: {:text, :run, []}
          })

        {:noreply, Files.opened(socket, panel)}

      %Model.Action{confirm: question} = action when is_binary(question) ->
        if Requests.controlled?(socket, :confirm),
          do: {:noreply, Requests.ask(socket, {:table_run, name}, action, nil)},
          else:
            {:noreply,
             push_event(socket, "ash_data_table:ask", %{
               table: id,
               action: action.name,
               question: question
             })}

      %Model.Action{} = action ->
        {:noreply, run_table(socket, {:table_act, name}, action)}

      nil ->
        {:noreply, socket}
    end
  end

  # Sent by the hook once the person has answered the question of a table
  # action with Confirm: the action runs. Whether it has a panel is the
  # table's to say, not the event's.
  def on({:table_run, name}, socket) do
    case Operation.table_action(Core.operation(socket, {:table_run, name}), name) do
      %Model.Action{panel?: false} = action ->
        {:noreply, run_table(socket, {:table_run, name}, action)}

      _none_or_with_inputs ->
        {:noreply, socket}
    end
  end

  # Sent by the panel's form as the person types: what its fields hold. The
  # action is given it, as `AshPhoenix.Form.validate/3` does, and says what
  # it makes of it; nothing runs.
  # The side panel of a filter for several values: what is ticked is kept
  # as it is typed, and filters once it is sent (`Reading.filtered/2`).
  # Nothing of an action is run or asked.
  def on({:panel_validate, typed}, socket)
      when :erlang.map_get(:kind, Current.entry(socket, :panel)) == :filter do
    panel = Core.table(socket).entry.panel
    name = Atom.to_string(panel.column)

    values =
      case typed do
        %{^name => [_own | values]} -> Enum.filter(values, &is_binary/1)
        _none -> panel.values
      end

    {:noreply, Core.put(socket, panel: %{panel | values: values, typed: typed})}
  end

  def on({:panel_submit, typed}, socket)
      when :erlang.map_get(:kind, Current.entry(socket, :panel)) == :filter,
      do: Reading.filtered(socket, typed)

  def on({:panel_validate, typed}, socket) when is_map(Current.entry(socket, :panel)) do
    panel = Core.table(socket).entry.panel

    form = Act.validate(panel.form, panel.inputs, typed, given(panel), panel.time_zone)
    # a field whose record was chosen is one the person has been in
    used = MapSet.union(used(typed), panel.picked)
    panel = sent(%{panel | form: form, used: used, typed: typed}, typed)

    {:noreply,
     socket
     |> Core.put(panel: errors(panel, Core.table(socket).entry.model))
     |> Files.say_refused_files()}
  end

  # Sent by the panel's form when the person uses its button: the action
  # runs with what the fields hold, and with the files of its uploads,
  # which LiveView has received by then.
  #
  # A wall time that the page's zone does not have runs nothing: the panel
  # says so at its field (`AshDataTable.Act.gaps/3`).
  def on({:panel_submit, typed}, socket) when is_map(Current.entry(socket, :panel)) do
    panel = Core.table(socket).entry.panel

    if Act.gaps(panel.inputs, typed, panel.time_zone) == %{},
      do: Files.filed(socket, sent(panel, typed), typed),
      else: {:noreply, failed_panel(socket, sent(%{panel | typed: typed}, typed), nil)}
  end

  # Sent by the button that adds a value to a field made of groups, or the
  # one that takes a value away: the way to the group, as the names it is
  # sent under. The panel is rendered again with the group, or without it,
  # and the action is told as it is of anything typed. The panel's hook is
  # told where focus goes (`ash_data_table:focus`).
  def on({event, [name | rest]}, socket)
      when event in [:panel_add, :panel_remove] and is_map(Current.entry(socket, :panel)) do
    panel = Core.table(socket).entry.panel

    change = if event == :panel_add, do: :add, else: :remove

    with %{} = input <-
           Enum.find(panel.inputs, &(Model.group?(&1) and Atom.to_string(&1.name) == name)),
         {:ok, held, focus} <-
           GroupValue.change(input, panel.groups[name], rest, change, panel.time_zone) do
      groups = Map.put(panel.groups, name, held)
      # every group as the panel holds it, with what the form sent last
      typed = Map.merge(panel.typed, groups)
      form = Act.validate(panel.form, panel.inputs, typed, given(panel), panel.time_zone)
      used = MapSet.put(panel.used, name)
      panel = %{panel | form: form, typed: typed, groups: groups, used: used}
      %{id: id, model: model} = Core.table(socket).entry

      {:noreply,
       socket
       |> Core.put(panel: errors(panel, model))
       |> focus(Ids.field(id, [name | focus]))}
    else
      _ -> {:noreply, socket}
    end
  end

  def on({event, _path}, socket) when event in [:panel_add, :panel_remove],
    do: {:noreply, socket}

  # Sent by the button beside a sensitive field of a row action's panel:
  # "Clear", and "Keep", which takes it back. The panel notes it, and the
  # action is given the field without a value when it runs. Only for a
  # field the panel offers it for (`AshDataTable.Act.clearable/3`). Focus
  # goes back to the button (`ash_data_table:focus`), which a patch that
  # changes what stands before it takes off.
  def on({:panel_clear, name}, socket) when is_map(Current.entry(socket, :panel)) do
    %{clearable: clearable, cleared: cleared} = panel = Core.table(socket).entry.panel

    case Enum.find(clearable, &(Atom.to_string(&1) == name)) do
      nil ->
        {:noreply, socket}

      input ->
        cleared =
          if input in cleared,
            do: MapSet.delete(cleared, input),
            else: MapSet.put(cleared, input)

        {:noreply,
         socket
         |> Core.put(panel: %{panel | cleared: cleared})
         |> focus(Ids.clear(Ids.field(Core.table(socket).entry.id, [name])))}
    end
  end

  def on({:panel_clear, _name}, socket), do: {:noreply, socket}

  # Sent by the panel's hook for Cancel and Escape.
  def on(:panel_cancel, socket),
    do: {:noreply, Core.put(socket, panel: nil, picker: nil)}

  # the form of a panel that is no longer open
  def on({event, _typed}, socket) when event in [:panel_validate, :panel_submit],
    do: {:noreply, socket}

  # Sent by the table's create button. The panel opens with the form of the
  # create action; nothing is created yet. A nested table creates under the
  # row it belongs to, which is read first, as the person.
  def on(:create, socket) when is_map(:erlang.map_get(:create, Current.entry(socket, :model))) do
    action = Core.table(socket).entry.model.create
    %{id: id, model: model} = Core.table(socket).entry

    case Operation.link(Core.operation(socket, :create), action) do
      {:ok, given} ->
        panel =
          panel(socket, & &1.default, %{
            kind: :create,
            action: action,
            key: nil,
            form: Act.open_create(model, action, "#{id}-panel", Core.reader(socket)),
            inputs: action.inputs,
            title: action.label,
            submit: {:text, :create, []},
            given: given
          })

        {:noreply, Files.opened(socket, panel)}

      # The row is gone, or no longer theirs: said to the live region, and
      # shown by the table itself, which reads again and finds the same.
      :error ->
        {:noreply, socket |> Core.say({:text, :record_gone, []}) |> Reading.reread()}
    end
  end

  def on(:create, socket), do: {:noreply, socket}

  # A row action, `confirmed?` once its question was answered: by the hook
  # before it sent `act`, or in controlled mode by the host, which the
  # table holds the question for (`Requests.ask/4`).
  def act(socket, key, name, confirmed?) do
    %{model: model, rows: rows} = Core.table(socket).entry

    with %Model.Action{} = action <- Operation.action(model.actions, name),
         %{} = row <- rows[key] do
      cond do
        action.panel? ->
          open_act(socket, key, row, action)

        is_binary(action.confirm) and not confirmed? and Requests.controlled?(socket, :confirm) ->
          {:reply, %{ok: true}, Requests.ask(socket, {:act, key, name}, action, row.pk)}

        true ->
          ran(Operation.run(Core.operation(socket, {:act, key, name})), socket, key, action)
      end
    else
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  # An action panel as the table keeps it while it is open. Besides what it
  # is given: `typed` is what its form sent last, and `picked` the fields
  # whose records the person has chosen in the picker. `held` gives the value
  # an input starts with.
  #
  # For the fields that are given by choosing related records:
  #
  #   * `chosen` is what the panel knows of the records they hold: by
  #     field, and by a record's key as the field writes it, what the
  #     record is called (`label`: the value of the column it is called by,
  #     with that column and the zone, which the panel formats) and what
  #     the row of its table is named by (`entry/3`); nil for a key of a
  #     record this person may not read;
  #   * `refs` is what the field of an argument holds, by the name it is
  #     sent under: the keys of its records, in their order. An attribute's
  #     field holds what the action's form holds for it; an argument's
  #     starts with what the form knows nothing of: the records that are
  #     related now (`related`, by field: see `AshDataTable.Act.related/3`), or
  #     its default.
  #
  # For the fields of the arguments that take a file: `file_errors` is what
  # the action said of such an argument when it last ran, by field, with
  # the entry LiveView knew the file by that it was given, nil for none
  # (`file_errors/3`), and `refused_files` what was last read out of the
  # files LiveView does not take.
  def panel(socket, held, panel) do
    table = Core.table(socket)
    related = Map.get(panel, :related, %{})

    started =
      for %{editor: editor} = input <- panel.inputs,
          editor in [:reference, :references],
          into: %{} do
        entries =
          case {input.kind, Map.fetch(related, input.name)} do
            {:argument, {:ok, records}} ->
              for record <- records,
                  {:ok, entry} <- [Picker.entry(input, record, table.caller.time_zone)],
                  do: entry

            {:argument, :error} ->
              for value <- List.wrap(input.default), do: known(socket, input, value)

            {:attribute, _none} ->
              value = held.(input)

              if is_nil(value) or is_struct(value, Ash.ForbiddenField),
                do: [],
                else: [known(socket, input, value)]
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
        {Atom.to_string(input.name),
         started(input, held.(input), panel.kind, table.caller.time_zone)}
      end

    Map.merge(
      %{
        errors: %{},
        submitted?: false,
        used: MapSet.new(),
        typed: %{},
        picked: MapSet.new(),
        picked_with: %{},
        chosen: chosen,
        refs: refs,
        groups: groups,
        touched: MapSet.new(),
        file_errors: %{},
        refused_files: [],
        # the sensitive fields a person can ask to be emptied, and those
        # they have asked for: of the panel of an update action on a row
        clearable: [],
        cleared: MapSet.new(),
        # the zone of the page, in which its fields show and take datetimes
        time_zone: table.caller.time_zone
      },
      Map.delete(panel, :related)
    )
  end

  # A record a field starts with, by the key the field holds for it: read as
  # the person, through the picker's read action, for what it is called.
  # One they may not read there is held all the same, and called nothing.
  defp known(socket, input, value) do
    table = Core.table(socket)

    with {:ok, record} <- Pick.current(input.reference, value, Picker.chooser(socket)),
         {:ok, entry} <- Picker.entry(input, record, table.caller.time_zone) do
      entry
    else
      :error -> {Picker.key_text(input, value, table.caller.time_zone), nil}
    end
  end

  # What a field made of groups starts with: the value it is given, as its
  # form sends it. Without a value, a list is empty, and a single value is
  # not there, unless a record is being created and cannot be without it:
  # then its fields are there to be filled in.
  defp started(%{editor: :groups} = input, value, _kind, zone),
    do: GroupValue.held(input, List.wrap(value), zone)

  # a union always sends its kind: none where it has no value
  defp started(%{editor: :union} = input, value, _kind, zone),
    do: GroupValue.held(input, value, zone)

  defp started(input, %{} = value, _kind, zone), do: GroupValue.held(input, value, zone)

  defp started(%{required?: true} = input, _none, :create, zone),
    do: GroupValue.blank(input, zone)

  defp started(_input, _none, _kind, _zone), do: nil

  # The panel with what its form sent for its fields made of groups, and
  # with the fields in them a person has been in. A group that was not sent
  # is not there.
  #
  # And with what it sent for the fields of the arguments that are given by
  # choosing related records: the keys, as they were sent.
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

  # A row action with inputs opens the action panel: the record is read
  # again, as the person, and the form of the action on it is what the panel
  # shows. Nothing runs yet. A row action without inputs runs straight away
  # (`Operation.run/1`): see `ran/4`.
  defp open_act(socket, key, row, %Model.Action{panel?: true} = action) do
    %{id: id, model: model} = Core.table(socket).entry

    case Act.open(model, action, row.pk, "#{id}-panel", Core.reader(socket)) do
      {:ok, record, form, inputs} ->
        title =
          case Reading.title_of(model, record) do
            nil -> action.label
            name -> {:text, :action_on, action: action.label, record: name}
          end

        # A field of a row action starts with the record's value. A
        # generic action accepts no attribute of the record: its arguments
        # start with their defaults, and it is given the row's key.
        {held, given} =
          case action.type do
            :action -> {& &1.default, Act.given(action, row.pk)}
            _update_or_destroy -> {&Map.get(record, &1.name), %{}}
          end

        panel =
          panel(socket, held, %{
            kind: :row,
            action: action,
            key: key,
            form: form,
            inputs: inputs,
            title: title,
            submit: {:text, :run, []},
            given: given,
            # an argument that is everything a relationship is to hold
            # starts with the records that are related now
            related: Act.related(inputs, record, Core.reader(socket)),
            clearable: Act.clearable(action, inputs, record)
          })

        {:reply, %{ok: true, panel: true}, Files.opened(socket, panel)}

      :error ->
        ran({:error, %Operation.Failure{message: {:text, :record_gone, []}}}, socket, key, action)
    end
  end

  # What the panel's form sends: the values of its fields, by name. Which of
  # them are taken is decided where the action is given them (`AshDataTable.Act`).
  # The fields of the panel a person has been in, by name. The browser says
  # which they have not (`_unused_NAME`, as for `Phoenix.Component.used_input?/1`),
  # and the action is not given that.
  defp used(typed) do
    for {name, _value} <- typed,
        not String.starts_with?(name, "_unused_"),
        not is_map_key(typed, "_unused_" <> name),
        into: MapSet.new(),
        do: name
  end

  @doc """
  Tells the panel's hook where focus goes after a button of the panel was
  used (`ash_data_table:focus`): the element of `id`, or the first field in
  it.
  """
  def focus(socket, id),
    do:
      push_event(socket, "ash_data_table:focus", %{table: Core.table(socket).entry.id, cell: id})

  # What the table itself gives the action of a panel.
  def given(panel), do: Map.get(panel, :given, %{})

  # The panel with what its form's errors say, by field.
  # and which values of its arrays they are about
  def errors(panel, model) do
    # a cell that is not this person's to change says so as a cell does
    refusal =
      if panel.kind == :cell,
        do: {:text, :edit_not_allowed, []},
        else: {:text, :action_not_allowed, []}

    # a wall time the page's zone does not have: said at its field, in
    # place of what the action makes of the text it was given for it
    gaps = Act.gaps(panel.inputs, panel.typed, panel.time_zone)

    # each text once at a field, as it is said in this process
    errors =
      Map.new(Act.errors(panel.form, model, panel.inputs, refusal), fn {field, messages} ->
        {field, Text.once(messages)}
      end)

    panel
    |> Map.put(:errors, own(Map.merge(errors, gaps), panel))
    |> Map.put(:places, Act.places(panel.form, panel.inputs))
  end

  # The form of a selection's panel is of the action on a record that holds
  # nothing (`AshDataTable.Act.open_bulk/4`). What it says about a field of the
  # panel is about what was typed; what it says about anything else is
  # about that record, which is nobody's, and is not shown.
  defp own(errors, %{kind: :bulk}), do: Map.delete(errors, nil)

  defp own(errors, _panel), do: errors

  # Runs the action of the open panel (`Operation.submit/1`), with the files
  # of its uploads, and shows what came of it. What the action says about a
  # field is shown at the field, and the panel stays open; done, the panel
  # closes and the table says what came of it. A panel whose row, column or
  # action is no longer this person's closes.
  def submit(socket, panel, params) do
    input =
      Core.operation(socket, {:panel_submit, params},
        panel: panel,
        with_files: &Files.attach(socket, panel, &1)
      )

    result = Operation.submit(input)

    socket
    |> Files.spend(panel, result)
    |> submitted(panel, result)
  end

  defp submitted(socket, _panel, :refused), do: {:noreply, Core.put(socket, panel: nil)}

  defp submitted(socket, panel, {:halted, message}),
    do: {:noreply, failed_panel(socket, panel, message)}

  defp submitted(
         socket,
         panel,
         {:error, %Operation.Failure{form: %AshPhoenix.Form{} = form} = failure}
       ) do
    panel = %{panel | form: form}
    panel = if failure.given, do: %{panel | given: failure.given}, else: panel

    message = if failure.unchosen != [], do: unchosen(failure.unchosen)
    {:noreply, failed_panel(socket, panel, message)}
  end

  defp submitted(socket, panel, {:error, %Operation.Failure{unchosen: [_ | _] = inputs}}),
    do: {:noreply, failed_panel(socket, panel, unchosen(inputs))}

  # the record is gone, or no longer this person's to read, or the value
  # is not theirs to change
  defp submitted(socket, panel, {:error, %Operation.Failure{record: nil, message: message}}),
    do: {:noreply, failed_panel(socket, panel, message)}

  defp submitted(socket, %{kind: :bulk, action: action}, {:start, run, files}),
    do: {:noreply, Bulk.start_bulk(socket, action, run, files)}

  defp submitted(socket, %{kind: :cell, key: key}, {:ok, %Operation.Outcome{} = saved}),
    do:
      {:noreply,
       socket
       |> Core.put(panel: nil)
       |> Reading.put_row(key, saved.record)
       |> Notify.told(saved.event)}

  defp submitted(socket, %{kind: :table, action: action}, {:ok, %Operation.Outcome{} = done}) do
    action =
      Operation.table_action(Core.operation(socket, nil), Atom.to_string(action.name)) || action

    {:noreply,
     socket |> Core.put(panel: nil) |> done(action, done.value) |> Notify.told(done.event)}
  end

  defp submitted(socket, %{kind: :create}, {:ok, %Operation.Outcome{} = created}) do
    model = Core.table(socket).entry.model

    socket =
      if created.gone?,
        do: Core.put(socket, panel: nil),
        else: socket |> Core.put(panel: nil) |> add_row(created.record)

    {:noreply,
     socket
     |> Core.say({:text, :created, name: created_name(model)})
     |> Notify.told(created.event)}
  end

  defp submitted(socket, %{kind: :row, key: key, action: action}, result) do
    {:reply, _reply, socket} = ran(result, Core.put(socket, panel: nil), key, action)
    {:noreply, socket}
  end

  # What the panel says of the fields whose key names a record the person
  # could not have chosen: nothing ran.
  defp unchosen(inputs) do
    {:join, " ",
     for(
       input <- inputs,
       do: {:text, :error_on_field, field: input.label, message: {:text, :record_gone, []}}
     )}
  end

  # What one record of the table is called, at the start of a sentence.
  defp created_name(model), do: model.name |> Text.label() |> String.capitalize()

  # Puts a record that was created at the top of the page, as a row like
  # the others, with its detail when rows expand. It stays there until the
  # table reads again. The rows after it move down by one, and the total is
  # one more: this record is there for certain, though a new read may not
  # find it on this page, or under these filters at all.
  defp add_row(socket, record) do
    %{id: id, model: model, rows: rows, page: page, geometry: geometry} = Core.table(socket).entry
    key = Reading.row_key(model, record, map_size(rows))

    if is_map_key(rows, key) do
      Reading.put_row(socket, key, record)
    else
      first = Geometry.first_row(geometry, page)
      rows = Map.new(rows, fn {key, row} -> {key, %{row | rowindex: row.rowindex + 1}} end)
      rows = Map.put(rows, key, %{rowindex: first, pk: Reading.primary_key(model, record)})

      socket
      |> Reading.due(:force)
      |> Core.put(rows: rows, row_count: map_size(rows))
      |> Core.put(page: page && %{page | total: page.total && page.total + 1})
      # the detail first: each goes to the top, so the row ends up above it.
      # `at: 0`, or in place, and no `limit:`: the grid's hook moves the
      # rows LiveView puts before the header after it (`headFirst`), so a
      # position past 0 would count the header (tab-model-design.md 15)
      |> then(fn socket ->
        if Core.table(socket).entry.expandable?,
          do:
            stream_insert(
              socket,
              Core.table(socket).entry.stream,
              Reading.detail(socket, key, nil),
              at: 0
            ),
          else: socket
      end)
      |> stream_insert(
        Core.table(socket).entry.stream,
        Reading.item(socket, record, %{
          id: id,
          key: key,
          rowindex: first,
          names: Reading.names(model, record, key)
        }),
        at: 0
      )
      # focus goes to the first stop of the row that was created: the
      # hook focuses the first stop of the row group it is named
      |> push_event("ash_data_table:focus", %{table: id, cell: Ids.row(id, key)})
    end
  end

  # The panel stays open with what the action said: at the fields, and above
  # them what is about no field of the panel. All of it is read out.
  defp failed_panel(socket, panel, message) do
    # What the action said of a file is kept with the entry it was said of,
    # where the action has run: its form is then another than the one the
    # panel held, which was never given a file. The entry is still listed:
    # LiveView drops it after this event.
    ran? =
      panel.form != (Core.table(socket).entry.panel && Core.table(socket).entry.panel.form)

    panel =
      errors(%{panel | submitted?: true}, Core.table(socket).entry.model)

    panel =
      if ran? do
        told =
          for input <- Files.file_inputs(panel), into: %{} do
            {input.name,
             {Files.entry_ref(
                Files.upload_of(socket.assigns[:uploads], Core.table(socket).entry.id, input)
              ), Map.get(panel.errors, input.name, [])}}
          end

        %{panel | file_errors: told}
      else
        panel
      end

    panel =
      if message,
        do: %{panel | errors: Map.update(panel.errors, nil, [message], &[message | &1])},
        else: panel

    said =
      for input <- [nil | panel.inputs],
          text <-
            Files.said_of(panel, input, Core.table(socket).entry.id, socket.assigns[:uploads]) do
        if input, do: {:text, :error_on_field, field: input.label, message: text}, else: text
      end

    # what is said at a field inside a group, with the way to it
    inside =
      for {[name | _] = place, texts} <- panel.errors,
          input = Enum.find(panel.inputs, &(&1.name == name)),
          text <- texts,
          do: {:text, :error_on_field, field: field_called(input, tl(place)), message: text}

    message = {:join, "; ", said ++ inside}

    said =
      case panel.kind do
        :cell -> {:text, :not_saved, column: panel.action.label, message: message}
        _action -> {:text, :action_not_done, action: panel.action.label, message: message}
      end

    socket |> Core.put(panel: panel) |> Core.say(said)
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

  # What became of a row action, run straight away or from its panel: the
  # reply to the hook, and the page as it is now.
  defp ran({:ok, %Operation.Outcome{record: %_{} = record} = outcome}, socket, key, action) do
    {:reply, %{ok: true},
     socket
     |> Reading.put_action_failure(key, nil)
     |> Reading.put_row(key, record)
     |> Core.say({:text, :action_done, action: action.label})
     |> Notify.told(outcome.event)}
  end

  # destroyed, or no longer this person's to read: the row is not theirs to
  # see any more
  defp ran({:ok, %Operation.Outcome{gone?: true} = outcome}, socket, key, action) do
    {:reply, %{ok: true, removed: true},
     socket
     |> Reading.remove_row(key)
     |> Core.say({:text, :action_done, action: action.label})
     |> Notify.told(outcome.event)}
  end

  # A generic action returns no row: the table says what it returned and
  # reads again, as any record may be another by now.
  defp ran({:ok, %Operation.Outcome{value: value} = outcome}, socket, _key, action),
    do: {:reply, %{ok: true}, socket |> done(action, value) |> Notify.told(outcome.event)}

  defp ran(
         {:error, %Operation.Failure{record: %_{} = record, message: message}},
         socket,
         key,
         action
       ) do
    {:reply, %{ok: false},
     socket
     |> Reading.put_action_failure(key, message)
     |> Reading.put_row(key, record)
     |> Core.say({:text, :action_not_done, action: action.label, message: message})}
  end

  # The record is gone, or no longer this person's to read: there is nothing
  # to show the row from, so it stays as it is, and the hook marks the
  # actions cell with the message. A veto says no in the same way.
  defp ran({error, message_or_failure}, socket, _key, action) when error in [:error, :halted] do
    message = Cells.message(message_or_failure)

    {:reply, %{ok: false, error: Text.say(message)},
     Core.say(socket, {:text, :action_not_done, action: action.label, message: message})}
  end

  defp ran(:refused, socket, _key, _action), do: {:reply, %{ok: false}, socket}

  # A table action that runs straight away (`Operation.run/1`). What came of
  # it is said above the grid, where the outcome of an action on the
  # selected rows is said: there is no row to say it on.
  defp run_table(socket, intent, action) do
    case Operation.run(Core.operation(socket, intent)) do
      {:ok, %Operation.Outcome{value: value} = outcome} ->
        socket |> done(action, value) |> Notify.told(outcome.event)

      {error, message_or_failure} when error in [:error, :halted] ->
        text =
          {:text, :action_not_done,
           action: action.label, message: Cells.message(message_or_failure)}

        socket |> Core.put(result: %{summary: text, failures: []}) |> Core.say(text)

      :refused ->
        socket
    end
  end

  # A generic action has run: the table says what it returned, when that
  # can be said in a word or a line, else that it is done, and reads again.
  defp done(socket, action, value) do
    text =
      case Format.said(action, value, Core.table(socket).caller.time_zone) do
        nil -> {:text, :action_done, action: action.label}
        said -> {:text, :action_result, action: action.label, result: said}
      end

    socket
    |> Core.put(result: %{summary: text, failures: []})
    |> Core.say(text)
    |> Reading.reread()
  end
end
