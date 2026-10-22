defmodule AshDataTable.Live.Core.Panel do
  @moduledoc false
  # The action panel over the table (stage 9d, 9g): the 2b adapter of
  # `AshDataTable.Panel`, which is the panel and its life. An intent of the
  # panel's events becomes a function of `Panel`, and what it gives is put
  # into the entry here, with the uploads (`Core.Files`), what the page is
  # told (`Core.Notify`), the live region and focus. Nothing else puts a
  # panel into an entry or takes one out: the other topics open one with
  # `open/4` and close it with `close/1`. And the row actions, the table
  # actions and create, which open a panel or run straight away, and what
  # came of a create or a run.
  #
  # ## The submit, in two intents
  #
  # A write goes through `AshDataTable.Operation` in one order: the checks,
  # the veto, the files, the record read again, the action. The files of a
  # panel are LiveView's, and only inside `consume_uploaded_entry/3` (the
  # adapter's): the action has to run in there, while LiveView holds them.
  # So a panel's submit is two intents, split at the files:
  #
  #   1. `{:panel_submit, typed}`: `Operation.submit/1` runs the checks and
  #      the veto, and where both let it go on, it gets to the files: its
  #      `with_files` is given the rest of the write (a function of the
  #      files: the record read again, the action), and hands it back
  #      (`{:files, write}`), run by nothing yet. Refused or halted, nothing
  #      gets that far: no file is consumed, none given, the panel says so.
  #      With files to give, the step's last effect is `{:uploads,
  #      {:consume, id, files, panel, write}}`; with none, `write` runs here,
  #      at once, with no file.
  #   2. `{:consumed, panel, write, files}`: what the adapter runs inside
  #      the consume of the last file (`Live.Core.effects/2`), with the
  #      files as `Plug.Upload`s: `write` runs, and what it came to is
  #      shown as one write's outcome is.
  #
  # The order is kept: `write` exists only where the checks and the veto
  # let it, it holds what the checks found (the row, the action, the
  # column) and runs nothing else before the files, and the rest runs once,
  # inside the consume. Nothing runs between the two intents: the effect
  # is the first intent's last, applied in the same callback before
  # anything else (`tidy` comes after both), and no event, host answer or
  # parse can name `{:consumed, …}`: only the adapter makes it, of an
  # effect a step gave.

  alias AshDataTable.Event
  alias AshDataTable.Format
  alias AshDataTable.Geometry
  alias AshDataTable.Ids
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Files
  alias AshDataTable.Live.Core.Notify
  alias AshDataTable.Live.Core.Opener
  alias AshDataTable.Live.Core.Picker
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Model
  alias AshDataTable.Operation
  alias AshDataTable.Panel
  alias AshDataTable.Table
  alias AshDataTable.Text

  # Sent by the hook when a person uses the page's "Open" of a row: the row
  # by the key in its DOM id. The page is told the row's primary key
  # (`:row_opened`), whatever its `notify` says; nothing is read or
  # written. A key that names no row of the page gets nothing.
  def step({:open, key}, table) do
    case table.entry do
      %{open_label: label, rows: %{^key => row}} when not is_nil(label) ->
        {Core.effect(table, Notify.told(table, Event.opened(row.pk), true)), nil}

      _no_open_or_no_row ->
        {table, nil}
    end
  end

  # Sent by the panel's form as the person types: what its fields hold
  # (`Panel.validate/3`); nothing runs. What LiveView does not take of its
  # files is read out (`refused_files/1`).
  def step({:panel_validate, typed}, table) when is_map(table.entry.panel) do
    %{panel: panel, model: model} = table.entry
    {table |> put(Panel.validate(panel, model, typed)) |> refused_files(), nil}
  end

  # the form of a panel that is no longer open
  def step({:panel_validate, _typed}, table), do: {table, nil}

  # Sent by the button that adds a value to a field made of groups, or the
  # one that takes a value away: the way to the group, as the names it is
  # sent under. The panel is rendered again with the group, or without it.
  # The panel's hook is told where focus goes (`ash_data_table:focus`).
  def step({event, path}, table)
      when event in [:panel_add, :panel_remove] and is_map(table.entry.panel) do
    %{id: id, model: model, panel: panel} = table.entry
    change = if event == :panel_add, do: :add, else: :remove

    case Panel.change(panel, model, path, change) do
      {:ok, panel, focus} -> {table |> put(panel) |> focus(Ids.field(id, focus)), nil}
      :error -> {table, nil}
    end
  end

  def step({event, _path}, table) when event in [:panel_add, :panel_remove], do: {table, nil}

  # Sent by the button beside a sensitive field of a row action's panel:
  # "Clear", and "Keep", which takes it back (`Panel.clear/2`). Focus goes
  # back to the button (`ash_data_table:focus`), which a patch that changes
  # what stands before it takes off.
  def step({:panel_clear, name}, table) when is_map(table.entry.panel) do
    %{id: id, panel: panel} = table.entry

    case Panel.clear(panel, name) do
      {:ok, panel, _input} ->
        {table |> put(panel) |> focus(Ids.clear(Ids.field(id, [name]))), nil}

      :error ->
        {table, nil}
    end
  end

  def step({:panel_clear, _name}, table), do: {table, nil}

  # Sent by the panel's hook for Cancel and Escape.
  def step(:panel_cancel, table), do: {table |> close() |> Table.put(picker: nil), nil}

  # Sent by the hook when a person uses a button of a row's actions cell,
  # once they have answered the question of an action that has one: the row
  # by the key in its DOM id, and the action by name.
  #
  # Nothing of it is taken on trust: the action has to be one this table
  # offers this person, and the row one of the page. Whether the action runs
  # straight away or opens its panel is the table's to say, not the event's.
  def step({:act, key, name}, table), do: act(table, key, name, false)

  # The host's Confirm of a row action's question (controlled mode).
  def step({:confirmed, {:act, key, name}}, table), do: act(table, key, name, true)

  def step({:confirmed, {:table_run, _name} = intent}, table), do: step(intent, table)

  # Sent by the button of a table action: the action by name. It has to be
  # one this table offers this person, and the table has to have read: a
  # table that could not read offers nothing.
  #
  # An action with inputs opens the action panel, and nothing runs. One
  # with a question asks it (`Opener.ask/4`): the table has the hook ask
  # it, or the host does (controlled mode), and it runs when the answer
  # comes (`table_run`). Any other runs now.
  def step({:table_act, name}, table) do
    %{id: id} = table.entry

    case Operation.table_action(Core.operation(table, {:table_act, name}), name) do
      %Model.Action{panel?: true} = action ->
        {:ok, table} = open(table, :table, %{action: action})
        {table, nil}

      %Model.Action{confirm: question} = action when is_binary(question) ->
        case Opener.ask(table, {:table_run, name}, question, %{action: action.name}) do
          {:run, table} ->
            {Core.effect(
               table,
               {:push, "ash_data_table:ask",
                %{table: id, action: action.name, question: question}}
             ), nil}

          {:held, _reply, table} ->
            {table, nil}
        end

      %Model.Action{} = action ->
        {run_table(table, {:table_act, name}, action), nil}

      nil ->
        {table, nil}
    end
  end

  # Sent by the hook once the person has answered the question of a table
  # action with Confirm: the action runs. Whether it has a panel is the
  # table's to say, not the event's.
  def step({:table_run, name}, table) do
    case Operation.table_action(Core.operation(table, {:table_run, name}), name) do
      %Model.Action{panel?: false} = action -> {run_table(table, {:table_run, name}, action), nil}
      _none_or_with_inputs -> {table, nil}
    end
  end

  # Sent by the panel's form when the person uses its button: the action
  # runs with what the fields hold, and with the files of its uploads,
  # which LiveView has received by then (see "The submit, in two intents"
  # above); a filter's panel filters (`Reading.filtered/2`). A wall time
  # that the page's zone does not have runs nothing: the panel says so at
  # its field (`Panel.gaps/3`).
  def step({:panel_submit, typed}, table) when is_map(table.entry.panel) do
    case Panel.submitted(table.entry.panel, typed) do
      {:filter, filter} -> {table |> close() |> Reading.filtered(filter), nil}
      {:ok, panel} -> {filed(table, panel, typed), nil}
      {:gaps, panel} -> {failed(table, panel, nil), nil}
    end
  end

  # the form of a panel that is no longer open
  def step({:panel_submit, _typed}, table), do: {table, nil}

  # The second intent of a submit: the files consumed, the rest of the
  # write runs inside the consume of the last (see the top). A run that
  # outlasts the event (on a selection) is given copies of them, which
  # its own process is given (`Core.Bulk`), and which go with it
  # (`Files.copies/1`). A run that does not start (the form failed, or
  # nothing was chosen) leaves the panel open: its copies are deleted at
  # once, so a retry does not pile them up in this process. The entries the
  # write was given are the panel's to keep, and LiveView's to take away
  # (`Files.given/2`).
  def step({:consumed, panel, write, files}, table) do
    files = if Panel.outlasts?(panel), do: Files.copies(files), else: files
    result = write.(files)

    if Panel.outlasts?(panel) and not match?({:start, _, _}, result),
      do: Enum.each(files, fn {_name, %{path: path}} -> File.rm(path) end)

    {written(table, panel, result, Files.given(table, panel)), nil}
  end

  # Sent by the table's create button. The panel opens with the form of the
  # create action; nothing is created yet. A nested table creates under the
  # row it belongs to, which is read first, as the person.
  def step(:create, table) when is_map(table.entry.model.create) do
    action = table.entry.model.create

    case Operation.link(Core.operation(table, :create), action) do
      {:ok, given} ->
        {:ok, table} = open(table, :create, %{action: action}, given: given)
        {table, nil}

      # The row is gone, or no longer theirs: said to the live region, and
      # shown by the table itself, which reads again and finds the same.
      :error ->
        {table |> Core.say({:text, :record_gone, []}) |> Reading.reread(), nil}
    end
  end

  def step(:create, table), do: {table, nil}

  @doc """
  Opens a panel of `kind` for `for` (`AshDataTable.Panel.open/4`), as the
  person asking, and puts it into the entry, with an upload for each of its
  fields that take a file (`Files.allowed/2`). `more` are options of
  `Panel.open/4` besides those the table knows. `{:ok, table}`; else what
  `Panel.open/4` says, the table as it was.
  """
  def open(%Table{caller: caller, entry: entry} = table, kind, for, more \\ []) do
    opts =
      [
        id: entry.id,
        time_zone: caller.time_zone,
        reader: Core.reader(table),
        chooser: Picker.chooser(table),
        named: &Reading.title_of(entry.model, &1),
        entry: &Picker.entry(&1, &2, caller.time_zone),
        once: &Text.once/1
      ] ++ more

    case Panel.open(kind, for, entry.model, opts) do
      {:ok, panel} -> {:ok, table |> Files.allowed(panel) |> put(panel)}
      not_opened -> not_opened
    end
  end

  @doc "Puts the open panel as it is now into the entry."
  def put(%Table{} = table, %Panel{} = panel), do: Table.put(table, panel: panel)

  @doc "Closes the panel (a new read, a run, Cancel); the picker is the caller's."
  def close(%Table{} = table), do: Table.put(table, panel: nil)

  @doc """
  Tells the panel's hook where focus goes after a button of the panel was
  used (`ash_data_table:focus`): the element of `id`, or the first field in
  it. An effect.
  """
  def focus(%Table{} = table, id),
    do: Core.effect(table, {:push, "ash_data_table:focus", %{table: table.entry.id, cell: id}})

  # A row action, `confirmed?` once its question was answered by the host
  # (controlled mode). A question not yet answered is asked
  # (`Opener.ask/4`): the hook asked it before it sent `act`, or the host
  # asks it, and the action waits for its answer.
  defp act(table, key, name, confirmed?) do
    %{model: model, rows: rows} = table.entry

    with %Model.Action{} = action <- Operation.action(model.actions, name),
         %{} = row <- rows[key] do
      cond do
        action.panel? ->
          open_act(table, key, row, action)

        is_binary(action.confirm) and not confirmed? ->
          about = %{action: action.name, key: row.pk}

          case Opener.ask(table, {:act, key, name}, action.confirm, about) do
            {:run, table} -> run_act(table, key, name, action)
            {:held, _reply, table} -> {table, %{ok: true}}
          end

        true ->
          run_act(table, key, name, action)
      end
    else
      _ -> {table, %{ok: false}}
    end
  end

  defp run_act(table, key, name, action),
    do: ran(Operation.run(Core.operation(table, {:act, key, name})), table, key, action)

  # A row action with inputs opens the action panel: the record is read
  # again, as the person (`Panel.open/4`). Nothing runs yet. A row action
  # without inputs runs straight away (`Operation.run/1`): see `ran/4`.
  defp open_act(table, key, row, action) do
    case open(table, :row, %{key: key, pk: row.pk, action: action}) do
      {:ok, table} ->
        {table, %{ok: true, panel: true}}

      {:error, message} ->
        ran({:error, %Operation.Failure{message: message}}, table, key, action)
    end
  end

  # Whether the panel's action can run with the files of its uploads
  # (`Files.filed/2`): nothing runs while LiveView does not take a file, or
  # has not received one: that is said, and the panel stays.
  defp filed(table, panel, typed) do
    case Files.filed(table, panel) do
      :ok ->
        submit(table, panel, typed)

      :waiting ->
        Core.say(table, {:text, :upload_failed, []})

      {:refused, refused} ->
        table |> put(Panel.refused(panel, refused)) |> Files.say_files(refused)
    end
  end

  # What LiveView does not take of the panel's files (of the uploads the
  # step's `context` holds), read out when it changes: a file is refused
  # as it is chosen, without the panel's button having been used.
  defp refused_files(table) do
    %{id: id, panel: panel} = table.entry

    case Files.refused(table.context.uploads, id, panel) do
      refused when refused == panel.refused_files -> table
      refused -> table |> put(Panel.refused(panel, refused)) |> Files.say_files(refused)
    end
  end

  # The first intent of the submit (see the top): the action of the open
  # panel (`Operation.submit/1`, what `Panel.submission/2` says it is) up to
  # its files. Past the checks and the veto, `with_files` hands the rest
  # back (`{:files, write}`): it runs here where the panel has no file to
  # give, else inside LiveView's consume of them, as the second intent.
  # Refused or halted, nothing was given.
  defp submit(table, panel, typed) do
    input = Core.operation(table, Panel.submission(panel, typed), with_files: &{:files, &1})

    case Operation.submit(input) do
      {:files, write} ->
        case Files.consumed(table, panel) do
          [] ->
            written(table, panel, write.(%{}), [])

          files ->
            Core.effect(table, {:uploads, {:consume, table.entry.id, files, panel, write}})
        end

      refused_or_halted ->
        written(table, panel, refused_or_halted, [])
    end
  end

  # Shows what came of the action of the panel (`Panel.outcome/2`), with
  # the entries of the files it was given (`Panel.spend/2`). What the
  # action says about a field is shown at the field, and the panel stays
  # open; done, the panel closes and the table says what came of it. A
  # panel whose row, column or action is no longer this person's closes.
  defp written(table, panel, result, given) do
    panel = Panel.spend(panel, given)

    case Panel.outcome(panel, result) do
      :closed -> close(table)
      {:open, panel, message} -> failed(table, panel, message)
      {:closed, done} -> closed(close(table), done)
    end
  end

  defp closed(table, {:start, action, run, files}) do
    {table, _reply} = Core.run({:bulk_start, action, run, files}, table)
    table
  end

  defp closed(table, {:saved, key, saved}),
    do: table |> Reading.put_row(key, saved.record) |> Core.notify(saved.event)

  defp closed(table, {:done, action, done}) do
    action =
      Operation.table_action(Core.operation(table, nil), Atom.to_string(action.name)) || action

    table |> done(action, done) |> Core.notify(done.event)
  end

  defp closed(table, {:created, created}) do
    model = table.entry.model
    table = if created.gone?, do: table, else: add_row(table, created.record)

    table
    |> Core.say({:text, :created, name: created_name(model)})
    |> Core.notify(created.event)
  end

  defp closed(table, {:ran, key, action, result}) do
    {table, _reply} = ran(result, table, key, action)
    table
  end

  # What one record of the table is called, at the start of a sentence.
  defp created_name(model), do: model.name |> Text.label() |> String.capitalize()

  # Puts a record that was created at the top of the page, as a row like
  # the others, with its detail when rows expand. It stays there until the
  # table reads again. The rows after it move down by one, and the total is
  # one more: this record is there for certain, though a new read may not
  # find it on this page, or under these filters at all.
  defp add_row(table, record) do
    %{id: id, model: model, rows: rows, page: page, geometry: geometry, stream: stream} =
      table.entry

    key = Reading.row_key(model, record, map_size(rows))

    if is_map_key(rows, key) do
      Reading.put_row(table, key, record)
    else
      first = Geometry.first_row(geometry, page)

      rows =
        Map.new(rows, fn {key, row} ->
          {key, %{row | rowindex: Geometry.shifted(row.rowindex, :added, first)}}
        end)

      rows = Map.put(rows, key, %{rowindex: first, pk: Reading.primary_key(model, record)})

      item =
        Reading.item(table, record, %{
          id: id,
          key: key,
          rowindex: first,
          names: Reading.names(model, record, key)
        })

      table
      |> Reading.due(:force)
      |> Table.put(rows: rows, row_count: map_size(rows))
      |> Table.put(page: page && %{page | total: page.total && page.total + 1})
      # the detail first: each goes to the top, so the row ends up above it.
      # `at: 0`, or in place, and no `limit:`: the grid's hook moves the
      # rows LiveView puts before the header after it (`headFirst`), so a
      # position past 0 would count the header
      |> then(fn table ->
        if table.entry.expandable?,
          do:
            Core.effect(
              table,
              {:stream, {:insert, stream, Reading.detail(table, key, nil), [at: 0]}}
            ),
          else: table
      end)
      |> Core.effect({:stream, {:insert, stream, item, [at: 0]}})
      # focus goes to the first stop of the row that was created: the
      # hook focuses the first stop of the row group it is named
      |> Core.effect({:push, "ash_data_table:focus", %{table: id, cell: Ids.row(id, key)}})
    end
  end

  # The panel stays open with what the action said (`Panel.failed/4`): at
  # the fields, and above them what is about no field of the panel. All of
  # it is read out (`Panel.said/2`).
  defp failed(table, panel, message) do
    %{id: id, model: model, panel: open} = table.entry
    uploads = table.context.uploads

    # What the action said of a file is kept with the entry it was said of,
    # where the action has run. The entry is still listed: LiveView drops
    # it after this event.
    files =
      if Panel.ran?(panel, open),
        do:
          Map.new(Panel.file_inputs(panel), fn input ->
            {input.name, Files.entry_ref(Files.upload_of(uploads, id, input))}
          end)

    panel = Panel.failed(panel, model, message, files)

    said =
      for input <- [nil | panel.inputs],
          text <- Files.said_of(panel, input, id, uploads),
          do: {input, text}

    table |> put(panel) |> Core.say(Panel.said(panel, said))
  end

  # What became of a row action, run straight away or from its panel: the
  # page as it is now, and the reply to the hook.
  defp ran({:ok, %Operation.Outcome{record: %_{} = record} = outcome}, table, key, action) do
    {table
     |> Reading.put_action_failure(key, nil)
     |> Reading.put_row(key, record)
     |> Core.say({:text, :action_done, action: action.label})
     |> Core.notify(outcome.event), %{ok: true}}
  end

  # destroyed, or no longer this person's to read: the row is not theirs to
  # see any more
  defp ran({:ok, %Operation.Outcome{gone?: true} = outcome}, table, key, action) do
    {table
     |> Reading.remove_row(key)
     |> Core.say({:text, :action_done, action: action.label})
     |> Core.notify(outcome.event), %{ok: true, removed: true}}
  end

  # A generic action returns no row: the table says what it returned and
  # reads again, as any record may be another by now.
  defp ran({:ok, %Operation.Outcome{} = outcome}, table, _key, action),
    do: {table |> done(action, outcome) |> Core.notify(outcome.event), %{ok: true}}

  defp ran(
         {:error, %Operation.Failure{record: %_{} = record, message: message}},
         table,
         key,
         action
       ) do
    {table
     |> Reading.put_action_failure(key, message)
     |> Reading.put_row(key, record)
     |> Core.say({:text, :action_not_done, action: action.label, message: message}), %{ok: false}}
  end

  # The record is gone, or no longer this person's to read: there is nothing
  # to show the row from, so it stays as it is, and the hook marks the
  # actions cell with the message. A veto says no in the same way.
  defp ran({error, message_or_failure}, table, _key, action) when error in [:error, :halted] do
    message = Operation.message(message_or_failure)

    {Core.say(table, {:text, :action_not_done, action: action.label, message: message}),
     %{ok: false, error: Text.say(message)}}
  end

  defp ran(:refused, table, _key, _action), do: {table, %{ok: false}}

  # A table action that runs straight away (`Operation.run/1`). What came of
  # it is said above the grid, where the outcome of an action on the
  # selected rows is said: there is no row to say it on.
  defp run_table(table, intent, action) do
    case Operation.run(Core.operation(table, intent)) do
      {:ok, %Operation.Outcome{} = outcome} ->
        table |> done(action, outcome) |> Core.notify(outcome.event)

      {error, message_or_failure} when error in [:error, :halted] ->
        text =
          {:text, :action_not_done,
           action: action.label, message: Operation.message(message_or_failure)}

        table |> Table.put(result: %{summary: text, failures: []}) |> Core.say(text)

      :refused ->
        table
    end
  end

  @doc """
  A generic action has run (a row's, the table's, or one on the selection,
  `AshDataTable.Live.Core.Bulk`): the table says what it returned, when
  that can be said in a word or a line, else that it is done, and reads
  again. A file it returned is said by its name and sent to the page to
  save (`Live.Core.download/2`): the table keeps none of it.
  """
  def done(table, action, %Operation.Outcome{value: value, download: download}) do
    text =
      case {download, Format.said(action, value, table.caller.time_zone)} do
        {%{name: name}, _said} -> {:text, :action_result, action: action.label, result: name}
        {nil, nil} -> {:text, :action_done, action: action.label}
        {nil, said} -> {:text, :action_result, action: action.label, result: said}
      end

    table
    |> Table.put(result: %{summary: text, failures: []})
    |> Core.say(text)
    |> Core.download(download)
    |> Reading.reread()
  end
end
