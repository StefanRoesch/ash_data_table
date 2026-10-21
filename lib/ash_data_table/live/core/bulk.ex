defmodule AshDataTable.Live.Core.Bulk do
  @moduledoc false
  # Actions on the selected rows: the question, the panel, and
  # the run beside the process, with its outcome.

  require Logger

  import Phoenix.LiveView

  alias AshDataTable.Caller
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Opener
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Live.Core.Selection
  alias AshDataTable.Live.Registry
  alias AshDataTable.Model
  alias AshDataTable.Operation
  alias AshDataTable.Table
  alias AshDataTable.Text

  # What became of an action that ran on the selected rows: said above the
  # grid and read out, and the hook is told on which rows it did not run,
  # by their keys and by what it names them by: those stay selected. The
  # table is read again, as the page may hold any of the records.
  #
  # A run goes on to its end when who is asking changes meanwhile: it was
  # started as the person who could, and stopping it would leave it half
  # done. What it came to is said to that person only, whose role or scope
  # may have changed (`AshDataTable.Caller.who/1`): another is told nothing
  # of it, and the table reads again as them.
  def handle_async(:bulk, result, socket) do
    %{caller: caller, entry: %{running: %{by: by}}} = Core.table(socket)

    # the host is told what was done, whoever asks now
    socket =
      case result do
        {:ok, %{event: event}} -> Core.notify(socket, event)
        _exit -> socket
      end

    if Caller.who(caller) == by,
      do: ran(result, socket),
      else: {:noreply, ended(socket, result)}
  end

  defp ran({:ok, outcome}, socket) do
    %{model: model, running: %{action: action}} = Core.table(socket).entry
    not_done = Enum.sum(for {_message, count} <- outcome.failures, do: count)
    # what says the same words is one failure, as it is said in this process
    outcome = %{outcome | failures: Text.counted(outcome.failures)}

    summary =
      if not_done == 0,
        do: {:text, :bulk_done, action: action.label, done: outcome.done},
        else: {:text, :bulk_not_done, action: action.label, done: outcome.done, failed: not_done}

    failures =
      for {message, count} <- outcome.failures,
          do: {:text, :bulk_failure, message: message, count: count}

    # the rows it did not run on stay selected, and no others
    failed = {:rows, Enum.map(outcome.failed, &Selection.named(model, &1))}

    socket =
      socket
      |> Core.put(running: nil, result: %{summary: summary, failures: failures})
      |> Core.say({:join, " ", [summary | failures]})

    {:noreply,
     socket
     |> Core.stepped(Selection.put(Core.table(socket), failed, true))
     |> Reading.reread()}
  end

  # The run itself went down. What it had done by then is not known: the
  # rows stay selected, and the table is read again.
  defp ran({:exit, reason}, socket) do
    %{running: %{action: action}} = Core.table(socket).entry
    went_down(socket, reason)

    summary =
      {:text, :action_not_done, action: action.label, message: {:text, :action_failed, []}}

    {:noreply,
     socket
     |> Core.put(running: nil, result: %{summary: summary, failures: []})
     |> Core.say(summary)
     |> Reading.reread()}
  end

  # A run that ended for a person who did not start it: the table is no
  # longer busy, the hook is told that it is over, and the rows are read
  # again as the person asking now.
  defp ended(socket, result) do
    with {:exit, reason} <- result, do: went_down(socket, reason)

    socket
    |> Core.put(running: nil, result: nil)
    |> Reading.reread()
  end

  defp went_down(socket, reason) do
    %{model: model, running: %{action: action}} = Core.table(socket).entry

    Logger.error(
      "ash_data_table: running `#{action.name}` on the selected rows of #{inspect(model.resource)} " <>
        "failed: #{inspect(reason)}"
    )
  end

  # Sent by the hook when the person changes the selection while the table
  # still says what the last run came to: that is said no longer. A step
  # over the table (stage 9g).
  def step(:bulk_seen, table, _context), do: {Table.put(table, result: nil), [], nil}

  # Sent by the hook when a person uses a button of the line above the grid,
  # on what they have selected (`AshDataTable.Live.Core.Selection`): `rows`,
  # each as the hook names it (its primary key), or every record the filters
  # match. Nothing runs yet: an action with inputs opens its panel, and for
  # any other the answer is the question to ask first, which says how many
  # records it is about, with a token of the selection it names
  # (`Selection.token/1`), which Confirm sends back.
  #
  # The action has to be one this table offers this person for a selection.
  # The rows are not looked up among those of the page, as a selection
  # outlives its page: they are claims, and the run reads each as the
  # person before anything is done to it (`AshDataTable.Bulk`).
  def on({:bulk, name} = intent, socket) do
    case Operation.bulk_action(
           Core.operation(Core.table(socket), Core.context(socket), intent),
           name
         ) do
      {:ok, action, selection} ->
        %{entry: entry} = Core.table(socket)
        question = question(action, selected(selection, entry))
        token = Selection.token(entry)

        if action.panel? do
          {:reply, %{panel: true}, open_bulk(socket, action, selection, question)}
        else
          # the hook asks it, or the host does (controlled mode)
          case Opener.ask(socket, {:bulk_run, name, token}, question, %{action: name}) do
            {:run, socket} -> {:reply, %{ask: Text.say(question), selection: token}, socket}
            {:held, _reply, socket} -> {:reply, %{ok: true}, socket}
          end
        end

      :error ->
        {:reply, %{ok: false}, socket}
    end
  end

  # Sent by the hook once the person has answered that question with
  # Confirm, for an action without a panel: the action runs on what is
  # selected. Whether it has a panel is the table's to say, not the event's.
  #
  # Only on the selection the question named: a question in the page leaves
  # the page in use, and the selection may change before it is answered
  # (as it may while a host asks it, in controlled mode). Then nothing runs,
  # and the person is told why.
  def on({:bulk_run, name, token}, socket) do
    input = Core.operation(Core.table(socket), Core.context(socket), {:bulk_run, name})

    with {:ok, action, _selection} <- Operation.bulk_action(input, name),
         :named <- named(socket, token),
         {:start, run, files} <- Operation.bulk(input) do
      {:noreply, start_bulk(socket, action, run, files)}
    else
      :changed ->
        changed = {:text, :bulk_selection_changed, []}

        {:noreply,
         socket
         |> Core.put(result: %{summary: changed, failures: []})
         |> Core.say(changed)}

      {:halted, message} ->
        {:noreply, Core.say(socket, message)}

      _other ->
        {:noreply, socket}
    end
  end

  # The host's Confirm of the question before a run (controlled mode).
  def on({:confirmed, {:bulk_run, _name, _token} = intent}, socket), do: on(intent, socket)

  # What came of the panel of an action on the selection: its run, handed
  # back to be started (`AshDataTable.Live.Core.Panel`).
  def on({:bulk_start, action, run, files}, socket),
    do: {:noreply, start_bulk(socket, action, run, files)}

  # Whether what is selected is what the token names.
  defp named(socket, token),
    do: if(token == Selection.token(Core.table(socket).entry), do: :named, else: :changed)

  # How many records a selection is: the rows that were named, or what the
  # last read counted, nil where the read action does not count.
  defp selected(:all, %{page: page}), do: page.total

  defp selected({:rows, rows}, _assigns), do: length(Enum.uniq(rows))

  # What is asked before an action runs on the selected rows: always
  # something, with the number of records. An action with a question of
  # its own asks that, and the number follows it.
  defp question(%Model.Action{confirm: nil, label: label}, nil),
    do: {:text, :bulk_question_all, action: label}

  defp question(%Model.Action{confirm: nil, label: label}, count),
    do: {:text, :bulk_question, count: count, action: label}

  defp question(%Model.Action{confirm: question}, nil),
    do: {:text, :bulk_confirm_all, question: question}

  defp question(%Model.Action{confirm: question}, count),
    do: {:text, :bulk_confirm, count: count, question: question}

  # The panel of an action that is to run on the selected rows
  # (`AshDataTable.Live.Core.Panel.open/4`), which asks its question before it runs.
  defp open_bulk(socket, action, selection, question) do
    count = selected(selection, Core.table(socket).entry)

    {:ok, socket} =
      Core.Panel.open(socket, :bulk, %{action: action, selection: selection, count: count},
        question: question
      )

    socket
  end

  # Runs an action on the selected rows, beside the process: a run takes as
  # long as its records are many, and the page stays in use meanwhile. The
  # grid is marked busy until `handle_async/3` has the outcome. An open
  # panel closes.
  #
  # A run goes on to its end when the page is left or the table closes
  # meanwhile, and what it came to is dropped (`Registry.finishing/1`):
  # stopped, it would leave a record's transaction in the middle of a
  # statement. `files` are the copies of the panel's files it runs with
  # (`Core.Files.attach/3`): they are handed to the run's process, and go
  # when it ends (`Plug.Upload.give_away/3`), whether the page is there
  # then or not. A hand-over that fails (the page went before the run
  # could take them, and its copies with it) ends the run before it
  # starts, and its answer is dropped with the page.
  defp start_bulk(socket, action, run, files) do
    view = self()
    copies = for {_name, %{path: path}} <- files, do: path

    socket
    |> Core.Panel.close()
    # who started it: what it comes to is said to that person only
    |> Core.put(
      running: %{action: action, by: Caller.who(Core.table(socket).caller)},
      result: nil
    )
    # The run says why a record was not done as message terms: their words
    # are made when the outcome is drawn, in this process, whose locale it is.
    |> start_async(
      Registry.async(socket, :bulk),
      Registry.finishing(fn ->
        Enum.each(copies, fn copy -> :ok = Plug.Upload.give_away(copy, self(), view) end)
        run.()
      end)
    )
  end
end
