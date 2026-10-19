defmodule AshDataTable.Live.Core.Reading do
  @moduledoc false
  # Reading: the read in place or beside the process, what it
  # shows, a row put into the stream or taken out of it, the fill and error
  # messages, the footer summaries beside the read; sort, filter, page and
  # page size.

  require Logger

  import Phoenix.LiveView

  alias AshDataTable.Errors
  alias AshDataTable.Event
  alias AshDataTable.Format
  alias AshDataTable.Ids
  alias AshDataTable.Item
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Notify
  alias AshDataTable.Live.Core.Panel
  alias AshDataTable.Live.Core.Selection
  alias AshDataTable.Live.Core.Url
  alias AshDataTable.Live.Registry
  alias AshDataTable.Model
  alias AshDataTable.Model.Relationship
  alias AshDataTable.Pick
  alias AshDataTable.Present
  alias AshDataTable.Query
  alias AshDataTable.State
  alias AshDataTable.Text

  require AshDataTable.Live.Current, as: Current

  # What the arguments of a state come to for this person: the model with
  # them (`AshDataTable.Model.supply/2`), the arguments the read action
  # requires that are empty, and what Ash refuses of what the person chose,
  # by argument, with what they typed. A value Ash refuses is taken out of
  # the state, and the rest is asked about again without it. Nothing is
  # read for it.
  def settle(model, state, reader, refused \\ %{}) do
    supplied = Model.supply(model, state.arguments)
    %{missing: missing, refused: said} = Query.arguments(supplied, reader)
    # only what a person chose is theirs to be refused
    said = Map.take(said, Map.keys(state.arguments))

    if said == %{} do
      {state, supplied, missing, refused}
    else
      refused =
        for {key, messages} <- said, into: refused do
          {key, %{typed: Map.fetch!(state.arguments, key), messages: messages, held: nil}}
        end

      settle(model, State.withdraw(state, Map.keys(said)), reader, refused)
    end
  end

  # Reads again only when something a read depends on has changed. The first
  # read is done in place, so that the first render has rows; later ones run
  # beside the process, with the previous rows left in view and the grid
  # marked busy.
  #
  # A nested table reads beside the process from the start: its line opens at
  # once, and several that are opened together read side by side. Until its
  # first rows are there it says that it is loading.
  def read(socket) do
    %{model: model, state: state, parent_key: key, parent_arguments: arguments} =
      Core.table(socket).entry

    opts = Core.reader(socket)

    # what the page gives is in the read, and not in what decides whether to
    # read again: `AshDataTable.refresh/2` is how a page reads with new values
    read = {model, state, Keyword.delete(opts, :page_values), key, arguments}

    # The records related to one record are read through that record: those
    # of a nested table, and those a URL limits a table of its own to.
    fetch =
      case model.via do
        %Relationship{} ->
          opts =
            [
              parent_authorize?: Core.table(socket).entry.parent_authorize?,
              parent_arguments: arguments
            ] ++
              opts

          fn -> Query.read_related(model, state, key, opts) end

        nil ->
          fn -> Query.read(model, state, opts) end
      end

    # with every read the summaries are asked for again (`summarise/1`): in
    # any case when the table reads again as it is, else when what they are
    # of has changed
    due = if Core.table(socket).entry.read == :again, do: :force, else: :changed

    cond do
      read == Core.table(socket).entry.read ->
        socket

      # an argument the read action requires is empty: it is not run
      Core.table(socket).entry.missing != [] ->
        first_or_later = if is_nil(Core.table(socket).entry.read), do: :first, else: :later
        socket |> Core.put(read: read) |> due(due) |> unfilled(first_or_later)

      Core.table(socket).entry.read == :again ->
        socket
        |> Core.put(read: read, busy?: true)
        |> due(due)
        |> start_async(Registry.async(socket, :read), fetch)

      Core.table(socket).entry.nested? ->
        socket
        |> Core.put(read: read, busy?: true, loading?: is_nil(Core.table(socket).entry.read))
        |> due(due)
        |> start_async(Registry.async(socket, :read), fetch)

      is_nil(Core.table(socket).entry.read) ->
        socket |> Core.put(read: read) |> due(due) |> show(fetch.(), :first)

      true ->
        socket
        |> Core.put(read: read, busy?: true)
        |> due(due)
        |> start_async(Registry.async(socket, :read), fetch)
    end
  end

  # ---- footer summaries ------------------------------------------------
  #
  # See "Footer summaries" at the top.

  # Notes that the summaries are to be asked for again. What was written or
  # announced (`:force`) is not undone by a read that follows it.
  def due(socket, nil), do: socket

  def due(socket, _due) when Current.entry(socket, :summary_due) == :force, do: socket

  def due(socket, due) when due in [:changed, :force], do: Core.put(socket, summary_due: due)

  # Asks for the summaries, when there is something to ask: beside the
  # process, and beside the read of the rows, which never waits for it. What
  # was shown stays, marked busy, until the answer is there; an answer to an
  # earlier question that comes later is dropped by LiveView, which keeps
  # the last task of a name.
  #
  # After a read (`:changed`) only when what they are of has changed: the
  # sort a person chose says nothing about which records match.
  def summarise(socket) when is_nil(Current.entry(socket, :summary_due)), do: socket

  def summarise(socket) when not Current.entry(socket, :summarised?),
    do: Core.put(socket, summary_due: nil)

  # while an argument the read action requires is empty nothing is read,
  # and nothing summed
  def summarise(socket) when Current.entry(socket, :missing) != [],
    do: Core.put(socket, summary_due: nil, summary: nil, summing?: false, summed: nil)

  def summarise(socket) do
    %{model: model, state: state, parent_key: parent, summary_due: due} =
      Core.table(socket).entry

    opts = read_opts(socket)
    of = {model, %{state | sort: nil}, Keyword.delete(opts, :page_values), parent}
    socket = Core.put(socket, summary_due: nil)

    if due == :changed and of == Core.table(socket).entry.summed do
      socket
    else
      socket
      |> Core.put(summing?: true, summed: of)
      |> start_async(Registry.async(socket, :summary), fn ->
        Query.summaries(model, state, parent, opts)
      end)
    end
  end

  # A summary that could not be computed says so in its cell, and the rows
  # are as they are. What the table's read is refused for is said by the
  # read; anything else is logged.
  defp unsummed(socket, reason) do
    %{model: model} = Core.table(socket).entry

    if not expected?(reason) do
      Logger.error(
        "ash_data_table: the summaries of the table of #{inspect(model.resource)} could not be " <>
          "computed: #{inspect(reason)}"
      )
    end

    unavailable = Map.new(Model.summarised(model), &{&1.name, :unavailable})
    Core.put(socket, summary: unavailable, summing?: false)
  end

  defp expected?(reason) when reason in [:parent_gone, :forbidden], do: true

  defp expected?(%Ash.Error.Forbidden{}), do: true

  defp expected?(_reason), do: false

  # What a read of the table is given besides who is asking: for a nested
  # table, how the row it belongs to is read.
  def read_opts(socket) do
    %{entry: entry} = Core.table(socket)

    [
      parent_authorize?: entry.parent_authorize?,
      parent_arguments: entry.parent_arguments
    ] ++ Core.reader(socket)
  end

  # A read that came back, or went down, while the table waits for an
  # argument its read action requires: it was of other arguments, and
  # nothing of it is shown (`unfilled/2`).
  def handle_async(:read, _result, socket) when Current.entry(socket, :missing) != [],
    do: {:noreply, socket}

  def handle_async(:read, {:ok, result}, socket) do
    {:noreply, socket |> Core.put(busy?: false, loading?: false) |> show(result, :later)}
  end

  def handle_async(:read, {:exit, reason}, socket) do
    {:noreply,
     socket |> Core.put(busy?: false, loading?: false) |> show({:error, reason}, :later)}
  end

  # The summaries, or why there are none (see "Footer summaries" at the
  # top). An answer that comes while the table waits for an argument is of
  # other arguments, as a read is.
  def handle_async(:summary, _result, socket) when Current.entry(socket, :missing) != [],
    do: {:noreply, socket}

  def handle_async(:summary, {:ok, {:ok, summary}}, socket),
    do: {:noreply, Core.put(socket, summary: summary, summing?: false)}

  def handle_async(:summary, {:ok, {:error, reason}}, socket),
    do: {:noreply, unsummed(socket, reason)}

  def handle_async(:summary, {:exit, reason}, socket), do: {:noreply, unsummed(socket, reason)}

  # The read action is not run while an argument it requires is empty: the
  # table has no rows, and says in their place which argument to fill in.
  # That is no error and not "No records". A read that is on its way is of
  # other arguments: it is left to finish, and what it brings is not shown
  # (`handle_async/3`). It is not stopped: a process that is killed in the
  # middle of a statement takes its database connection with it.
  #
  # A person who can never run the read action is not asked to fill in
  # anything: Ash says so without a read (`Ash.can/3`), and they are
  # answered as they are when the read itself is refused.
  defp unfilled(socket, first_or_later) do
    %{model: model, missing: missing} = Core.table(socket).entry
    reader = Core.reader(socket)

    socket = Core.put(socket, busy?: false, loading?: false)

    if Keyword.get(reader, :authorize?, true) and
         Model.Access.forbidden_actions(model.resource, [model.read_action], reader) != [] do
      show(socket, {:error, Ash.Error.Forbidden.exception([])}, first_or_later)
    else
      text = {:text, :fill_in, argument: Enum.map_join(missing, ", ", & &1.label)}

      socket
      |> Core.put(page: nil, row_count: 0, rows: %{}, failed: %{}, announce?: false, gone?: false)
      |> Core.put(error: nil, open: %{}, related_title: nil, panel: nil, picker: nil)
      |> Core.put(fill: text, notice?: false, held: [], leaving: MapSet.new())
      |> stream(Core.table(socket).entry.stream, [], reset: true)
      |> Core.say(text)
    end
  end

  # Shows what a read gave, and tells the host (`:read`, `:read_failed`).
  # `read` says which one it was: the `:first` of this table, done while it
  # is mounted, or a `:later` one.
  defp show(socket, result, read) do
    socket = shown(socket, result, read)
    %{model: model, state: state, row_count: count, error: error} = Core.table(socket).entry

    event =
      case result do
        {:ok, %Query.Page{total: total}} ->
          Event.read(model, state, count, total)

        {:error, reason} ->
          forbidden? = reason == :forbidden or is_struct(reason, Ash.Error.Forbidden)
          Event.read_failed(error && Text.say(error), forbidden?)
      end

    Notify.told(socket, event)
  end

  defp shown(socket, {:ok, %Query.Page{} = page}, _read) do
    %{id: id, model: model} = Core.table(socket).entry

    rows =
      page.records
      |> Enum.with_index()
      |> Enum.map(fn {record, index} ->
        key = row_key(model, record, index)

        %{
          key: key,
          record: record,
          names: names(model, record, key),
          # 1-based, the header rows counted. Under offset pagination it
          # runs through all pages; a keyset page does not know how many
          # records lie before it, and counts from its own top.
          rowindex: (page.offset || 0) + index + Present.header_rows() + 1
        }
      end)

    # each row, and after it its detail when rows can be expanded: closed
    items =
      Enum.flat_map(rows, fn row ->
        current? = current?(Core.table(socket).entry.choose, model, row.record)

        [
          item(socket, row.record, %{
            id: id,
            key: row.key,
            rowindex: row.rowindex,
            names: row.names,
            current?: current?
          })
        ] ++
          if(Core.table(socket).entry.expandable?,
            do: [detail(socket, row.key, nil)],
            else: []
          )
      end)

    socket
    |> Core.put(page: %{page | records: [], parent: nil}, row_count: length(rows))
    |> Core.put(error: nil, gone?: false, related_title: related_title(Core.table(socket), page))
    |> Core.put(fill: nil)
    # what was announced before this read is in it: there is nothing left
    # to read again for, and no row is waiting for its person
    |> Core.put(notice?: false, held: [], leaving: MapSet.new())
    # the rows are other rows now: a panel never acts on a record that the
    # table no longer shows, and neither does a picker
    |> Core.put(panel: nil, picker: nil)
    |> Core.put(
      rows: Map.new(rows, &{&1.key, %{rowindex: &1.rowindex, pk: primary_key(model, &1.record)}}),
      failed: %{},
      open: %{}
    )
    |> announce(page)
    |> stream(Core.table(socket).entry.stream, items, reset: true)
  end

  # The row a nested table belongs to is gone, or no longer this person's to
  # read: nothing is known about its related records, which is not the same
  # as there being none.
  defp shown(socket, {:error, :parent_gone}, _read),
    do: show_message(socket, {:text, :record_gone, []})

  # A nested table whose destination this person may not read, in either of
  # the two ways Ash says so. Its line has told them that there is a table,
  # so it says something in every case: that they are not allowed when the
  # destination's table is declared with `on_forbidden :message`, and no more
  # than that the records are not available otherwise. Never "No records".
  defp shown(socket, {:error, refusal}, _read)
       when Current.entry(socket, :nested?) and
              (refusal == :forbidden or is_struct(refusal, Ash.Error.Forbidden)) do
    case Core.table(socket).entry.model.on_forbidden do
      :message -> show_message(socket, {:text, :not_allowed, []})
      :not_found -> show_message(socket, {:text, :records_not_available, []})
    end
  end

  # A table to choose from whose read is refused: the picker has told the
  # person that there is a table, so it says something in every case, as a
  # nested table does.
  defp shown(socket, {:error, %Ash.Error.Forbidden{}}, _read)
       when is_map(Current.entry(socket, :choose)) do
    case Core.table(socket).entry.model.on_forbidden do
      :message -> show_message(socket, {:text, :not_allowed, []})
      :not_found -> show_message(socket, {:text, :records_not_available, []})
    end
  end

  # A table of its own that is limited to related records, whose destination
  # this person may not read: Ash put its refusal in place of the records.
  # It is the refusal of this table's read, as below.
  defp shown(socket, {:error, :forbidden}, read),
    do: shown(socket, {:error, Ash.Error.Forbidden.exception([])}, read)

  # A read the resource refuses outright. Unless the table is declared with
  # `on_forbidden :message`, the person is not told that there is a table:
  # nothing of it is rendered, and a table that is a page of its own answers
  # as a page that does not exist.
  defp shown(socket, {:error, %Ash.Error.Forbidden{} = error}, read) do
    case Core.table(socket).entry.model.on_forbidden do
      :message -> show_error(socket, error)
      :not_found -> socket |> show_error(error) |> Core.put(gone?: true) |> not_found(read)
    end
  end

  defp shown(socket, {:error, error}, _read), do: show_error(socket, error)

  defp show_error(socket, error),
    do: show_message(socket, error_text(error, Core.table(socket).entry.model))

  # The message is an alert of its own, in place of the rows.
  defp show_message(socket, text) do
    socket
    |> Core.put(page: nil, row_count: 0, rows: %{}, failed: %{}, announce?: false, gone?: false)
    # nothing is said of a record that was not read for this person
    |> Core.put(error: text, open: %{}, related_title: nil, panel: nil, picker: nil)
    |> Core.put(fill: nil, notice?: false, held: [], leaving: MapSet.new())
    |> stream(Core.table(socket).entry.stream, [], reset: true)
  end

  # A table placed in a page of the host's cannot make that page disappear:
  # it renders nothing.
  defp not_found(socket, _read) when not Current.option(socket, :mounted?), do: socket

  # While the page is mounted, the first read is the request's: the table
  # is `gone?`, and the page raises (`AshDataTable.Live.Page`,
  # `AshDataTable.NotFoundError`).
  defp not_found(socket, :first), do: socket

  # Later, the page is on screen. The browser is sent to ask for it afresh,
  # which raises the exception; nothing crashes for it.
  defp not_found(socket, :later) do
    uri = URI.parse(Core.table(socket).options.url)
    redirect(socket, to: %URI{path: uri.path || "/", query: uri.query} |> URI.to_string())
  end

  # Whether a record of a table to choose from is the one the key points at
  # now: the row the picker opens with, where it is on the page.
  defp current?(%{current: {attribute, value}}, model, record),
    do:
      Pick.current?(
        %{destination: model.resource, destination_attribute: attribute},
        record,
        value
      )

  defp current?(_choose, _model, _record), do: false

  # The rows that are selected as a table to choose several records from
  # What the hook tells the server of a selected row is the row's primary
  # key. Where that is one value and the key in the row's DOM id is that
  # value as it is written, the hook reads it there, and this is nil. For
  # every other row (a key of several attributes, a value that had to be
  # encoded for an id) the values are said on the row itself, in the order
  # of the primary key, as they are written.
  def names(%{primary_key: [field]}, key, row_key) do
    value = key |> Map.get(field) |> to_string()
    if value != row_key, do: [value]
  end

  def names(%{primary_key: fields}, key, _row_key),
    do: Enum.map(fields, &(key |> Map.get(&1) |> to_string()))

  # The item of a record's row (`AshDataTable.Item`): the record scrubbed
  # (`Present.row/3`), each cell with its text, as the person reads it now.
  def item(socket, record, attributes) do
    %{caller: caller, entry: entry} = Core.table(socket)

    Item.row(entry.model, Present.row(entry.model, record, attributes), %{
      time_zone: caller.time_zone,
      editing?: entry.editing?,
      selecting: entry.selecting
    })
  end

  # The detail of a row as the stream holds it (`AshDataTable.Item`): what
  # is under an expanded row. `lines` are the names of its open lines, nil
  # while the row is not expanded; the counts of its open nested tables are
  # the entry's, where they are known. No record is needed for it.
  def detail(socket, key, lines) do
    %{id: id, model: model, counts: counts} = Core.table(socket).entry
    Item.detail(model, id, key, lines, Map.get(counts, key, %{}))
  end

  # Puts a row of the page into the stream again, in its place: with the
  # record as an action returned it or as it was read again, and with the
  # edits of the row that have failed. Its detail is another item and stays
  # as it is: what is open under the row stays open.
  def put_row(socket, key, record) do
    %{id: id, model: model, rows: rows, failed: failed, open: open} = Core.table(socket).entry
    names = names(model, record, key)
    # in a table to choose from: whether this is the record chosen now
    current? = current?(Core.table(socket).entry.choose, model, record)

    # a row is put back after something was done with its record
    socket
    |> due(:force)
    |> stream_insert(
      Core.table(socket).entry.stream,
      item(socket, record, %{
        id: id,
        key: key,
        rowindex: rows[key].rowindex,
        failed: failed[key],
        open?: is_map_key(open, key),
        names: names,
        current?: current?
      })
    )
  end

  # Puts the detail of a row into the stream again, in its place, as `open`
  # says it is now. A nested table that stays open is rendered again and
  # reads nothing for it; one that is no longer rendered is gone, with its
  # state.
  def put_detail(socket, key) do
    stream_insert(
      socket,
      Core.table(socket).entry.stream,
      detail(socket, key, Core.table(socket).entry.open[key])
    )
  end

  # Notes that the save of a cell has failed, or with `nil` that it no longer
  # has. What was typed is kept with the action's message, and no record: a
  # failed row that is put back again is read again for it (`put_read/2`).
  def put_failure(socket, key, name, failure) do
    row = Core.table(socket).entry.failed[key] || %{}
    cells = Map.get(row, :cells, %{})
    cells = if failure, do: Map.put(cells, name, failure), else: Map.delete(cells, name)

    put_failed(socket, key, %{cells: cells, action: Map.get(row, :action)})
  end

  # Notes that a row action has failed, with the action's message, or with
  # `nil` that the row's actions cell has nothing to say any more.
  def put_action_failure(socket, key, message) do
    row = Core.table(socket).entry.failed[key] || %{}

    put_failed(socket, key, %{cells: Map.get(row, :cells, %{}), action: message})
  end

  def put_failed(socket, key, %{cells: cells, action: nil}) when cells == %{},
    do: Core.put(socket, failed: Map.delete(Core.table(socket).entry.failed, key))

  def put_failed(socket, key, failures),
    do: Core.put(socket, failed: Map.put(Core.table(socket).entry.failed, key, failures))

  # Puts a row of the page back with its record read again as the person,
  # as a live update reads one (`Query.rows/4`): through the table's read
  # action, and for a nested table through its parent. A record that does
  # not come back is no row of the page any more.
  def put_read(socket, key) do
    %{model: model, parent_key: parent, rows: rows} = Core.table(socket).entry

    case rows do
      %{^key => %{pk: pk}} ->
        case Query.rows(model, parent, [pk], read_opts(socket)) do
          {:ok, [record]} -> put_row(socket, key, record)
          {:ok, []} -> remove_row(socket, key)
          {:error, _error} -> reread(socket)
        end

      _not_on_the_page ->
        socket
    end
  end

  # Takes a row out of the page, with its detail and so with everything that
  # is open under it: its record is no more. The rows after it move up by
  # one, and the total is one less: of what the last read counted, this
  # record is gone for certain. A page that is left without rows is read
  # again.
  def remove_row(socket, key) do
    %{id: id, rows: rows, page: page} = Core.table(socket).entry
    %{rowindex: removed, pk: pk} = rows[key]

    rows =
      rows
      |> Map.delete(key)
      |> Map.new(fn {key, row} ->
        {key, if(row.rowindex > removed, do: %{row | rowindex: row.rowindex - 1}, else: row)}
      end)

    socket =
      socket
      |> Core.put(rows: rows, row_count: map_size(rows))
      |> Core.put(failed: Map.delete(Core.table(socket).entry.failed, key))
      |> Core.put(open: Map.delete(Core.table(socket).entry.open, key))
      |> Core.put(leaving: MapSet.delete(Core.table(socket).entry.leaving, key))
      |> Core.put(page: %{page | total: page.total && max(page.total - 1, 0)})
      |> stream_delete_by_dom_id(Core.table(socket).entry.stream, Ids.row(id, key))
      |> stream_delete_by_dom_id(Core.table(socket).entry.stream, Ids.detail(Ids.row(id, key)))
      |> Selection.gone(pk)
      |> due(:force)

    if rows == %{}, do: reread(socket), else: socket
  end

  # A row that is gone is selected no longer: the hook, which alone knows
  # what is selected, is told.
  # Reads the page again as it is asked for now, beside the process.
  def reread(socket), do: socket |> Core.put(read: :again) |> read()

  def primary_key(%{primary_key: primary_key}, record), do: Map.take(record, primary_key)

  # What the record is called that a table of its own is limited to: what
  # its resource's table calls a record by, as far as this person may see it
  # on this record. Taken from the record as it was read for them, and from
  # nothing else: a record that was not read has no name here.
  defp related_title(
         %{entry: %{related: %{via: via}}} = table,
         %Query.Page{parent: %_{} = parent}
       ),
       do:
         via.source
         |> Model.build(table: via.source_table)
         |> Model.zoned(table.caller.time_zone)
         |> Core.in_words()
         |> title_of(parent)

  defp related_title(_table, _page), do: nil

  # What a record is called: by the first of the columns its table names a
  # record by that holds something this person may see on it. Nil when none
  # does.
  def title_of(model, record) do
    case label(model, record) do
      {column, value} -> Format.format(column, value, model.time_zone)
      nil -> nil
    end
  end

  # The same as a value, with its column (`AshDataTable.Present.label/3`):
  # a value whose text would be blank calls nothing.
  def label(model, record) do
    Present.label(model, record, fn column, value ->
      is_nil(blank_as_nil(Format.format(column, value, model.time_zone)))
    end)
  end

  def blank_as_nil(text), do: if(String.trim(text) != "", do: text)

  # After a filter change, the result is put into the live region: the count
  # when the read action counts, under either pagination strategy, else
  # only that the rows have changed.
  defp announce(socket, page) when Current.entry(socket, :announce?) do
    text =
      case page.total do
        nil -> {:text, :results_updated, []}
        total -> {:text, :results, count: total}
      end

    socket |> Core.put(announce?: false) |> Core.say(text)
  end

  defp announce(socket, _page), do: socket

  defp error_text(%Ash.Error.Forbidden{}, _model), do: {:text, :not_allowed, []}

  # What the read action returned on purpose is shown as it is: an argument
  # or a filter it does not accept, a validation of its own. Anything else is
  # a failure a person can do nothing about and should not be shown the
  # inside of: it goes to the log, and the table says only that it failed.
  defp error_text(error, model) do
    case Errors.of_read(error, model) do
      [] ->
        log_failed_read(error, model)
        {:text, :read_failed, []}

      messages ->
        {:once, "; ", messages}
    end
  end

  # A failure underneath is an error for whoever runs the application. An
  # error of the invalid class that has no message for a person (a keyset
  # cursor that somebody altered in the URL, say) is not.
  defp log_failed_read(error, model) do
    text = if is_exception(error), do: Exception.message(error), else: inspect(error)

    message =
      "ash_data_table: the read `#{model.read_action}` of #{inspect(model.resource)} failed: "

    case error do
      %Ash.Error.Invalid{} -> Logger.warning(message <> text)
      _other -> Logger.error(message <> text)
    end
  end

  # The primary key as a DOM id. A resource without one falls back to the
  # position in the page.
  def row_key(%{primary_key: []}, _record, index), do: "n#{index}"

  def row_key(%{primary_key: primary_key}, record, _index) do
    Enum.map_join(primary_key, "-", fn field ->
      value = record |> Map.get(field) |> to_string()

      if value =~ ~r/\A[A-Za-z0-9_-]+\z/,
        do: value,
        else: "b" <> Base.url_encode64(value, padding: false)
    end)
  end

  def on({:sort, name}, socket) do
    %{state: state, model: model} = Core.table(socket).entry
    {:noreply, Url.go(socket, State.cycle_sort(state, model, name))}
  end

  # Sent by the form of the filter row when a filter is left or a choice is
  # made, with every filter of the row.
  def on({:filter, form}, socket) do
    %{state: state, model: model} = Core.table(socket).entry

    {filtered, rejected} = State.filter(state, model, form)
    pending = %{controls: State.pending(model, form), among: [state.filters, filtered.filters]}

    {:noreply, socket |> Core.put(rejected: rejected, pending: pending) |> Url.refilter(filtered)}
  end

  # Sent by the button of a filter for several of a column's values ("is
  # any of", "is none of"): the side panel opens with a box per value of the
  # column, ticked as the filter applies, as a form of its own; nothing is
  # filtered until it is sent (`filtered/2`). The column and the operator
  # are claims: one of the column's operators, which takes several values.
  def on({:filter_values, name, operator}, socket) do
    %{model: model, state: state} = Core.table(socket).entry

    with %{} = column <-
           Enum.find(model.columns, &(Atom.to_string(&1.name) == name and &1.operators != [])),
         %{} = takes <- column.takes,
         op when not is_nil(op) <- Enum.find(column.operators, &(Atom.to_string(&1) == operator)),
         :many <- Map.get(takes, op) do
      chosen =
        case state.filters[column.name] do
          {^op, values} when is_list(values) -> Enum.map(values, &to_string/1)
          _none -> []
        end

      panel =
        Panel.panel(socket, fn _input -> nil end, %{
          kind: :filter,
          action: nil,
          key: nil,
          column: column.name,
          operator: op,
          form: nil,
          inputs: [Model.filter_input(column)],
          values: chosen,
          title: {:text, :filter, column: column.label},
          submit: {:text, :apply, []}
        })

      {:noreply, Core.put(socket, panel: panel)}
    else
      _none -> {:noreply, socket}
    end
  end

  def on({:clear_filter, name}, socket) do
    %{state: state, pending: pending} = Core.table(socket).entry
    cleared = State.clear_filter(state, name)

    # the other columns keep the controls they show
    pending = %{
      controls:
        Map.reject(pending.controls, fn {column, _} -> Atom.to_string(column) == name end),
      among: [state.filters, cleared.filters]
    }

    {:noreply, socket |> Core.put(pending: pending) |> Url.refilter(cleared)}
  end

  def on(:clear_filters, socket) do
    state = State.clear_filters(Core.table(socket).entry.state)

    {:noreply,
     socket
     |> Core.put(rejected: %{}, pending: %{controls: %{}, among: []})
     |> Url.refilter(state)}
  end

  def on({:page, to}, socket) do
    {:noreply, Url.go(socket, target(Core.table(socket).entry, to))}
  end

  # Sent by the "Rows per page" menu: the size as text. It is a claim: only
  # a size the table offers is taken (`AshDataTable.State.resize/3`), and
  # anything else changes nothing. The table starts at its first page with
  # it, as after a new sort; the sort, the filters and the arguments stay.
  def on({:page_size, size}, socket) do
    %{state: state, model: model} = Core.table(socket).entry
    {:noreply, Url.go(socket, State.resize(state, model, size))}
  end

  @doc """
  The side panel of a filter for several values was sent: the column is
  filtered by the values that were ticked, with the panel's operator, and
  the panel goes. The other filters stay as they are. A value that is none
  of the column's is no filter (`AshDataTable.State.filter_column/4`).
  """
  def filtered(socket, typed) do
    %{panel: panel, state: state, model: model, pending: pending} = Core.table(socket).entry
    name = Atom.to_string(panel.column)

    values =
      case typed do
        %{^name => [_own | values]} -> Enum.filter(values, &is_binary/1)
        _none -> []
      end

    entry = %{"o" => Atom.to_string(panel.operator), "in" => values}
    filtered = State.filter_column(state, model, name, entry)

    # the filter row shows the operator still, with no value ticked
    pending = %{
      controls:
        pending.controls
        |> Map.delete(panel.column)
        |> Map.merge(State.pending(model, %{name => entry})),
      among: [state.filters, filtered.filters]
    }

    {:noreply,
     socket
     |> Core.put(panel: nil, pending: pending)
     |> Url.refilter(filtered)}
  end

  defp target(%{page: %{previous: %State{} = state}}, "previous"), do: state

  defp target(%{page: %{next: %State{} = state}}, "next"), do: state

  defp target(%{state: state, model: %{pagination: %{strategy: :offset}}} = assigns, to) do
    with {number, ""} when number > 0 <- Integer.parse(to),
         true <-
           is_nil(assigns.page) or is_nil(assigns.page.pages) or number <= assigns.page.pages do
      State.to_page(state, number)
    else
      _ -> state
    end
  end

  defp target(%{state: state}, _to), do: state
end
