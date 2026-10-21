defmodule AshDataTable.Live.Core.Panel do
  @moduledoc false
  # The action panel over the socket (stage 9d): the 2b adapter of
  # `AshDataTable.Panel`, which is the panel and its life. An intent of the
  # panel's events becomes a function of `Panel`, and what it gives is put
  # into the entry here, with the uploads (`Core.Files`), what the page is
  # told (`Core.Notify`), the live region and focus. Nothing else puts a
  # panel into an entry or takes one out: the other topics open one with
  # `open/4` and close it with `close/1`. And the row actions, the table
  # actions and create, which open a panel or run straight away, and what
  # came of a create or a run.

  import Phoenix.LiveView

  alias AshDataTable.Event
  alias AshDataTable.Format
  alias AshDataTable.Geometry
  alias AshDataTable.Ids
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Files
  alias AshDataTable.Live.Core.Notify
  alias AshDataTable.Live.Core.Picker
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Live.Core.Requests
  alias AshDataTable.Model
  alias AshDataTable.Operation
  alias AshDataTable.Panel
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

  # The host's Confirm of a row action's question (controlled mode).
  def on({:confirmed, {:act, key, name}}, socket), do: act(socket, key, name, true)

  def on({:confirmed, {:table_run, _name} = intent}, socket), do: on(intent, socket)

  # Sent by the button of a table action: the action by name. It has to be
  # one this table offers this person, and the table has to have read: a
  # table that could not read offers nothing.
  #
  # An action with inputs opens the action panel, and nothing runs. One
  # with a question has the hook ask it, and runs when the answer comes
  # (`table_run`). Any other runs now.
  def on({:table_act, name}, socket) do
    %{id: id} = Core.table(socket).entry

    case Operation.table_action(Core.operation(socket, {:table_act, name}), name) do
      %Model.Action{panel?: true} = action ->
        {:ok, socket} = open(socket, :table, %{action: action})
        {:noreply, socket}

      %Model.Action{confirm: question} = action when is_binary(question) ->
        if Requests.controlled?(socket, :confirm),
          do: {:noreply, socket |> yielded() |> Requests.ask({:table_run, name}, action, nil)},
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

  # Sent by the panel's form as the person types: what its fields hold
  # (`Panel.validate/3`); nothing runs.
  def on({:panel_validate, typed}, socket) when is_map(Current.entry(socket, :panel)) do
    %{panel: panel, model: model} = Core.table(socket).entry
    {:noreply, socket |> put(Panel.validate(panel, model, typed)) |> refused_files()}
  end

  # Sent by the panel's form when the person uses its button: the action
  # runs with what the fields hold, and with the files of its uploads,
  # which LiveView has received by then; a filter's panel filters
  # (`Reading.filtered/2`). A wall time that the page's zone does not have
  # runs nothing: the panel says so at its field (`Panel.gaps/3`).
  def on({:panel_submit, typed}, socket) when is_map(Current.entry(socket, :panel)) do
    case Panel.submitted(Core.table(socket).entry.panel, typed) do
      {:filter, filter} -> Reading.filtered(close(socket), filter)
      {:ok, panel} -> filed(socket, panel, typed)
      {:gaps, panel} -> {:noreply, failed(socket, panel, nil)}
    end
  end

  # Sent by the button that adds a value to a field made of groups, or the
  # one that takes a value away: the way to the group, as the names it is
  # sent under. The panel is rendered again with the group, or without it.
  # The panel's hook is told where focus goes (`ash_data_table:focus`).
  def on({event, path}, socket)
      when event in [:panel_add, :panel_remove] and is_map(Current.entry(socket, :panel)) do
    %{id: id, model: model, panel: panel} = Core.table(socket).entry
    change = if event == :panel_add, do: :add, else: :remove

    case Panel.change(panel, model, path, change) do
      {:ok, panel, focus} -> {:noreply, socket |> put(panel) |> focus(Ids.field(id, focus))}
      :error -> {:noreply, socket}
    end
  end

  def on({event, _path}, socket) when event in [:panel_add, :panel_remove],
    do: {:noreply, socket}

  # Sent by the button beside a sensitive field of a row action's panel:
  # "Clear", and "Keep", which takes it back (`Panel.clear/2`). Focus goes
  # back to the button (`ash_data_table:focus`), which a patch that changes
  # what stands before it takes off.
  def on({:panel_clear, name}, socket) when is_map(Current.entry(socket, :panel)) do
    %{id: id, panel: panel} = Core.table(socket).entry

    case Panel.clear(panel, name) do
      {:ok, panel, _input} ->
        {:noreply, socket |> put(panel) |> focus(Ids.clear(Ids.field(id, [name])))}

      :error ->
        {:noreply, socket}
    end
  end

  def on({:panel_clear, _name}, socket), do: {:noreply, socket}

  # Sent by the panel's hook for Cancel and Escape.
  def on(:panel_cancel, socket), do: {:noreply, socket |> close() |> Core.put(picker: nil)}

  # the form of a panel that is no longer open
  def on({event, _typed}, socket) when event in [:panel_validate, :panel_submit],
    do: {:noreply, socket}

  # Sent by the table's create button. The panel opens with the form of the
  # create action; nothing is created yet. A nested table creates under the
  # row it belongs to, which is read first, as the person.
  def on(:create, socket) when is_map(:erlang.map_get(:create, Current.entry(socket, :model))) do
    action = Core.table(socket).entry.model.create

    case Operation.link(Core.operation(socket, :create), action) do
      {:ok, given} ->
        {:ok, socket} = open(socket, :create, %{action: action}, given: given)
        {:noreply, socket}

      # The row is gone, or no longer theirs: said to the live region, and
      # shown by the table itself, which reads again and finds the same.
      :error ->
        {:noreply, socket |> Core.say({:text, :record_gone, []}) |> Reading.reread()}
    end
  end

  def on(:create, socket), do: {:noreply, socket}

  @doc """
  Opens a panel of `kind` for `for` (`AshDataTable.Panel.open/4`), as the
  person asking, and puts it into the entry, with an upload for each of its
  fields that take a file (`Files.allowed/2`). `more` are options of
  `Panel.open/4` besides those the table knows. `{:ok, socket}`; else what
  `Panel.open/4` says, the socket as it was.
  """
  def open(socket, kind, for, more \\ []) do
    %{caller: caller, entry: entry} = Core.table(socket)

    opts =
      [
        id: entry.id,
        time_zone: caller.time_zone,
        reader: Core.reader(socket),
        chooser: Picker.chooser(socket),
        named: &Reading.title_of(entry.model, &1),
        entry: &Picker.entry(&1, &2, caller.time_zone),
        once: &Text.once/1
      ] ++ more

    case Panel.open(kind, for, entry.model, opts) do
      {:ok, panel} -> {:ok, socket |> Files.allowed(panel) |> put(panel)}
      not_opened -> not_opened
    end
  end

  @doc "Puts the open panel as it is now into the entry."
  def put(socket, %Panel{} = panel), do: Core.put(socket, panel: panel)

  @doc "Closes the panel (a new read, a run, Cancel); the picker is the caller's."
  def close(socket), do: Core.put(socket, panel: nil)

  @doc """
  A question held for the host (controlled mode, `Requests.ask/4`) ends a
  panel the host holds: it closes, and the picker over it. Asked before the
  question is held.
  """
  def yielded(socket) do
    if Requests.holds?(socket, :panel),
      do: socket |> close() |> Core.put(picker: nil),
      else: socket
  end

  # A row action, `confirmed?` once its question was answered: by the hook
  # before it sent `act`, or in controlled mode by the host, which the
  # table holds the question for (`Requests.ask/4`).
  defp act(socket, key, name, confirmed?) do
    %{model: model, rows: rows} = Core.table(socket).entry

    with %Model.Action{} = action <- Operation.action(model.actions, name),
         %{} = row <- rows[key] do
      cond do
        action.panel? ->
          open_act(socket, key, row, action)

        is_binary(action.confirm) and not confirmed? and Requests.controlled?(socket, :confirm) ->
          {:reply, %{ok: true},
           socket |> yielded() |> Requests.ask({:act, key, name}, action, row.pk)}

        true ->
          ran(Operation.run(Core.operation(socket, {:act, key, name})), socket, key, action)
      end
    else
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  # A row action with inputs opens the action panel: the record is read
  # again, as the person (`Panel.open/4`). Nothing runs yet. A row action
  # without inputs runs straight away (`Operation.run/1`): see `ran/4`.
  defp open_act(socket, key, row, action) do
    case open(socket, :row, %{key: key, pk: row.pk, action: action}) do
      {:ok, socket} ->
        {:reply, %{ok: true, panel: true}, socket}

      {:error, message} ->
        ran({:error, %Operation.Failure{message: message}}, socket, key, action)
    end
  end

  @doc """
  Tells the panel's hook where focus goes after a button of the panel was
  used (`ash_data_table:focus`): the element of `id`, or the first field in
  it.
  """
  def focus(socket, id),
    do:
      push_event(socket, "ash_data_table:focus", %{table: Core.table(socket).entry.id, cell: id})

  # The files of the panel's uploads, before its action runs (`Files.filed/3`):
  # nothing runs while LiveView does not take a file, or has not received
  # one: that is said, and the panel stays.
  defp filed(socket, panel, typed) do
    case Files.filed(socket, panel) do
      :ok ->
        submit(socket, panel, typed)

      :waiting ->
        {:noreply, Core.say(socket, {:text, :upload_failed, []})}

      {:refused, refused} ->
        {:noreply, socket |> put(Panel.refused(panel, refused)) |> Files.say_files(refused)}
    end
  end

  # What LiveView does not take of the panel's files, read out when it
  # changes: a file is refused as it is chosen, without the panel's button
  # having been used.
  defp refused_files(socket) do
    %{panel: panel} = Core.table(socket).entry

    case Files.refused(socket, panel) do
      refused when refused == panel.refused_files -> socket
      refused -> socket |> put(Panel.refused(panel, refused)) |> Files.say_files(refused)
    end
  end

  # Runs the action of the open panel (`Operation.submit/1`, what
  # `Panel.submission/2` says it is), with the files of its uploads, and
  # shows what came of it (`Panel.outcome/2`). What the action says about a
  # field is shown at the field, and the panel stays open; done, the panel
  # closes and the table says what came of it. A panel whose row, column or
  # action is no longer this person's closes.
  defp submit(socket, panel, typed) do
    result =
      socket
      |> Core.operation(Panel.submission(panel, typed),
        with_files: &Files.attach(socket, panel, &1)
      )
      |> Operation.submit()

    panel = Panel.spend(panel, Files.given(socket, panel, result))

    case Panel.outcome(panel, result) do
      :closed -> {:noreply, close(socket)}
      {:open, panel, message} -> {:noreply, failed(socket, panel, message)}
      {:closed, done} -> closed(close(socket), done)
    end
  end

  defp closed(socket, {:start, action, run, files}),
    do: Core.run({:bulk_start, action, run, files}, socket)

  defp closed(socket, {:saved, key, saved}),
    do: {:noreply, socket |> Reading.put_row(key, saved.record) |> Notify.told(saved.event)}

  defp closed(socket, {:done, action, done}) do
    action =
      Operation.table_action(Core.operation(socket, nil), Atom.to_string(action.name)) || action

    {:noreply, socket |> done(action, done.value) |> Notify.told(done.event)}
  end

  defp closed(socket, {:created, created}) do
    model = Core.table(socket).entry.model
    socket = if created.gone?, do: socket, else: add_row(socket, created.record)

    {:noreply,
     socket
     |> Core.say({:text, :created, name: created_name(model)})
     |> Notify.told(created.event)}
  end

  defp closed(socket, {:ran, key, action, result}) do
    {:reply, _reply, socket} = ran(result, socket, key, action)
    {:noreply, socket}
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

      rows =
        Map.new(rows, fn {key, row} ->
          {key, %{row | rowindex: Geometry.shifted(row.rowindex, :added, first)}}
        end)

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

  # The panel stays open with what the action said (`Panel.failed/4`): at
  # the fields, and above them what is about no field of the panel. All of
  # it is read out (`Panel.said/2`).
  defp failed(socket, panel, message) do
    %{id: id, model: model, panel: open} = Core.table(socket).entry
    uploads = socket.assigns[:uploads]

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

    socket |> put(panel) |> Core.say(Panel.said(panel, said))
  end

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
    message = Operation.message(message_or_failure)

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
           action: action.label, message: Operation.message(message_or_failure)}

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
