defmodule AshTable.Live.TableComponent do
  @moduledoc false
  # The table itself: a grid whose rows live in a LiveView stream.
  #
  # The server keeps the table model, the state (sort, filters and position),
  # what the last read said about the pages, the primary keys of the rows of
  # the page and the edits that failed; it does not keep the records. A change
  # of sort, filter or page reads again and resets the stream.
  #
  # Editing a cell is the hook's until the value is saved: it opens the
  # column's editor in the cell and sends one `save` event with the row, the
  # column and the value as typed. The server reads the record again, runs the
  # column's update action and puts the row back into the stream.
  #
  # Markup contract (spec sections 7.2 and 13):
  #
  #   * the `<table role="grid">` is the stream container; the header is a
  #     child with its own id and every row is one `<tbody>`;
  #   * the header has two rows, the column headers and the filter row, which
  #     are not part of the stream. The controls of the filter row belong to
  #     the form `ID-filters`, which sits outside the table;
  #   * ids are stable and built from names, never from positions:
  #     `ID-head-FIELD` for a header cell, `ID-filter-FIELD` for a filter cell
  #     (its controls end in `-operator`, `-value` and `-clear`), `ID-row-KEY`
  #     for a row's `<tbody>` and `ID-row-KEY-c-FIELD` for a cell;
  #   * `aria-colindex` is computed through `colindex/2`, which counts the
  #     leading expander column in when the table has one; an actions column
  #     goes after the last data column, which holds no cell yet.
  #
  # ## Nested tables
  #
  # A table whose rows offer relationships, to this person and at this depth,
  # has a first column of expanders. The stream then holds two items per
  # record, both `<tbody>`s: the row (`ID-row-KEY`) and, right after it, its
  # detail (`ID-row-KEY-x`), which is empty and hidden until the row is
  # expanded. Expanded, the detail holds one line per relationship
  # (`ID-row-KEY-l-NAME`, with its cell `…-c` and its button `…-b`) and, under
  # an open line, a row (`ID-row-KEY-n-NAME`) whose one cell (`…-c`) spans the
  # table and holds the nested table: this same component once more, under
  # the id `ID-row-KEY-t-NAME`, which prefixes every id in it.
  #
  # The detail is an item of its own so that opening and closing never needs
  # the record again, which the server does not keep: a toggle puts the
  # detail back into the stream and leaves the row alone, and a save puts the
  # row back and leaves the detail alone. What the server keeps for it is
  # which rows are expanded and which of their lines are open (`open`). A
  # new read forgets both, as it forgets the failed edits.
  #
  # A nested table is given the relationship it is reached through (`via`)
  # and the primary key of the row it belongs to (`parent_key`); it reads
  # through `AshTable.Query.read_related/4`, when it is opened and whenever
  # its own sort, filters or page change. Its state is never in the URL.
  # `depth` counts from the table on the page, which is at 0, and
  # `depth_limit` is that table's `max_depth`.
  #
  # ## The full view
  #
  # The last row of a nested table's grid holds a link to the page the host's
  # router mounts the destination's table at, when it mounts one
  # (`ID-full-view` in the cell `ID-view`). That page shows the same records:
  # its table's parameter `of` names the row and the relationship
  # (`AshTable.Related`).
  #
  # A table with its state in the URL reads that parameter. Limited by it,
  # the table is what a nested table is, read the same way, with `via` and
  # `parent_key` taken from the URL; only that it is not `nested?` in
  # another, and so looks and behaves as a table of its own. Above its grid
  # it says what it shows (`ID-related`: the heading `ID-related-heading`
  # and the control `ID-related-clear`, which takes the limit away).
  #
  # Use it through `AshTable.table/1`.
  use Phoenix.LiveComponent

  require Logger

  alias AshTable.Edit
  alias AshTable.Errors
  alias AshTable.Format
  alias AshTable.Model
  alias AshTable.Model.Operator
  alias AshTable.Model.Relationship
  alias AshTable.Query
  alias AshTable.Related
  alias AshTable.Resource.Info, as: TableInfo
  alias AshTable.Routes
  alias AshTable.State
  alias AshTable.Text
  alias Phoenix.LiveView.JS

  # The rows above the data rows: the header and the filter row.
  @header_rows 2

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> stream_configure(:rows, dom_id: & &1.dom_id)
     # a nested table is rendered before its first read has come back
     |> stream(:rows, [])
     |> assign(state: %State{}, page: nil, error: nil, row_count: 0, busy?: false, read: nil)
     # Whether the table is a page of its own, which a refused read can turn
     # into "not found", and whether a refused read has left it with nothing
     # to show at all.
     |> assign(mounted?: false, gone?: false)
     # The rows of the page by the key in their DOM id: each one's primary key
     # and row index. What an edit event names is looked up here.
     |> assign(rows: %{})
     # The edits that failed, by row key: what was typed into each cell with
     # the action's message, and the record, as a failed row is rendered more
     # than once. A new read forgets them.
     |> assign(failed: %{})
     # What the live region says, and how often it has spoken. `announce?` is
     # set by a filter change and answered by the read that follows it.
     |> assign(announce?: false, announcement: nil, announcements: 0)
     # What a person typed into a filter that is not a value of its column:
     # shown in the filter, marked, and not applied.
     |> assign(rejected: %{})
     # The rows that are expanded, by row key: the names of their open
     # lines. A new read forgets them.
     |> assign(open: %{})
     # What makes a table a nested one: the relationship it is reached
     # through and the primary key of the row it belongs to. `depth` counts
     # from the table on the page; `depth_limit` is that table's `max_depth`.
     |> assign(via: nil, parent_key: nil, parent_authorize?: true, depth: 0, depth_limit: nil)
     # The ids of the elements that name a nested table's grid, in place of
     # `label`; and whether its first read is still on its way.
     |> assign(labelledby: nil, loading?: false)
     # Whether the table is inside a row of another. What the URL limits a
     # table of its own to (`AshTable.Related`), and what the record it is
     # limited to is called, once that record has been read for the person.
     # Where a nested table's records are shown in the full view.
     |> assign(nested?: false, related: nil, related_title: nil, full_view: nil)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      assign(
        socket,
        Map.take(
          assigns,
          [:id, :resource, :scope, :actor, :tenant, :url, :label, :mounted?] ++
            [:via, :parent_key, :parent_authorize?, :depth, :depth_limit, :labelledby]
        )
      )

    # Unless the table is told, it authorizes as its resource's domain says.
    # What it was told is kept as it was given, for the tables nested in it.
    socket =
      assign(socket,
        authorize_given: assigns[:authorize?],
        authorize?:
          case assigns[:authorize?] do
            nil -> AshTable.Domain.Info.authorize?(socket.assigns.resource)
            authorize? -> authorize?
          end
      )

    socket = socket |> assign(nested?: socket.assigns.depth > 0) |> relate()

    # The table as the person asking meets it: without the columns they can
    # never see, and with the columns they can never edit read-only. Ash is
    # asked again on every update, which for a table with its state in the
    # URL is every sort, filter and page change; it costs no query.
    model =
      socket.assigns.resource
      |> Model.build(via: socket.assigns.via)
      |> Model.for_actor(reader(socket.assigns))
      |> in_words()

    state = current_state(socket.assigns, model)

    # How deep a person can expand is said by the table on the page, for
    # everything beneath it.
    depth_limit = socket.assigns.depth_limit || model.max_depth

    {:ok,
     socket
     |> assign(model: model, state: state, editing?: Enum.any?(model.columns, & &1.editable?))
     |> assign(depth_limit: depth_limit)
     |> assign(expandable?: expandable?(model, socket.assigns.depth, depth_limit))
     |> read()}
  end

  # What makes the table one of related records. A nested table is told by
  # the table around it, and is given where its records are shown in the
  # full view. A table with its state in the URL finds it there, and is then
  # read as a nested table is: through the parent, read again as the person.
  # Any other table is not limited.
  defp relate(%{assigns: %{nested?: true, via: via, parent_key: key}} = socket) do
    assign(socket, full_view: Related.path(socket.router, socket.endpoint, via, key))
  end

  defp relate(%{assigns: %{url: url, id: id, resource: resource}} = socket)
       when is_binary(url) do
    params = url |> query_params() |> Map.get(id)

    case Related.from_params(resource, params, reader(socket.assigns), socket.endpoint) do
      nil ->
        assign(socket, via: nil, parent_key: nil, related: nil, related_title: nil)

      %{via: via, key: key} = related ->
        # as the table around a nested one says for it: what this table was
        # told, else what the parent's own domain says
        parent_authorize? =
          case socket.assigns.authorize_given do
            nil -> AshTable.Domain.Info.authorize?(via.source)
            authorize? -> authorize?
          end

        assign(socket,
          via: via,
          parent_key: key,
          parent_authorize?: parent_authorize?,
          related: related
        )
    end
  end

  defp relate(socket), do: socket

  # Whether the rows of the table have an expander: there is something to
  # offer this person, the table lets its rows expand at all (`max_depth 0`
  # says never, wherever the table is shown), and the table on the page lets
  # them expand this deep.
  defp expandable?(model, depth, depth_limit),
    do: model.relationships != [] and model.max_depth > 0 and depth < depth_limit

  # The resource's own wording, as the person reads it: the labels of the
  # columns and of their values, and the questions, in the host's
  # translation where it has one. Done here, once per update and in the
  # process whose locale the host has set, so that everything rendered from
  # the model, and every message that names a column, uses the same words.
  defp in_words(model) do
    columns =
      for column <- model.columns do
        %{
          column
          | label: Text.label(column.label),
            confirm: column.confirm && Text.label(column.confirm),
            values:
              column.values &&
                Enum.map(column.values, fn {value, label} -> {value, Text.label(label)} end)
        }
      end

    relationships = Enum.map(model.relationships, &%{&1 | label: Text.label(&1.label)})

    %{model | columns: columns, relationships: relationships}
  end

  # A table whose state lives in the URL takes it from there on every update;
  # an embedded table keeps what its own events set.
  defp current_state(%{url: url, id: id}, model) when is_binary(url) do
    State.from_params(model, url |> query_params() |> Map.get(id))
  end

  # What it kept is fitted to the model of the person who is asking now.
  defp current_state(%{state: state}, model), do: State.fit(state, model)

  # Reads again only when something a read depends on has changed. The first
  # read is done in place, so that the first render has rows; later ones run
  # beside the process, with the previous rows left in view and the grid
  # marked busy.
  #
  # A nested table reads beside the process from the start: its line opens at
  # once, and several that are opened together read side by side. Until its
  # first rows are there it says that it is loading.
  defp read(socket) do
    %{model: model, state: state, parent_key: key} = socket.assigns
    opts = reader(socket.assigns)
    read = {model, state, opts, key}

    # The records related to one record are read through that record: those
    # of a nested table, and those a URL limits a table of its own to.
    fetch =
      case model.via do
        %Relationship{} ->
          opts = [parent_authorize?: socket.assigns.parent_authorize?] ++ opts
          fn -> Query.read_related(model, state, key, opts) end

        nil ->
          fn -> Query.read(model, state, opts) end
      end

    cond do
      read == socket.assigns.read ->
        socket

      socket.assigns.nested? ->
        socket
        |> assign(read: read, busy?: true, loading?: is_nil(socket.assigns.read))
        |> start_async(:read, fetch)

      is_nil(socket.assigns.read) ->
        socket |> assign(read: read) |> show(fetch.(), :first)

      true ->
        socket |> assign(read: read, busy?: true) |> start_async(:read, fetch)
    end
  end

  # Who is reading and saving.
  defp reader(assigns), do: Map.to_list(Map.take(assigns, [:scope, :actor, :tenant, :authorize?]))

  @impl true
  def handle_async(:read, {:ok, result}, socket) do
    {:noreply, socket |> assign(busy?: false, loading?: false) |> show(result, :later)}
  end

  def handle_async(:read, {:exit, reason}, socket) do
    {:noreply, socket |> assign(busy?: false, loading?: false) |> show({:error, reason}, :later)}
  end

  # Shows what a read gave. `read` says which one it was: the `:first` of
  # this table, done while it is mounted, or a `:later` one.
  defp show(socket, {:ok, %Query.Page{} = page}, _read) do
    %{id: id, model: model} = socket.assigns

    rows =
      page.records
      |> Enum.with_index()
      |> Enum.map(fn {record, index} ->
        %{
          key: row_key(model, record, index),
          record: record,
          # 1-based, the header rows counted. Under offset pagination it
          # runs through all pages; a keyset page does not know how many
          # records lie before it, and counts from its own top.
          rowindex: (page.offset || 0) + index + @header_rows + 1
        }
      end)

    # each row, and after it its detail when rows can be expanded: closed
    items =
      Enum.flat_map(rows, fn row ->
        [item(id, row.key, row.record, row.rowindex, %{}, false)] ++
          if(socket.assigns.expandable?, do: [detail(id, row.key, nil, nil)], else: [])
      end)

    socket
    |> assign(page: %{page | records: [], parent: nil}, row_count: length(rows))
    |> assign(error: nil, gone?: false, related_title: related_title(socket.assigns, page))
    |> assign(
      rows: Map.new(rows, &{&1.key, %{rowindex: &1.rowindex, pk: primary_key(model, &1.record)}}),
      failed: %{},
      open: %{}
    )
    |> announce(page)
    |> stream(:rows, items, reset: true)
  end

  # The row a nested table belongs to is gone, or no longer this person's to
  # read: nothing is known about its related records, which is not the same
  # as there being none.
  defp show(socket, {:error, :parent_gone}, _read),
    do: show_message(socket, Text.t(:record_gone))

  # A nested table whose destination this person may not read, in either of
  # the two ways Ash says so. Its line has told them that there is a table,
  # so it says something in every case: that they are not allowed when the
  # destination's table is declared with `on_forbidden :message`, and no more
  # than that the records are not available otherwise. Never "No records".
  defp show(%{assigns: %{nested?: true}} = socket, {:error, refusal}, _read)
       when refusal == :forbidden or is_struct(refusal, Ash.Error.Forbidden) do
    case TableInfo.table_on_forbidden!(socket.assigns.resource) do
      :message -> show_message(socket, Text.t(:not_allowed))
      :not_found -> show_message(socket, Text.t(:records_not_available))
    end
  end

  # A table of its own that is limited to related records, whose destination
  # this person may not read: Ash put its refusal in place of the records.
  # It is the refusal of this table's read, as below.
  defp show(socket, {:error, :forbidden}, read),
    do: show(socket, {:error, Ash.Error.Forbidden.exception([])}, read)

  # A read the resource refuses outright. Unless the table is declared with
  # `on_forbidden :message`, the person is not told that there is a table:
  # nothing of it is rendered, and a table that is a page of its own answers
  # as a page that does not exist.
  defp show(socket, {:error, %Ash.Error.Forbidden{} = error}, read) do
    case TableInfo.table_on_forbidden!(socket.assigns.resource) do
      :message -> show_error(socket, error)
      :not_found -> socket |> show_error(error) |> assign(gone?: true) |> not_found(read)
    end
  end

  defp show(socket, {:error, error}, _read), do: show_error(socket, error)

  defp show_error(socket, error),
    do: show_message(socket, error_text(error, socket.assigns.model))

  # The message is an alert of its own, in place of the rows.
  defp show_message(socket, text) do
    socket
    |> assign(page: nil, row_count: 0, rows: %{}, failed: %{}, announce?: false, gone?: false)
    # nothing is said of a record that was not read for this person
    |> assign(error: text, open: %{}, related_title: nil)
    |> stream(:rows, [], reset: true)
  end

  # A table placed in a page of the host's cannot make that page disappear:
  # it renders nothing.
  defp not_found(%{assigns: %{mounted?: false}} = socket, _read), do: socket

  # While the page is mounted, an exception is how a LiveView says "not
  # found": Phoenix answers the request with 404, and over a live connection
  # the browser is told to ask for the page afresh, which gets that answer.
  defp not_found(_socket, :first), do: raise(AshTable.NotFoundError)

  # Later, the page is on screen. The browser is sent to ask for it afresh,
  # which raises the exception above; nothing crashes for it.
  defp not_found(%{assigns: %{url: url}} = socket, :later) do
    uri = URI.parse(url)
    redirect(socket, to: %URI{path: uri.path || "/", query: uri.query} |> URI.to_string())
  end

  # A row as the stream holds it. `failed` holds, by column name, what was
  # typed into a cell whose save failed and the action's message; `open?`
  # says whether the row is expanded.
  defp item(id, key, record, rowindex, failed, open?) do
    %{
      dom_id: "#{id}-row-#{key}",
      record: record,
      rowindex: rowindex,
      failed: failed,
      open?: open?
    }
  end

  # The detail of a row as the stream holds it: what is under an expanded
  # row. `lines` are the names of its open lines, nil while the row is not
  # expanded; `pk` is the row's primary key, which its nested tables are
  # given. No record is needed for it.
  defp detail(id, key, pk, lines) do
    %{dom_id: "#{id}-row-#{key}-x", detail?: true, key: key, pk: pk, lines: lines}
  end

  # Puts a row of the page into the stream again, in its place: with the
  # record as an action returned it or as it was read again, and with the
  # edits of the row that have failed. Its detail is another item and stays
  # as it is: what is open under the row stays open.
  defp put_row(socket, key, record) do
    %{id: id, rows: rows, failed: failed, open: open} = socket.assigns
    cells = get_in(failed, [key, :cells]) || %{}

    stream_insert(
      socket,
      :rows,
      item(id, key, record, rows[key].rowindex, cells, is_map_key(open, key))
    )
  end

  # Puts the detail of a row into the stream again, in its place, as `open`
  # says it is now. A nested table that stays open is rendered again and
  # reads nothing for it; one that is no longer rendered is gone, with its
  # state.
  defp put_detail(socket, key) do
    %{id: id, rows: rows, open: open} = socket.assigns

    stream_insert(socket, :rows, detail(id, key, rows[key].pk, open[key]))
  end

  # Notes that the save of a cell has failed, or with `nil` that it no longer
  # has. The record is kept with the failures of its row, and only then.
  defp put_failure(socket, key, record, name, failure) do
    cells = get_in(socket.assigns.failed, [key, :cells]) || %{}
    cells = if failure, do: Map.put(cells, name, failure), else: Map.delete(cells, name)

    failed =
      if cells == %{},
        do: Map.delete(socket.assigns.failed, key),
        else: Map.put(socket.assigns.failed, key, %{record: record, cells: cells})

    assign(socket, failed: failed)
  end

  defp primary_key(%{primary_key: primary_key}, record), do: Map.take(record, primary_key)

  # What the record is called that a table of its own is limited to: what
  # its resource's table calls a record by, as far as this person may see it
  # on this record. Taken from the record as it was read for them, and from
  # nothing else: a record that was not read has no name here.
  defp related_title(%{related: %{via: via}}, %Query.Page{parent: %_{} = parent}) do
    via.source
    |> Model.build()
    |> in_words()
    |> Model.naming()
    |> Enum.find_value(fn column ->
      case Map.get(parent, column.name) do
        %Ash.ForbiddenField{} -> nil
        %Ash.NotLoaded{} -> nil
        value -> blank_as_nil(Format.format(column, value))
      end
    end)
  end

  defp related_title(_assigns, _page), do: nil

  defp blank_as_nil(text), do: if(String.trim(text) != "", do: text)

  # After a filter change, the result is put into the live region: the count
  # when the read action counts, under either pagination strategy, else
  # only that the rows have changed.
  defp announce(%{assigns: %{announce?: true}} = socket, page) do
    text =
      case page.total do
        nil -> Text.t(:results_updated)
        total -> Text.n(:results, total)
      end

    socket |> assign(announce?: false) |> say(text)
  end

  defp announce(socket, _page), do: socket

  # Puts a text into the live region, to be read out.
  defp say(socket, text) do
    assign(socket, announcement: text, announcements: socket.assigns.announcements + 1)
  end

  defp error_text(%Ash.Error.Forbidden{}, _model), do: Text.t(:not_allowed)

  # What the read action returned on purpose is shown as it is: an argument
  # or a filter it does not accept, a validation of its own. Anything else is
  # a failure a person can do nothing about and should not be shown the
  # inside of: it goes to the log, and the table says only that it failed.
  defp error_text(error, model) do
    case Errors.of_read(error, model) do
      [] ->
        log_failed_read(error, model)
        Text.t(:read_failed)

      messages ->
        Enum.join(messages, "; ")
    end
  end

  # A failure underneath is an error for whoever runs the application. An
  # error of the invalid class that has no message for a person (a keyset
  # cursor that somebody altered in the URL, say) is not.
  defp log_failed_read(error, model) do
    text = if is_exception(error), do: Exception.message(error), else: inspect(error)
    message = "ash_table: the read `#{model.read_action}` of #{inspect(model.resource)} failed: "

    case error do
      %Ash.Error.Invalid{} -> Logger.warning(message <> text)
      _other -> Logger.error(message <> text)
    end
  end

  # The primary key as a DOM id. A resource without one falls back to the
  # position in the page.
  defp row_key(%{primary_key: []}, _record, index), do: "n#{index}"

  defp row_key(%{primary_key: primary_key}, record, _index) do
    Enum.map_join(primary_key, "-", fn field ->
      value = record |> Map.get(field) |> to_string()

      if value =~ ~r/\A[A-Za-z0-9_-]+\z/,
        do: value,
        else: "b" <> Base.url_encode64(value, padding: false)
    end)
  end

  @impl true
  def handle_event("sort", %{"column" => name}, socket) do
    %{state: state, model: model} = socket.assigns
    {:noreply, go(socket, State.cycle_sort(state, model, name))}
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  # Sent by the form of the filter row when a filter is left or a choice is
  # made, with every filter of the row.
  def handle_event("filter", params, socket) do
    %{state: state, model: model} = socket.assigns

    form =
      case params do
        %{"filter" => %{} = form} -> form
        _other -> %{}
      end

    {state, rejected} = State.filter(state, model, form)

    {:noreply, socket |> assign(rejected: rejected) |> refilter(state)}
  end

  def handle_event("clear_filter", %{"column" => name}, socket) when is_binary(name) do
    {:noreply, refilter(socket, State.clear_filter(socket.assigns.state, name))}
  end

  def handle_event("clear_filters", _params, socket) do
    state = State.clear_filters(socket.assigns.state)

    {:noreply, socket |> assign(rejected: %{}) |> refilter(state)}
  end

  def handle_event("page", %{"to" => to}, socket) when is_binary(to) do
    {:noreply, go(socket, target(socket.assigns, to))}
  end

  # An event of a shape the table never sends: nothing happens.
  def handle_event(event, _params, socket) when event in ["clear_filter", "page"],
    do: {:noreply, socket}

  # Sent by the hook when a person uses the expander of a row: the row by
  # the key in its DOM id. The row is expanded to its lines, or closed with
  # everything open under it. The answer says which, as the row itself is
  # not sent again.
  #
  # Only a row of the page can be expanded, and only where the table has
  # expanders: this is where the depth limit holds against an event that the
  # table never offered.
  def handle_event("expand", %{"row" => key}, socket) when is_binary(key) do
    %{rows: rows, open: open, expandable?: expandable?} = socket.assigns

    if expandable? and is_map_key(rows, key) do
      open = if is_map_key(open, key), do: Map.delete(open, key), else: Map.put(open, key, [])

      {:reply, %{open: is_map_key(open, key)}, socket |> assign(open: open) |> put_detail(key)}
    else
      {:reply, %{open: false}, socket}
    end
  end

  def handle_event("expand", _params, socket), do: {:reply, %{open: false}, socket}

  # Sent by the hook when a person uses a line under an expanded row: the
  # row, and the relationship by name. The line's nested table is opened, or
  # closed and forgotten.
  #
  # Only a line that is on the page can be used: of an expanded row of the
  # page, and for a relationship this person is offered.
  def handle_event("toggle", %{"row" => key, "relationship" => name}, socket)
      when is_binary(key) do
    %{model: model, open: open, expandable?: expandable?} = socket.assigns

    with true <- expandable?,
         lines when is_list(lines) <- open[key],
         %Relationship{name: name} <- Model.relationship(model, name) do
      lines = if name in lines, do: List.delete(lines, name), else: lines ++ [name]

      {:noreply, socket |> assign(open: Map.put(open, key, lines)) |> put_detail(key)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle", _params, socket), do: {:noreply, socket}

  # Sent by the hook when a person has changed a cell's value and pressed
  # Enter or left the cell: the row by the key in its DOM id, the column, and
  # the value as it was typed.
  def handle_event("save", %{"row" => key, "column" => name, "value" => typed}, socket)
      when is_binary(typed) do
    %{model: model, rows: rows} = socket.assigns

    with %{editable?: true} = column <- column(model, name),
         %{} = row <- rows[key] do
      save(socket, key, row, column, typed)
    else
      # not a cell this table lets anyone edit: nothing a person can send
      # through the table, so nothing is shown for it either
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event("save", _params, socket), do: {:reply, %{ok: false}, socket}

  # Sent by the hook when a person presses Escape on a cell whose save has
  # failed: the edit is given up, and the cell shows its record's value again.
  def handle_event("discard", %{"row" => key, "column" => name}, socket) do
    with %{} = column <- column(socket.assigns.model, name),
         %{record: record, cells: %{}} <- socket.assigns.failed[key] do
      {:noreply, socket |> put_failure(key, record, column.name, nil) |> put_row(key, record)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("discard", _params, socket), do: {:noreply, socket}

  # Either way the row is put back with what is true now: the action's
  # result, or the record as it is and the cell marked with what was typed.
  defp save(socket, key, row, column, typed) do
    case Edit.save(socket.assigns.model, column, row.pk, typed, reader(socket.assigns)) do
      {:ok, record} ->
        {:reply, %{ok: true},
         socket |> put_failure(key, record, column.name, nil) |> put_row(key, record)}

      {:error, %_{} = record, message} ->
        {:reply, %{ok: false},
         socket
         |> put_failure(key, record, column.name, {typed, message})
         |> put_row(key, record)
         |> say(Text.t(:not_saved, column: column.label, message: message))}

      # The record is gone, or no longer this person's to read: there is
      # nothing to show the row from, so it stays as it is, and the hook
      # marks the cell with the message.
      {:error, nil, message} ->
        {:reply, %{ok: false, error: message},
         say(socket, Text.t(:not_saved, column: column.label, message: message))}
    end
  end

  # Looked up by its name as text, so that text from the outside is never
  # turned into an atom.
  defp column(model, name) when is_binary(name),
    do: Enum.find(model.columns, &(Atom.to_string(&1.name) == name))

  defp column(_model, _name), do: nil

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

  # A change of the filters is announced once its rows have been read.
  defp refilter(%{assigns: %{state: state}} = socket, state), do: socket
  defp refilter(socket, state), do: socket |> assign(announce?: true) |> go(state)

  # With the state in the URL the change is a patch, and the new state comes
  # back through `update/2`. Otherwise the component holds it.
  defp go(%{assigns: %{state: state}} = socket, state), do: socket

  defp go(%{assigns: %{url: url, id: id}} = socket, state) when is_binary(url) do
    # what the table is limited to stays, whatever else changes
    limit =
      case socket.assigns.related do
        nil -> %{}
        %{param: param} -> %{Related.param() => param}
      end

    push_patch(socket,
      to: path(url, id, Map.merge(State.to_params(state, socket.assigns.model), limit))
    )
  end

  defp go(socket, state), do: socket |> assign(state: state) |> read()

  # The URL with these parameters for the table `id`, and those of the
  # page's other tables as they are.
  defp path(url, id, params) do
    params =
      if params == %{},
        do: Map.delete(query_params(url), id),
        else: Map.put(query_params(url), id, params)

    path = URI.parse(url).path || "/"

    if params == %{}, do: path, else: path <> "?" <> Plug.Conn.Query.encode(params)
  end

  defp query_params(url) do
    case URI.parse(url).query do
      nil -> %{}
      query -> Plug.Conn.Query.decode(query)
    end
  end

  @impl true
  def render(%{gone?: true} = assigns) do
    ~H"""
    <div id={@id} hidden></div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class="ash-table">
      <%!-- The form of the filter row. A form cannot sit inside a table around
      its cells, so the controls name it instead. --%>
      <.related
        :if={@related}
        id={@id}
        via={@related.via}
        title={@related_title}
        parent={Routes.table(@socket.router, @related.via.source)}
        clear={path(@url, @id, %{})}
      />
      <form
        id={"#{@id}-filters"}
        phx-change="filter"
        phx-submit="filter"
        phx-target={@myself}
      >
      </form>
      <%!-- as high as its button, so that the table does not move when it appears --%>
      <div class="mb-2 flex min-h-8 items-center justify-end">
        <%!-- the button goes away with the filters, so focus is sent on to the grid --%>
        <button
          :if={@state.filters != %{}}
          type="button"
          id={"#{@id}-clear-filters"}
          tabindex={@nested? && "-1"}
          class="btn btn-sm"
          phx-click={
            JS.push("clear_filters", target: @myself)
            |> JS.focus(to: "##{@id}-table [tabindex='0']")
          }
        >
          {Text.t(:clear_filters)}
        </button>
      </div>
      <%!-- Read out after each filter change, and when a save fails. A live region
      is only read when its content changes, so every other announcement ends in a
      no-break space. --%>
      <p id={"#{@id}-status"} role="status" aria-live="polite" class="sr-only" phx-no-format>{@announcement}{if rem(@announcements, 2) == 1, do: "\u00A0"}</p>
      <%!-- `data-ash-table` marks the element a grid's hook is on, for the hooks
      of the tables nested in it and around it; `data-lead` is the number of
      columns before the first data column. --%>
      <div
        id={"#{@id}-grid"}
        phx-hook=".Grid"
        phx-target={@myself}
        data-ash-table
        data-lead={lead(@expandable?)}
        class={not @nested? && "overflow-x-auto"}
      >
        <table
          id={"#{@id}-table"}
          role="grid"
          aria-label={is_nil(@labelledby) && @label}
          aria-labelledby={@labelledby}
          aria-rowcount={aria_rowcount(@page)}
          aria-colcount={length(@model.columns) + lead(@expandable?)}
          aria-busy={@busy? && "true"}
          class={
            [
              "table aria-busy:opacity-60",
              # what every cell looks like is set once here, to keep each cell's markup small:
              # the focus ring, which a cell keeps while its editor has the focus
              "[&_:is(td,th):focus]:outline-2 [&_:is(td,th):focus]:-outline-offset-2 [&_:is(td,th):focus]:outline-primary",
              "[&>tbody>tr>td:not([data-nested]):focus-within]:outline-2 [&>tbody>tr>td:not([data-nested]):focus-within]:-outline-offset-2 [&>tbody>tr>td:not([data-nested]):focus-within]:outline-primary",
              # a cell whose save failed, and one whose save is on its way
              "[&_td[aria-invalid]]:inset-ring-2 [&_td[aria-invalid]]:inset-ring-error [&_td[aria-busy]]:opacity-60",
              # one line per row: long text is cut off, not wrapped. Not in a cell
              # that spans the table: a line, or the cell a nested table is in.
              "[&>tbody>tr>td:not([colspan])]:max-w-80 [&>tbody>tr>td:not([colspan])]:truncate",
              # the expander of a row and the button of a line, with the mark that turns when open
              "[&>tbody>tr>td>button[aria-expanded]]:cursor-pointer [&>tbody>tr>td[data-expander]]:w-0 [&>tbody>tr>td[data-expander]>button]:px-1",
              "[&>tbody>tr>td[data-expander]>button]:transition-transform [&>tbody>tr>td[data-expander]>button[aria-expanded=true]]:rotate-90",
              "[&>tbody>tr>td[data-line]>button>span]:inline-block [&>tbody>tr>td[data-line]>button>span]:transition-transform [&>tbody>tr>td[data-line]>button[aria-expanded=true]>span]:rotate-90"
            ]
          }
          phx-update="stream"
        >
          <thead id={"#{@id}-head"}>
            <tr id={"#{@id}-head-row"} role="row" aria-rowindex="1">
              <th
                :if={@expandable?}
                id={"#{@id}-expander-head"}
                role="columnheader"
                scope="col"
                aria-colindex="1"
                tabindex="-1"
                class="w-0"
              >
                <span class="sr-only">{Text.t(:related_records)}</span>
              </th>
              <th
                :for={{column, index} <- Enum.with_index(@model.columns)}
                id={"#{@id}-head-#{column.name}"}
                role="columnheader"
                scope="col"
                aria-colindex={colindex(index, @expandable?)}
                aria-sort={column.sortable? && aria_sort(@state.sort, column)}
                tabindex="-1"
                data-sort={column.sortable?}
                phx-click={column.sortable? && "sort"}
                phx-value-column={column.sortable? && column.name}
                phx-target={column.sortable? && @myself}
                class={["whitespace-nowrap", column.sortable? && "cursor-pointer select-none"]}
                phx-no-format
              >{column.label}<span :if={column.sortable?} aria-hidden="true">{sort_mark(@state.sort, column)}</span></th>
            </tr>
            <tr id={"#{@id}-filter-row"} role="row" aria-rowindex="2">
              <td
                :if={@expandable?}
                id={"#{@id}-expander-filter"}
                role="gridcell"
                aria-colindex="1"
                tabindex="-1"
              >
              </td>
              <td
                :for={{column, index} <- Enum.with_index(@model.columns)}
                id={"#{@id}-filter-#{column.name}"}
                role="gridcell"
                aria-colindex={colindex(index, @expandable?)}
                tabindex="-1"
                data-filter={column.operators != []}
              >
                <.filter
                  :if={column.operators != []}
                  id={"#{@id}-filter-#{column.name}"}
                  form={"#{@id}-filters"}
                  column={column}
                  filter={@rejected[column.name] || @state.filters[column.name]}
                  rejected?={is_map_key(@rejected, column.name)}
                  target={@myself}
                />
              </td>
            </tr>
          </thead>
          <%!-- Written without whitespace on purpose: every byte of a row is sent again
          whenever the row is, and a cell's text must not be padded. An item of the
          stream is a row or, after its row, the row's detail (see "Nested tables"
          at the top). --%>
          <tbody
            :for={{dom_id, row} <- @streams.rows}
            id={dom_id}
            hidden={row[:detail?] && is_nil(row.lines)}
            data-detail={row[:detail?]}
            data-row={row[:detail?] && row.key}
            phx-no-format
          ><.lines
            :if={row[:detail?] && row.lines}
            id={@id}
            row={row}
            model={@model}
            reader={nested_reader(assigns)}
          /><tr
            :if={!row[:detail?]}
            id={"#{dom_id}-r"}
            role="row"
            aria-rowindex={row.rowindex}
          ><td
            :if={@expandable?}
            id={"#{dom_id}-e"}
            role="gridcell"
            aria-colindex="1"
            tabindex="-1"
            data-expander
          ><button type="button" tabindex="-1" aria-expanded={to_string(row.open?)} aria-label={Text.t(:related_records)}>▸</button></td><td
            :for={{column, index} <- Enum.with_index(@model.columns)}
            id={"#{dom_id}-c-#{column.name}"}
            role="gridcell"
            aria-colindex={colindex(index, @expandable?)}
            tabindex="-1"
            {cell_attributes(@editing?, "#{dom_id}-c-#{column.name}", column, row)}
          >{cell_content("#{dom_id}-c-#{column.name}", column, row)}</td></tr></tbody>
          <%!-- The pages of a nested table are a last row of its grid: reached with
          the arrow keys and entered with Enter, as a filter is, and no tab stop in the
          middle of the grid around it. The element stays where it is once it is there,
          as every child of a stream's container with an id does. --%>
          <tfoot
            :if={@nested?}
            id={"#{@id}-foot"}
            hidden={not pages?(@page, @model) and not full_view?(@page, @full_view)}
          >
            <tr :if={pages?(@page, @model)} id={"#{@id}-foot-row"} role="row">
              <td
                id={"#{@id}-pager"}
                role="gridcell"
                colspan={length(@model.columns) + lead(@expandable?)}
                aria-colindex="1"
                tabindex="-1"
                data-pager
              >
                <.pagination
                  id={@id}
                  nested?={true}
                  page={@page}
                  model={@model}
                  state={@state}
                  row_count={@row_count}
                  label={@label}
                  target={@myself}
                />
              </td>
            </tr>
            <%!-- The link to the full view is the last row of a nested table's grid,
            for the same reason: reached with the arrow keys and followed with Enter. --%>
            <tr :if={full_view?(@page, @full_view)} id={"#{@id}-view-row"} role="row">
              <td
                id={"#{@id}-view"}
                role="gridcell"
                colspan={length(@model.columns) + lead(@expandable?)}
                aria-colindex="1"
                tabindex="-1"
                data-view
              >
                <.link
                  id={"#{@id}-full-view"}
                  navigate={@full_view}
                  tabindex="-1"
                  aria-label={Text.t(:full_view_of, table: @label)}
                  class="link text-sm"
                >
                  {Text.t(:full_view)}
                </.link>
              </td>
            </tr>
          </tfoot>
        </table>
        <%!-- One editor per editable column. The hook opens a copy of it in the
        cell being edited; which cell that is, the server never knows. --%>
        <template
          :for={column <- @model.columns}
          :if={column.editable?}
          id={"#{@id}-editor-#{column.name}"}
          data-editor={column.editor}
          data-confirm={column.confirm}
        >
          <.editor column={column} allow_nil?={allow_nil?(@model.resource, column)} />
        </template>
        <%!-- The message of a cell whose save failed, for the one case in which
        the hook has to mark the cell itself: the record is gone, so there is
        no row to send. --%>
        <template :if={@editing?} id={"#{@id}-failure"}>{failure_message(nil, "")}</template>
      </div>
      <%!-- The one dialog of the table: it asks the question of a column with
      `confirm` before the cell is saved. The hook opens it and puts the question
      in, so patches leave it alone. --%>
      <div :if={Enum.any?(@model.columns, & &1.confirm)} id={"#{@id}-dialogs"} phx-update="ignore">
        <%!-- Styled here and not with daisyUI's `modal`: that one fades in, and
        a dialog that is not visible yet when it opens cannot take the focus. --%>
        <dialog
          id={"#{@id}-dialog"}
          aria-labelledby={"#{@id}-dialog-question"}
          class="m-auto w-full max-w-md rounded-box bg-base-100 p-6 text-base-content shadow-xl backdrop:bg-black/40"
        >
          <form method="dialog">
            <p id={"#{@id}-dialog-question"}></p>
            <div class="mt-6 flex justify-end gap-2">
              <button value="cancel" class="btn">{Text.t(:cancel)}</button>
              <button value="confirm" class="btn btn-primary">{Text.t(:confirm)}</button>
            </div>
          </form>
        </dialog>
      </div>
      <%!-- in the text colour: the error colour is too faint for small text --%>
      <p
        :if={@error}
        id={"#{@id}-error"}
        role="alert"
        class={[if(@nested?, do: "py-4", else: "py-8"), "text-center text-sm font-medium"]}
      >
        {@error}
      </p>
      <%!-- a nested table whose first read is on its way --%>
      <p :if={@loading?} id={"#{@id}-loading"} class="py-4 text-center text-sm opacity-70">
        {Text.t(:loading)}
      </p>
      <p
        :if={is_nil(@error) and @row_count == 0 and not @loading?}
        id={"#{@id}-empty"}
        class={[if(@nested?, do: "py-4", else: "py-8"), "text-center text-sm opacity-70"]}
      >
        {Text.t(:no_records)}
      </p>
      <.pagination
        :if={not @nested? and pages?(@page, @model)}
        id={@id}
        nested?={false}
        page={@page}
        model={@model}
        state={@state}
        row_count={@row_count}
        label={@label}
        target={@myself}
      />
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Pagination">
        // Focus stays on the pagination control that was used. Previous and
        // Next are patched where they are. A page number is not always: when
        // the numbers around it change, the patch takes its button out and
        // puts it back, and the browser drops the focus of an element that is
        // moved, as it does of one that becomes disabled. So the control
        // that had focus before a patch is given it back after the patch.
        //
        // When it cannot have it, because Next was used to reach the last
        // page or Previous to reach the first, focus goes to the button of
        // the page that is shown now and, in a table without page numbers, to
        // the other of the two. When the pagination itself goes away, with a
        // read that failed, focus goes to the grid.
        export default {
          mounted() {
            this.gridId = this.el.id.replace(/-pagination$/, "-table")
            this.used = null
            this.hasFocus = false
            // the control that had focus last
            this.last = null
            this.el.addEventListener("focusin", e => { this.hasFocus = true; this.last = e.target.id })
            // noted a moment later: a control that is taken out of the page
            // loses the focus as one that is left does, and `destroyed` has
            // to know that it had it
            this.el.addEventListener("focusout", () => {
              setTimeout(() => { this.hasFocus = this.el.contains(document.activeElement) })
            })
          },

          // A patch that takes away what stands above the pagination ("No
          // records", when the rows are back) moves the pagination itself,
          // and by the time this is called the browser has dropped the focus
          // of what was moved. The control is then the one that had it last.
          beforeUpdate() {
            const active = document.activeElement
            this.used = this.el.contains(active) ? active.id : (this.hasFocus ? this.last : null)
          },

          updated() {
            if (!this.used) return
            const usable = control => control && this.el.contains(control) && !control.disabled
            const control = [
              document.getElementById(this.used),
              this.el.querySelector("[aria-current='page']"),
              ...this.el.querySelectorAll("button")
            ].find(usable)
            this.used = null
            if (!control) return this.toGrid()
            if (control !== document.activeElement) control.focus({preventScroll: true})
          },

          // After the patch, once the grid has its tab stop again, and only
          // while focus is still nowhere.
          destroyed() {
            if (!this.hasFocus) return
            setTimeout(() => { if (document.activeElement === document.body) this.toGrid() })
          },

          // To the grid's tab stop; in a nested table, whose tab stop may be
          // anywhere in the tables around it, to the cell the controls are in.
          toGrid() {
            const cell = this.el.closest("td[data-pager]") ||
              document.querySelector(`[id="${CSS.escape(this.gridId)}"] [tabindex="0"]`)
            if (cell) cell.focus({preventScroll: true})
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Grid">
        // Keyboard, focus and editing for one grid: a single tab stop with a
        // roving tabindex, moved by the arrow keys.
        //
        // A nested table is a grid of its own, with a hook of its own, inside
        // a cell of the grid around it. The tab stop is one for the whole
        // tree: the tables on top of each other share where it is (`tree()`),
        // and each hook deals only with what happens in its own grid
        // (`owns()`). The arrow keys stay in the grid that has the focus;
        // Enter on the cell that holds a nested table goes into it, and
        // Escape in it comes back out to that cell.
        //
        // Moving about never talks to the server. Enter on a sortable header
        // clicks it and Enter in a filter submits the filter row's form; both
        // are the server's from there.
        //
        // Which cell is being edited is known here alone. The server renders
        // one editor per editable column in a <template>; a copy of it is put
        // into the cell, and when the person is done, one "save" event goes
        // out with the row, the column and the value as typed. The answer is
        // the row itself, patched in: with the new value, or with the cell
        // marked as failed.

        // a key that types a character
        const PRINTABLE = e => e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey

        // What a cell says about itself besides its content, which a patch
        // does not bring to a cell that is being edited.
        const KEPT = ["aria-readonly", "aria-invalid", "aria-describedby", "data-value", "data-saved"]

        // keys that move through the options of a closed select
        const SELECT_KEYS = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Home", "End", "PageUp", "PageDown"]

        // the element a grid's hook is on
        const GRID = "[data-ash-table]"

        // What a cell is besides a cell of a column: the expander of a row, a
        // line under an expanded row, the cell that holds a nested table, the
        // cell that holds a nested table's pages, or the one that holds its
        // link to the full view.
        const is = (cell, what) => cell.dataset[what] !== undefined

        export default {
          mounted() {
            // the table's id, which every id in it starts with
            this.id = this.el.id.replace(/-grid$/, "")
            // for the hooks of the grids around this one and in it
            this.el._ashTable = this
            // the cell arrow keys start from: the first data cell of the first
            // data row, or of the last header row while there are no rows. The
            // expander of the row is one cell to the left of it.
            this.pos = {r: this.headRows(), c: this.lead()}
            this.col = this.lead()
            // the edit in progress: {cell, input, type, saved, old, confirm},
            // and `attributes` once a patch has brought the cell's row again
            this.editing = null
            // cells this hook has marked as failed itself, with what they showed before
            this.marked = new WeakMap()
            // the cell under the pointer, and the message that is showing
            this.pointed = null
            this.message = null
            // what happens in a grid nested in this one is that grid's
            const own = handle => e => { if (this.owns(e.target)) handle(e) }
            this.el.addEventListener("keydown", own(e => this.onKeydown(e)))
            this.el.addEventListener("focusin", own(e => this.onFocusin(e)))
            this.el.addEventListener("focusout", own(e => this.onFocusout(e)))
            this.el.addEventListener("click", own(e => this.onClick(e)))
            this.el.addEventListener("dblclick", own(e => this.onDblclick(e)))
            this.el.addEventListener("mouseover", e => this.onPointer(this.cellOf(e.target)))
            this.el.addEventListener("mouseleave", () => this.onPointer(null))
            this.onScroll = () => this.showMessage()
            window.addEventListener("scroll", this.onScroll, true)
            // updated() only runs when this element itself is patched; a
            // stream insert or reset touches the rows alone.
            this.observer = new MutationObserver(() => this.sync())
            this.observer.observe(this.el, {
              subtree: true,
              childList: true,
              attributes: true,
              attributeFilter: ["tabindex"]
            })
            this.sync()
          },

          // A cell that is being edited is left alone by patches, so that
          // what is typed survives when another cell's save puts the row
          // back. The row the server sent holds what the cell shows now,
          // though; it is kept aside here, for when the edit is given up.
          beforeUpdate(toEl) {
            const ed = this.editing
            if (!ed || !toEl || !toEl.querySelector) return
            const fresh = toEl.querySelector(`[id="${CSS.escape(ed.cell.id)}"]`)
            if (!fresh) return
            ed.saved = Array.from(fresh.childNodes).map(node => node.cloneNode(true))
            ed.attributes = KEPT.map(name => [name, fresh.getAttribute(name)])
          },

          updated() { this.sync() },

          destroyed() {
            this.observer && this.observer.disconnect()
            window.removeEventListener("scroll", this.onScroll, true)
          },

          // ---- the tree of grids -------------------------------------------

          // The grid on the page that this one is nested in, at whatever
          // depth; itself when it is nested in none.
          top() {
            let top = this.el
            for (let up; (up = top.parentElement && top.parentElement.closest(GRID));) top = up
            return top
          },

          // What the grids of one tree share: the one cell that is the tab
          // stop (`activeId`) with the grid it is in (`owner`), where focus
          // falls back to when that cell goes away (`trail`), and whether
          // focus is in the tree.
          tree() {
            const top = this.top()
            return top._ashTableTree || (top._ashTableTree = {activeId: null, owner: null, trail: [], hadFocus: false})
          },

          // Whether a node is in this grid, and not in a table nested in it:
          // neither in that table's grid, which has its own hook, nor in what
          // that table has around its grid (its dialog, its "Clear filters").
          owns(node) {
            if (!node || !node.closest || node.closest(GRID) !== this.el) return false
            const holder = node.closest("td[data-nested]")
            return !holder || holder === node || !this.el.contains(holder)
          },

          // The cell of the grid around this one that holds it, if any.
          holder() {
            const cell = this.el.parentElement && this.el.parentElement.closest("td[data-nested]")
            return cell || null
          },

          // The number of columns before the first data column.
          lead() { return Number(this.el.dataset.lead || 0) },

          // Where focus goes when a cell goes away with what is around it,
          // nearest first: out of each nested table to the cell that held it,
          // then to its line, then to the expander of its row.
          trailOf(cell) {
            const trail = []
            for (let node = cell; node;) {
              if (is(node, "nested")) trail.push(node.dataset.lineCell, node.dataset.expanderCell)
              else if (is(node, "line")) trail.push(node.id.replace(/-l-[^-]+-c$/, "-e"))
              const grid = node.closest(GRID)
              node = grid && grid.parentElement ? grid.parentElement.closest("td[data-nested]") : null
              if (node) trail.push(node.id)
            }
            return trail
          },

          rows() {
            // HTMLTableElement.rows lists the header rows first, wherever the
            // header sits among the stream's rows in the DOM.
            const table = this.el.querySelector("table")
            return table ? table.rows : []
          },

          // The rows above the data rows: the header and the filter row.
          headRows() {
            const table = this.el.querySelector("table")
            return table && table.tHead ? table.tHead.rows.length : 1
          },

          // The input, menu or button of a filter, or the editor of a cell,
          // that a node is or is in.
          controlOf(node) {
            const control = node && node.closest ? node.closest("input,select,textarea,button") : null
            return control && this.el.contains(control) ? control : null
          },

          cellOf(node) {
            const cell = node && node.closest ? node.closest("td,th") : null
            return cell && this.owns(cell) ? cell : null
          },

          cellAt(r, c) {
            const rows = this.rows()
            if (rows.length === 0) return null
            const row = rows[Math.max(0, Math.min(r, rows.length - 1))]
            return row.cells[Math.max(0, Math.min(c, row.cells.length - 1))] || null
          },

          setActive(cell) {
            const tree = this.tree()
            const previous = tree.activeId && document.getElementById(tree.activeId)
            if (previous && previous !== cell && previous.tabIndex !== -1) previous.tabIndex = -1
            tree.activeId = cell.id
            tree.owner = this.el
            tree.trail = this.trailOf(cell)
            this.pos = {r: cell.parentElement.rowIndex, c: cell.cellIndex}
            // while a cell is edited its editor is the tab stop, so that
            // Shift+Tab from the editor leaves the grid as Tab does
            const tabIndex = this.editing && this.editing.cell === cell ? -1 : 0
            if (cell.tabIndex !== tabIndex) cell.tabIndex = tabIndex
          },

          // After every patch: the server renders each cell with tabindex -1,
          // so the one tab stop has to be put back, and so has focus when the
          // focused cell did not survive the patch.
          //
          // The tab stop is one for the whole tree of grids. When its cell is
          // gone, the next best takes its place: the cell at the same place
          // of the same grid (after a sort, a filter or another page); when
          // that grid is gone too, the nearest cell that held it (a line
          // that was closed, a row that was closed); and at last the cell
          // the grid on the page had before.
          sync() {
            const tree = this.tree()
            const top = this.top()
            const hook = top._ashTable
            // the hook of the grid on the page mounts first
            if (!hook) return
            let cell = tree.activeId && document.getElementById(tree.activeId)
            if (cell && !top.contains(cell)) cell = null
            if (!cell && tree.owner && tree.owner.isConnected && top.contains(tree.owner) && tree.owner._ashTable) {
              const owner = tree.owner._ashTable
              cell = owner.cellAt(owner.pos.r, owner.pos.c)
            }
            if (!cell) {
              const id = tree.trail.find(id => id && document.getElementById(id) && top.contains(document.getElementById(id)))
              cell = id ? document.getElementById(id) : hook.cellAt(hook.pos.r, hook.pos.c)
            }
            const owner = cell && cell.closest(GRID)._ashTable
            if (!owner) return
            owner.setActive(cell)
            // while the dialog asks, focus is in the dialog and stays there
            if (owner.editing && owner.editing.asking) return
            if (tree.hadFocus && !top.contains(document.activeElement)) {
              cell.focus({preventScroll: true})
            }
            // a patch may have brought, replaced or taken away a message
            this.showMessage()
          },

          move(r, c) {
            const cell = this.cellAt(r, c)
            if (cell) cell.focus()
          },

          // A cell that spans the table: a line, the cell of a nested table,
          // the cell of a nested table's pages. Moving up and down through
          // one keeps the column the person was in.
          spans(cell) { return cell.colSpan > 1 },

          onFocusin(e) {
            const tree = this.tree()
            const cell = this.cellOf(e.target)
            if (!cell) { tree.hadFocus = false; return }
            tree.hadFocus = true
            if (!this.spans(cell)) this.col = cell.cellIndex
            this.setActive(cell)
            this.showMessage()
          },

          onFocusout(e) {
            const tree = this.tree()
            const top = this.top()
            if (e.relatedTarget) {
              if (!top.contains(e.relatedTarget)) tree.hadFocus = false
            } else {
              // No new target: either focus really left (a click on nothing),
              // or a patch removed the focused cell and sync() puts it back.
              const target = e.target
              setTimeout(() => {
                if (target.isConnected && !top.contains(document.activeElement)) tree.hadFocus = false
              }, 0)
            }
            setTimeout(() => this.showMessage(), 0)
          },

          onClick(e) {
            const cell = this.cellOf(e.target)
            if (!cell) return
            if (!this.spans(cell)) this.col = cell.cellIndex
            // the expander of a row and the button of a line: used, with
            // focus on their cell
            if (is(cell, "expander") || is(cell, "line")) {
              if (e.target.closest("button")) this.open(cell)
              if (document.activeElement !== cell) cell.focus()
              return
            }
            // a click on a filter's control or in an editor leaves focus there
            if (this.controlOf(e.target)) return
            if (this.editing && this.editing.cell === cell) return
            if (document.activeElement !== cell) cell.focus()
          },

          onDblclick(e) {
            const cell = this.cellOf(e.target)
            if (cell && !this.controlOf(e.target) && this.canEdit(cell)) this.startEdit(cell, null)
          },

          // Into a filter cell: to where its value is typed or chosen, or to
          // its menu when the operator needs no value. Returns the control.
          enter(cell) {
            const control = cell.querySelector("[id$='-value']") ||
              Array.from(cell.querySelectorAll("select,button")).find(control => !control.disabled)
            if (!control) return null
            control.focus()
            if (control.select) control.select()
            return control
          },

          // Inside a filter the keys belong to its controls, the arrow keys
          // among them. The grid keeps three.
          onControlKeydown(e, control) {
            const cell = this.cellOf(control)
            const input = control.tagName === "INPUT"
            switch (e.key) {
              // back to the cell, giving up what was typed and not applied
              case "Escape":
                if (input) control.value = control.defaultValue
                cell.focus()
                e.preventDefault()
                break
              // applies the filter now; focus stays where the person is typing.
              // A patch leaves the value attribute of a focused input alone,
              // so what Escape restores is noted here.
              case "Enter":
                if (input && control.form) {
                  e.preventDefault()
                  if (control.form.reportValidity()) {
                    control.defaultValue = control.value
                    control.form.requestSubmit()
                  }
                }
                break
              // through the controls of this filter; from its last one Tab
              // leaves the grid, as it does from a cell
              case "Tab":
                if (this.toControl(cell, control, e.shiftKey ? -1 : 1)) e.preventDefault()
                break
              // through the pages of a nested table, which are buttons in a row
              case "ArrowLeft":
              case "ArrowRight":
                if (is(cell, "pager")) {
                  this.toControl(cell, control, e.key === "ArrowLeft" ? -1 : 1)
                  e.preventDefault()
                }
                break
            }
          },

          // To the control before or after this one in its cell, if there is one.
          toControl(cell, control, step) {
            const controls = Array.from(cell.querySelectorAll("input,select,button")).filter(control => !control.disabled)
            const next = controls[controls.indexOf(control) + step]
            if (next) next.focus()
            return !!next
          },

          // ---- expanding ---------------------------------------------------

          // Whether the expander of a row, or a line, is open.
          isOpen(cell) {
            const button = cell.querySelector("button")
            return !!button && button.getAttribute("aria-expanded") === "true"
          },

          // Uses the expander of a row, or a line under it: one event. A
          // line comes back with its row's detail, patched in. A row is not
          // sent again, so the answer says whether it is expanded now.
          open(cell) {
            const button = cell.querySelector("button")
            if (!button || button.dataset.pending !== undefined) return
            if (is(cell, "line")) {
              const row = cell.closest("tbody").dataset.row
              this.pushEventTo(this.el, "toggle", {row, relationship: cell.dataset.line})
            } else {
              button.dataset.pending = ""
              this.pushEventTo(this.el, "expand", {row: this.rowKey(cell)}, reply => {
                delete button.dataset.pending
                if (reply && typeof reply.open === "boolean") button.setAttribute("aria-expanded", String(reply.open))
              })
            }
          },

          // Follows the link a cell holds, as a click on it does.
          follow(cell) {
            const link = cell.querySelector("a[href]")
            if (link) link.click()
          },

          // Into the nested table a cell holds: to the cell it was left at,
          // or to its first.
          enterNested(cell) {
            const grid = cell.querySelector(GRID)
            const hook = grid && grid._ashTable
            if (hook) hook.move(hook.pos.r, hook.pos.c)
            return !!hook
          },

          onKeydown(e) {
            const cell = this.cellOf(e.target)
            if (!cell || e.altKey) return
            if (this.editing && e.target === this.editing.input) return this.onEditorKeydown(e)
            const control = this.controlOf(e.target)
            if (control) return this.onControlKeydown(e, control)
            const rows = this.rows()
            const head = this.headRows()
            const r = cell.parentElement.rowIndex
            const c = cell.cellIndex
            const lastC = cell.parentElement.cells.length - 1
            const lastR = rows.length - 1
            const ctrl = e.ctrlKey || e.metaKey
            let handled = true
            // the expander of a row, and a line under it
            const expands = is(cell, "expander") || is(cell, "line")
            switch (e.key) {
              // on an expander that is closed, Right Arrow opens it and Left
              // Arrow on one that is open closes it, as in a tree
              case "ArrowRight":
                if (expands && !this.isOpen(cell)) this.open(cell)
                else if (!this.spans(cell)) { this.col = Math.min(c + 1, lastC); this.move(r, this.col) }
                break
              case "ArrowLeft":
                if (expands && this.isOpen(cell)) this.open(cell)
                else if (!this.spans(cell)) { this.col = Math.max(c - 1, 0); this.move(r, this.col) }
                break
              case "ArrowDown": this.move(r + 1, this.col); break
              // from the first data row this reaches the filter row, then the header
              case "ArrowUp": this.move(r - 1, this.col); break
              case "PageDown": this.move(Math.min(r + this.pageRows(cell), lastR), this.col); break
              // stays in the data rows; the header rows are an Arrow Up further
              case "PageUp": this.move(r < head ? r : Math.max(r - this.pageRows(cell), head), this.col); break
              case "Home":
                this.col = 0
                this.move(ctrl ? Math.min(head, lastR) : r, 0)
                break
              case "End": {
                const row = ctrl ? rows[lastR] : cell.parentElement
                if (!this.spans(row.cells[0])) this.col = row.cells.length - 1
                this.move(row.rowIndex, row.cells.length - 1)
                break
              }
              case "Enter":
                if (cell.tagName === "TH" && cell.dataset.sort !== undefined) cell.click()
                else if (cell.dataset.filter !== undefined || is(cell, "pager")) this.enter(cell)
                else if (expands) this.open(cell)
                else if (is(cell, "nested")) this.enterNested(cell)
                else if (is(cell, "view")) this.follow(cell)
                else if (this.canEdit(cell)) this.startEdit(cell, null)
                else handled = false
                break
              case "F2":
                if (cell.dataset.filter !== undefined || is(cell, "pager")) this.enter(cell)
                else if (is(cell, "nested")) this.enterNested(cell)
                else if (this.canEdit(cell)) this.startEdit(cell, null)
                else handled = false
                break
              // gives up the edit of a cell whose save failed; in a nested
              // table, goes back out to the cell that holds it
              case "Escape":
                if (cell.hasAttribute("aria-invalid")) this.discard(cell)
                else if (this.holder()) this.holder().focus()
                else handled = false
                break
              // reserved for row selection; swallowed so the page does not scroll
              case " ": break
              default:
                if (PRINTABLE(e) && cell.dataset.filter !== undefined) {
                  // Typing on a filter cell goes into the filter as Enter
                  // does, and the browser goes on to type the character
                  // there: over the text or number, which is selected; into
                  // the first part of a date; to the first choice that
                  // starts with it.
                  const control = this.enter(cell)
                  handled = false
                  // A character a number does not take (a letter, say)
                  // would empty it: the number stays, as in a data cell.
                  if (control && control.type === "number") {
                    const current = control.value
                    setTimeout(() => {
                      if (document.activeElement === control && control.value === "" && !control.validity.badInput) {
                        control.value = current
                        control.select()
                      }
                    }, 0)
                  }
                } else {
                  // typing starts the edit with what is typed
                  handled = PRINTABLE(e) && this.canEdit(cell) && this.startEdit(cell, e.key)
                }
            }
            if (handled) e.preventDefault()
          },

          pageRows(cell) {
            return Math.max(1, Math.floor(window.innerHeight / (cell.offsetHeight || 24)) - 2)
          },

          // ---- editing ---------------------------------------------------

          // A cell's ids hold what an event names: `ID-row-KEY` on the row's
          // <tbody>, and `ID-row-KEY-c-COLUMN` on the cell.
          rowKey(cell) { return cell.closest("tbody").id.slice(this.id.length + 5) },
          columnOf(cell) { return cell.id.slice(cell.closest("tbody").id.length + 3) },

          editorOf(cell) { return document.getElementById(`${this.id}-editor-${this.columnOf(cell)}`) },

          // A data cell of an editable column that the server has not marked
          // as read-only for this person, and whose last save has been answered.
          canEdit(cell) {
            const body = cell.parentElement.parentElement
            return cell.tagName === "TD" && body.tagName === "TBODY" && !is(body, "detail") && !is(cell, "expander") &&
              cell.getAttribute("aria-readonly") !== "true" && !cell.hasAttribute("aria-busy") &&
              !!this.editorOf(cell)
          },

          // What a cell's editor starts with: the text the cell shows, unless
          // the server says otherwise (a choice, a boolean, a failed cell).
          valueOf(cell) {
            return cell.dataset.value !== undefined ? cell.dataset.value : cell.textContent
          },

          // Opens the column's editor in the cell. `key` is the character
          // that was typed on the cell, or null for Enter, F2 and a double
          // click. Returns whether the key has been dealt with here; if not,
          // the browser goes on to type it into the editor, which has the
          // focus by then.
          startEdit(cell, key) {
            const template = this.editorOf(cell)
            const type = template.dataset.editor
            // a boolean has no edit mode: Enter and F2 toggle it, typing does nothing
            if (type === "boolean") {
              if (key === null) this.toggle(cell, template)
              return key === null
            }
            const input = template.content.firstElementChild.cloneNode(true)
            const current = this.valueOf(cell)
            const saved = Array.from(cell.childNodes)
            // LiveView leaves an element marked like this alone, so a patch of
            // the row, after another cell's save, does not take the editor away.
            cell.setAttribute("phx-update", "ignore")
            cell.replaceChildren(input)
            // What "unchanged" means: the value the record has, as this
            // editor writes it. A failed cell shows what was typed instead.
            input.value = cell.dataset.saved !== undefined ? cell.dataset.saved : current
            const old = input.value
            input.value = current
            const ed = {cell, input, type, saved, old, confirm: template.dataset.confirm, lastKey: null}
            this.editing = ed
            cell.tabIndex = -1
            input.addEventListener("blur", () => this.onEditorBlur(ed))
            let handled = true
            if (type === "enum") {
              input.addEventListener("change", () => this.onEditorChange(ed))
              input.addEventListener("pointerdown", () => { ed.lastKey = null })
              // a typed character goes to the first choice that starts with
              // it, as it would in the menu; nothing is saved by that alone
              if (key !== null) {
                const letter = key.toLowerCase()
                const option = Array.from(input.options).find(o => o.textContent.trim().toLowerCase().startsWith(letter))
                if (option) input.value = option.value
                ed.lastKey = "ArrowDown"
              }
              input.focus()
              try { input.showPicker() } catch (_error) { /* the closed menu works too */ }
            } else if (type === "text") {
              input.addEventListener("input", () => this.fit(input))
              // typing replaces the text; the character itself is typed by the browser
              if (key !== null) { input.value = ""; handled = false }
              this.fit(input)
              input.focus()
              if (key === null) input.select()
            } else if (type === "number") {
              input.focus()
              if (key === null) input.select()
              else {
                // Typing replaces the number, if the input takes the character.
                // One it does not take changes nothing: the number stays.
                input.value = ""
                handled = false
                setTimeout(() => {
                  if (this.editing === ed && input.value === "" && !input.validity.badInput) {
                    input.value = current
                    input.select()
                  }
                }, 0)
              }
            } else {
              // A date or a datetime keeps its value: a digit typed on the
              // cell goes into the first part of the input, any other
              // character the input ignores.
              input.focus()
              handled = key === null
            }
            return handled
          },

          // A textarea as high as its text, up to eight lines or so.
          fit(input) {
            input.style.height = "auto"
            input.style.height = `${Math.min(input.scrollHeight, 160)}px`
          },

          // While a cell is edited the keys belong to its editor, the arrow
          // keys among them. The grid keeps two; Tab leaves the grid, which
          // saves.
          onEditorKeydown(e) {
            const ed = this.editing
            ed.lastKey = PRINTABLE(e) ? "ArrowDown" : e.key
            switch (e.key) {
              case "Escape":
                e.preventDefault()
                this.finish(ed, false, true)
                break
              case "Enter":
                // a new line in text
                if (ed.type === "text" && e.shiftKey) return
                if (ed.type === "enum") {
                  // an open menu takes Enter as the choice, which saves; a
                  // closed one has its value already
                  setTimeout(() => this.finish(ed, true, true), 0)
                  return
                }
                e.preventDefault()
                this.finish(ed, true, true)
                break
            }
          },

          // A choice saves when it is made: picked from the open menu, or
          // with the pointer. Moving through a closed menu with the keys
          // changes the value at every step, which is not yet a choice;
          // Enter or leaving the cell makes it one.
          onEditorChange(ed) {
            if (SELECT_KEYS.includes(ed.lastKey)) return
            this.finish(ed, true, true)
          },

          onEditorBlur(ed) {
            // Leaving the window is not leaving the cell.
            if (!document.hasFocus()) return
            // Focus is on its way to somewhere else: nothing pulls it back.
            // The editor is taken out of the cell once focus has arrived,
            // as Tab goes on from where the editor stands.
            setTimeout(() => this.finish(ed, true, false), 0)
          },

          // Ends an edit: saves the value if it has changed, after asking
          // when the column has a question, or gives it up. `refocus` puts
          // focus on the cell, for Enter and Escape; after a blur it is left
          // where the person has put it.
          finish(ed, save, refocus) {
            if (this.editing !== ed || ed.asking) return
            if (!ed.cell.isConnected) { this.editing = null; return }
            if (save && ed.input.value !== ed.old && ed.confirm) {
              ed.asking = true
              this.ask(ed.confirm).then(confirmed => {
                ed.asking = false
                if (this.editing !== ed) return
                // Cancel: back in the editor, with what was typed
                if (confirmed) this.close(ed, true, refocus)
                else ed.input.focus()
              })
            } else {
              this.close(ed, save, refocus)
            }
          },

          close(ed, save, refocus) {
            const {cell, input} = ed
            const value = input.value
            // The cell as the server last sent it: as it was when the
            // editor opened, or as a patch of its row has brought it since.
            const restore = () => cell.replaceChildren(...ed.saved)
            for (const [name, value] of ed.attributes || []) {
              if (value === null) cell.removeAttribute(name)
              else cell.setAttribute(name, value)
            }
            const failed = cell.hasAttribute("aria-invalid")
            this.editing = null
            cell.removeAttribute("phx-update")
            if (save && value !== ed.old) {
              // shows what was typed until the server has answered
              const option = ed.type === "enum" && input.selectedOptions[0]
              cell.replaceChildren(document.createTextNode(option ? option.textContent : value))
              this.save(cell, value, ed.old, restore)
            } else {
              // given up, or back at the value the record has: nothing is
              // saved, and a failed edit of the cell is given up with it
              restore()
              if (failed) this.discard(cell)
            }
            // the cell is the grid's tab stop again, unless focus has gone to another cell
            if (this.tree().activeId === cell.id) cell.tabIndex = 0
            if (refocus) cell.focus()
          },

          // A boolean: toggled and saved at once.
          toggle(cell, template) {
            const value = this.valueOf(cell) === "true" ? "false" : "true"
            const old = cell.dataset.saved !== undefined ? cell.dataset.saved : this.valueOf(cell)
            const commit = () => {
              // back at the value the record has: the failed edit is given up
              if (cell.hasAttribute("aria-invalid") && value === old) return this.discard(cell)
              const saved = Array.from(cell.childNodes)
              const box = template.content.firstElementChild.cloneNode(true)
              box.checked = value === "true"
              cell.replaceChildren(box)
              this.save(cell, value, old, () => cell.replaceChildren(...saved))
            }
            if (!template.dataset.confirm) return commit()
            this.ask(template.dataset.confirm).then(confirmed => {
              if (confirmed) commit()
              cell.focus()
            })
          },

          // Sends the value. The answer is a patch of the row, which takes
          // `aria-busy` away with everything else this hook put into the
          // cell. Where no patch came, the cell is put back as it was: the
          // server refused the event, or the record is gone, and then the
          // cell is marked here.
          save(cell, value, old, restore) {
            cell.setAttribute("aria-busy", "true")
            const payload = {row: this.rowKey(cell), column: this.columnOf(cell), value}
            this.pushEventTo(this.el, "save", payload, reply => {
              if (!cell.isConnected || !cell.hasAttribute("aria-busy")) return
              cell.removeAttribute("aria-busy")
              if (reply && reply.error) this.mark(cell, value, old, reply.error, restore)
              else restore()
            })
          },

          // Marks a cell as failed the way the server does, for a record
          // that is gone.
          mark(cell, value, old, message, restore) {
            const template = document.getElementById(`${this.id}-failure`)
            const error = template.content.firstElementChild.cloneNode(true)
            error.id = `${cell.id}-error`
            error.textContent = message
            if (!this.marked.has(cell)) this.marked.set(cell, restore)
            const stale = document.getElementById(error.id)
            if (stale) stale.remove()
            cell.append(error)
            cell.setAttribute("aria-invalid", "true")
            cell.setAttribute("aria-describedby", error.id)
            cell.dataset.value = value
            cell.dataset.saved = old
            this.showMessage()
          },

          // Gives up the edit of a failed cell: the server puts the row back
          // with the value the record has.
          discard(cell) {
            const restore = this.marked.get(cell)
            if (restore) {
              this.marked.delete(cell)
              cell.removeAttribute("aria-invalid")
              cell.removeAttribute("aria-describedby")
              delete cell.dataset.value
              delete cell.dataset.saved
              restore()
              this.showMessage()
            } else {
              this.pushEventTo(this.el, "discard", {row: this.rowKey(cell), column: this.columnOf(cell)})
            }
          },

          // ---- the dialog --------------------------------------------------

          // Asks a question in the table's dialog and resolves to whether it
          // was confirmed. Escape closes the dialog as Cancel does. When it
          // closes, the browser puts focus back where it was.
          ask(question) {
            const dialog = document.getElementById(`${this.id}-dialog`)
            if (!dialog || !dialog.showModal) return Promise.resolve(true)
            document.getElementById(`${this.id}-dialog-question`).textContent = question
            dialog.returnValue = ""
            return new Promise(resolve => {
              dialog.addEventListener("close", () => resolve(dialog.returnValue === "confirm"), {once: true})
              // focus goes to the dialog's first control: Cancel, the safe answer
              dialog.showModal()
            })
          },

          // ---- the message of a failed cell ----------------------------------

          onPointer(cell) {
            if (cell === this.pointed) return
            this.pointed = cell
            this.showMessage()
          },

          // The message of a failed cell is a popover: shown under the cell
          // while the cell has the pointer or focus, without making the row
          // higher. The pointer wins, as it says where the person is looking.
          showMessage() {
            const failed = cell => cell && cell.isConnected && cell.hasAttribute("aria-invalid") ? cell : null
            const cell = failed(this.pointed) || failed(this.cellOf(document.activeElement))
            const message = cell && document.getElementById(cell.getAttribute("aria-describedby"))
            if (this.message && this.message !== message) {
              if (this.message.isConnected && this.message.matches(":popover-open")) this.message.hidePopover()
              this.message = null
            }
            if (!message || !message.showPopover) return
            if (!message.matches(":popover-open")) message.showPopover()
            const box = cell.getBoundingClientRect()
            message.style.top = `${box.bottom + 2}px`
            message.style.left = `${Math.max(0, box.left)}px`
            this.message = message
          }
        }
      </script>
    </div>
    """
  end

  # What is under an expanded row: one line per relationship the person is
  # offered, and under an open line the row whose one cell holds the nested
  # table. A line is a cell that spans the table, with a button that says
  # whether it is open; so is the cell of a nested table, which the hook lets
  # a person go into and come back out of.
  #
  # The nested table is named by its line and by the first cell of the row
  # it belongs to ("Comments" and "Write the report"): both are on the page,
  # so the name follows the row when it is edited, and the server keeps
  # nothing for it.
  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :model, :map, required: true
  attr :reader, :map, required: true

  defp lines(assigns) do
    assigns =
      assign(assigns,
        row_id: "#{assigns.id}-row-#{assigns.row.key}",
        colspan: length(assigns.model.columns) + 1,
        first: List.first(assigns.model.columns)
      )

    ~H"""
    <%= for relationship <- @model.relationships do %>
      <tr id={"#{@row_id}-l-#{relationship.name}"} role="row">
        <td
          id={"#{@row_id}-l-#{relationship.name}-c"}
          role="gridcell"
          colspan={@colspan}
          aria-colindex="1"
          tabindex="-1"
          data-line={relationship.name}
          class="py-1 ps-10"
        >
          <button
            type="button"
            id={"#{@row_id}-l-#{relationship.name}-b"}
            tabindex="-1"
            aria-expanded={to_string(relationship.name in @row.lines)}
            class="text-sm font-medium"
          >
            <span aria-hidden="true">▸</span> {relationship.label}
          </button>
        </td>
      </tr>
      <tr
        :if={relationship.name in @row.lines}
        id={"#{@row_id}-n-#{relationship.name}"}
        role="row"
      >
        <td
          id={"#{@row_id}-n-#{relationship.name}-c"}
          role="gridcell"
          colspan={@colspan}
          aria-colindex="1"
          tabindex="-1"
          data-nested
          data-line-cell={"#{@row_id}-l-#{relationship.name}-c"}
          data-expander-cell={"#{@row_id}-e"}
          class="pt-0 pb-3 ps-10"
        >
          <%!-- No wider than the cell for the layout of the table around it,
          whatever the nested table would like: the columns around it stay as they
          are. A nested table that is wider reaches out of the cell to the right,
          and the grid on the page scrolls for it: one region that scrolls, the one
          that holds the tab stop, and none inside it that the keyboard could not
          reach with Tab. --%>
          <div class="w-0 min-w-full border-s-2 border-base-300 ps-3">
            <.live_component
              module={__MODULE__}
              id={"#{@row_id}-t-#{relationship.name}"}
              resource={relationship.destination}
              via={relationship}
              parent_key={@row.pk}
              label={relationship.label}
              labelledby={
                Enum.join(
                  ["#{@row_id}-l-#{relationship.name}-b"] ++
                    if(@first, do: ["#{@row_id}-c-#{@first.name}"], else: []),
                  " "
                )
              }
              url={nil}
              mounted?={false}
              {@reader}
            />
          </div>
        </td>
      </tr>
    <% end %>
    """
  end

  # What a nested table is given of the table it is in: who is asking, how
  # deep it is, and how the table around it authorizes. `authorize?` is passed
  # on only as this table was told it; untold, a nested table authorizes as
  # its own resource's domain says.
  defp nested_reader(assigns) do
    %{
      scope: assigns.scope,
      actor: assigns.actor,
      tenant: assigns.tenant,
      authorize?: assigns.authorize_given,
      parent_authorize?: assigns.authorize?,
      depth: assigns.depth + 1,
      depth_limit: assigns.depth_limit
    }
  end

  # What is above the grid of a table that a URL limits to the records
  # related to one record: what it shows, and the way back to all records.
  #
  # The heading names the relationship, as the parent's table labels it, and
  # the record once it has been read for this person: as a link to the page
  # of the record's own table where the router mounts one. The text is one
  # message, so that a translation can put its parts in another order.
  attr :id, :string, required: true
  attr :via, :map, required: true
  attr :title, :string, default: nil
  attr :parent, :map, default: nil
  attr :clear, :string, required: true

  defp related(assigns) do
    # in the host's words, as the line of the relationship is
    label = Text.label(assigns.via.label)

    # the message with a mark where the record goes
    parts =
      :related_heading
      |> Text.t(record: "\0", relationship: label)
      |> String.split("\0", parts: 2)

    assigns =
      assign(assigns,
        label: label,
        parts: parts,
        titled?: assigns.title && match?([_, _], parts)
      )

    ~H"""
    <div id={"#{@id}-related"} class="mb-2 flex flex-wrap items-center justify-between gap-2">
      <h2 id={"#{@id}-related-heading"} class="font-semibold" phx-no-format><%= if @titled? do %>{hd(@parts)}<.link
            :if={@parent}
            id={"#{@id}-related-parent"}
            navigate={@parent.path}
            class="link"
          >{@title}</.link><span :if={!@parent} id={"#{@id}-related-parent"}>{@title}</span>{List.last(@parts)}<% else %>{@label}<% end %></h2>
      <.link id={"#{@id}-related-clear"} patch={@clear} class="btn btn-sm">
        {Text.t(:show_all_records)}
      </.link>
    </div>
    """
  end

  # Whether a nested table has its link to the full view: the router mounts
  # the destination's table, and the nested table has been read.
  defp full_view?(page, full_view), do: not is_nil(page) and not is_nil(full_view)

  # Whether there are pages to go through.
  defp pages?(page, model), do: not is_nil(page) and model.pagination.strategy != :none

  # The pages of a table: where the page is among the records, and the
  # controls to go to another. Under a table of its own it is a navigation
  # landmark after the grid, whose controls are ordinary tab stops. In a
  # nested table it is a group in the last row of the grid, and its controls
  # are reached through that row's cell.
  #
  # The hook keeps focus on the control that was used, or sends it on when
  # that control is gone (see `.Pagination` below).
  attr :id, :string, required: true
  attr :nested?, :boolean, required: true
  attr :page, :map, required: true
  attr :model, :map, required: true
  attr :state, :map, required: true
  attr :row_count, :integer, required: true
  attr :label, :string, required: true
  attr :target, :any, required: true

  defp pagination(assigns) do
    ~H"""
    <nav
      :if={not @nested?}
      id={"#{@id}-pagination"}
      phx-hook=".Pagination"
      aria-label={Text.t(:pagination, table: @label)}
      class="mt-4 flex flex-wrap items-center justify-between gap-4"
    >
      <.pages {assigns} />
    </nav>
    <div
      :if={@nested?}
      id={"#{@id}-pagination"}
      phx-hook=".Pagination"
      role="group"
      aria-label={Text.t(:pagination, table: @label)}
      class="flex flex-wrap items-center justify-between gap-4"
    >
      <.pages {assigns} />
    </div>
    """
  end

  defp pages(assigns) do
    ~H"""
    <p id={"#{@id}-range"} class="text-sm">{range_text(@page, @row_count, @state)}</p>
    <div class="join">
      <button
        type="button"
        id={"#{@id}-previous"}
        class="join-item btn btn-sm"
        tabindex={@nested? && "-1"}
        disabled={is_nil(@page.previous)}
        phx-click="page"
        phx-value-to="previous"
        phx-target={@target}
      >
        {Text.t(:previous)}
      </button>
      <%!-- The page numbers have an element to themselves, which the layout
      does not see: Previous and Next are then always the first and the last
      of three, and a patch that adds or takes away a number leaves them
      where they are, with their focus. --%>
      <span
        :if={@model.pagination.strategy == :offset}
        class="contents [&>:first-child]:ms-[calc(var(--border)*-1)]"
      >
        <button
          :for={number <- page_numbers(@page, @state)}
          type="button"
          id={"#{@id}-page-#{number}"}
          class={["join-item btn btn-sm", number == @state.page && "btn-active"]}
          tabindex={@nested? && "-1"}
          aria-label={Text.t(:go_to_page, page: number)}
          aria-current={number == @state.page && "page"}
          phx-click="page"
          phx-value-to={number}
          phx-target={@target}
        >
          {number}
        </button>
      </span>
      <button
        type="button"
        id={"#{@id}-next"}
        class="join-item btn btn-sm"
        tabindex={@nested? && "-1"}
        disabled={is_nil(@page.next)}
        phx-click="page"
        phx-value-to="next"
        phx-target={@target}
      >
        {Text.t(:next)}
      </button>
    </div>
    """
  end

  # The controls of one column's filter, showing the filter that applies.
  # They are out of the tab order: the grid is one tab stop, and the hook
  # moves focus into a filter cell.
  defp filter(assigns) do
    {operator, value} = assigns.filter || {nil, nil}
    assigns = assign(assigns, operator: operator, value: value)

    ~H"""
    <div class="flex items-center gap-1">
      <select
        :if={@column.cell_type == :boolean}
        id={"#{@id}-value"}
        name={"filter[#{@column.name}][o]"}
        form={@form}
        tabindex="-1"
        aria-label={Text.t(:filter, column: @column.label)}
        class="select select-xs w-auto"
      >
        <option value="">{Text.t(:any)}</option>
        <option :for={choice <- @column.operators} value={choice} selected={choice == @operator}>
          {Text.t(choice)}
        </option>
      </select>
      <select
        :if={@column.cell_type != :boolean and match?([_, _ | _], @column.operators)}
        id={"#{@id}-operator"}
        name={"filter[#{@column.name}][o]"}
        form={@form}
        tabindex="-1"
        aria-label={Text.t(:filter_operator, column: @column.label)}
        class="select select-xs w-auto"
      >
        <option :for={choice <- @column.operators} value={choice} selected={choice == @operator}>
          {operator_text(choice)}
        </option>
      </select>
      <select
        :if={@column.cell_type == :enum}
        id={"#{@id}-value"}
        name={"filter[#{@column.name}][v]"}
        form={@form}
        tabindex="-1"
        aria-label={Text.t(:filter, column: @column.label)}
        class="select select-xs w-auto"
      >
        <option value="">{Text.t(:any)}</option>
        <option
          :for={{choice, label} <- @column.values}
          value={choice}
          selected={to_string(choice) == @value}
        >
          {label}
        </option>
      </select>
      <%!-- an operator such as "is empty" is complete without a value --%>
      <input
        :if={
          @column.cell_type not in [:boolean, :enum] and
            (is_nil(@operator) or Operator.takes_value?(@operator))
        }
        type={input_type(@column.cell_type)}
        step={input_step(@column.cell_type)}
        id={"#{@id}-value"}
        name={"filter[#{@column.name}][v]"}
        form={@form}
        value={@value}
        phx-debounce="blur"
        tabindex="-1"
        aria-label={Text.t(:filter, column: @column.label)}
        aria-invalid={@rejected? && "true"}
        aria-describedby={@rejected? && "#{@id}-error"}
        class={["input input-xs w-32", @rejected? && "input-error"]}
      />
      <button
        :if={@filter && not @rejected?}
        type="button"
        id={"#{@id}-clear"}
        tabindex="-1"
        aria-label={Text.t(:clear_filter, column: @column.label)}
        class="btn btn-ghost btn-xs"
        phx-click="clear_filter"
        phx-value-column={@column.name}
        phx-target={@target}
      >
        <span aria-hidden="true">✕</span>
      </button>
    </div>
    <%!-- in the text colour: the error colour is too faint for small text --%>
    <p :if={@rejected?} id={"#{@id}-error"} class="mt-1 text-xs">
      {Text.t(:invalid_filter)}
    </p>
    """
  end

  # What a cell of an editable column is edited with: the native control of
  # its cell type, without a name or a form, as the hook reads its value and
  # sends it. It takes the place of the cell's text, so it has the text's
  # size and no border of its own; the cell shows the focus.
  attr :column, :map, required: true
  attr :allow_nil?, :boolean, required: true

  # Text is edited in a textarea, so that text of several lines keeps its
  # lines. It is one line high until the text needs more.
  defp editor(%{column: %{editor: :text}} = assigns) do
    ~H"""
    <textarea
      rows="1"
      aria-label={@column.label}
      class="block w-full min-w-40 resize-none bg-transparent p-0 text-sm break-words whitespace-pre-wrap outline-none"
    ></textarea>
    """
  end

  defp editor(%{column: %{editor: :boolean}} = assigns) do
    ~H"""
    <input
      type="checkbox"
      tabindex="-1"
      aria-label={@column.label}
      class="checkbox checkbox-xs pointer-events-none"
    />
    """
  end

  defp editor(%{column: %{editor: :enum}} = assigns) do
    ~H"""
    <select
      aria-label={@column.label}
      class="block h-5 w-full bg-transparent p-0 text-sm outline-none"
    >
      <option :if={@allow_nil?} value=""></option>
      <option :for={{choice, label} <- @column.values} value={choice}>{label}</option>
    </select>
    """
  end

  defp editor(assigns) do
    ~H"""
    <input
      type={input_type(@column.editor)}
      step={input_step(@column.editor)}
      aria-label={@column.label}
      class="block h-5 w-full min-w-24 bg-transparent p-0 text-sm outline-none"
    />
    """
  end

  # A choice that can be empty offers the empty choice.
  defp allow_nil?(resource, column) do
    Ash.Resource.Info.attribute(resource, column.name).allow_nil?
  end

  defp operator_text(operator), do: Text.t(String.to_existing_atom("operator_#{operator}"))

  # The native input of each cell type that is filtered by a typed value.
  defp input_type(:text), do: "text"
  defp input_type(:number), do: "number"
  defp input_type(:date), do: "date"
  defp input_type(:datetime), do: "datetime-local"

  # Any number, not only whole ones; and a datetime to the second, as it is shown.
  defp input_step(:number), do: "any"
  defp input_step(:datetime), do: "1"
  defp input_step(_cell_type), do: nil

  # The columns before the first data column: the expanders, when the rows
  # have them.
  defp lead(true), do: 1
  defp lead(false), do: 0

  # 1-based position of a data column among all columns of the grid.
  defp colindex(index, expandable?), do: lead(expandable?) + index + 1

  # The header rows are counted. -1 says the total is not known.
  defp aria_rowcount(%{total: total}) when is_integer(total), do: total + @header_rows
  defp aria_rowcount(_page), do: -1

  defp aria_sort({name, :asc}, %{name: name}), do: "ascending"
  defp aria_sort({name, :desc}, %{name: name}), do: "descending"
  defp aria_sort(_sort, _column), do: "none"

  defp sort_mark({name, :asc}, %{name: name}), do: " ▲"
  defp sort_mark({name, :desc}, %{name: name}), do: " ▼"
  defp sort_mark(_sort, _column), do: ""

  # What a cell says about editing, for people and for the hook:
  #
  #   * `aria-readonly` on a cell that cannot be edited, when the table
  #     offers editing at all;
  #   * `data-value` where the editor's value is not the text the cell shows:
  #     a choice and a boolean, and a cell whose save failed, which shows
  #     what was typed;
  #   * on a cell whose save failed, also `aria-invalid`, `aria-describedby`
  #     naming the action's message, and `data-saved`, the value the record
  #     still has, which the hook compares with what is typed next.
  defp cell_attributes(false, _id, _column, _row), do: []

  defp cell_attributes(true, id, column, row) do
    value = value(column, row.record)

    case {editable?(column, value), row.failed[column.name]} do
      {false, _failure} ->
        [{"aria-readonly", "true"}]

      {true, {typed, _message}} ->
        [
          {"aria-invalid", "true"},
          {"aria-describedby", "#{id}-error"},
          {"data-value", typed},
          {"data-saved", Format.input(column, value)}
        ]

      {true, nil} when column.editor in [:boolean, :enum] ->
        [{"data-value", Format.input(column, value)}]

      {true, nil} ->
        []
    end
  end

  # What a record holds for a column. For a reference column that is the
  # label of the related record, as Ash loaded it for this person:
  #
  #   * nil where there is no related record, and where there is one that is
  #     not theirs to read. Ash gives nil for both, so the cell is empty for
  #     both, and nothing in it tells the two apart;
  #   * an `Ash.ForbiddenField` where they may read the related record and
  #     not its label, or where the read of the destination was refused as a
  #     whole: the cell of a hidden field.
  defp value(%{kind: :reference, name: name, reference: %{label_field: label}}, record) do
    case Map.get(record, name) do
      %Ash.ForbiddenField{} = hidden -> hidden
      %Ash.NotLoaded{} = not_loaded -> not_loaded
      %_{} = related -> Map.get(related, label)
      nil -> nil
    end
  end

  defp value(column, record), do: Map.get(record, column.name)

  # A cell whose save failed shows what was typed, as the cell would show it
  # had it been saved, and holds the action's message. The message is a
  # popover the hook opens while the cell has focus or the pointer, so that
  # the row keeps its height; it is in the text colour on the page's
  # background, as the error colour is too faint for small text.
  defp cell_content(id, column, row) do
    value = value(column, row.record)

    case editable?(column, value) && row.failed[column.name] do
      {typed, message} ->
        {:safe, shown} = typed |> typed(column) |> Phoenix.HTML.html_escape()
        {:safe, message} = failure_message("#{id}-error", message)
        {:safe, [shown, message]}

      _none ->
        cell(column, value)
    end
  end

  defp failure_message(id, message) do
    {:safe,
     [
       "<span",
       if(id, do: [~s( id="), escape(id), ~s(")], else: []),
       ~s( popover="manual" class="inset-auto m-0 max-w-xs rounded border border-error bg-base-100 px-2 py-1 text-xs whitespace-normal text-base-content shadow">),
       escape(message),
       "</span>"
     ]}
  end

  # What was typed into an editor, as its cell shows it.
  defp typed("true", %{editor: :boolean} = column), do: cell(column, true)
  defp typed("false", %{editor: :boolean} = column), do: cell(column, false)

  defp typed(typed, %{editor: :enum, values: values}) do
    Enum.find_value(values, typed, fn {value, label} -> to_string(value) == typed && label end)
  end

  defp typed(typed, _column), do: typed

  # Whether a person can edit this cell: its column is editable, and the
  # field is not hidden from them on this row.
  defp editable?(_column, %Ash.ForbiddenField{}), do: false
  defp editable?(column, _value), do: column.editable?

  # A field the actor may not see on this row looks empty and is announced.
  defp cell(_column, %Ash.ForbiddenField{}) do
    {:safe, [~s(<span class="sr-only">), escape(Text.t(:not_available)), "</span>"]}
  end

  # A boolean is a check indicator with its accessible text beside it;
  # everything else is plain text.
  defp cell(%{cell_type: :boolean} = column, value) when is_boolean(value) do
    mark = if value, do: "✓", else: "–"

    {:safe,
     [
       ~s(<span aria-hidden="true">),
       mark,
       ~s(</span><span class="sr-only">),
       escape(Format.format(column, value)),
       "</span>"
     ]}
  end

  defp cell(column, value), do: Format.format(column, value)

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp range_text(%{offset: offset, total: total}, row_count, _state)
       when is_integer(offset) and row_count > 0 do
    bindings = [from: offset + 1, to: offset + row_count, total: total]
    if total, do: Text.t(:range_of_total, bindings), else: Text.t(:range, bindings)
  end

  defp range_text(%{offset: offset}, _row_count, state) when is_integer(offset),
    do: Text.t(:page, page: state.page)

  # Keyset pagination: the page does not know its place among the others, so
  # the total is all there is to say, when the action counts.
  defp range_text(%{total: total}, _row_count, _state) when is_integer(total),
    do: Text.n(:records, total)

  defp range_text(_page, _row_count, _state), do: nil

  # The page numbers offered: the first, the last and those around the
  # current one, of the pages there are; and the current one, also when the
  # URL asked for a page beyond the last. Without a total only the current
  # page is known.
  defp page_numbers(%{pages: pages}, %{page: current}) when is_integer(pages) do
    [1, pages | Enum.to_list((current - 2)..(current + 2)//1)]
    |> Enum.filter(&((&1 >= 1 and &1 <= pages) or &1 == current))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp page_numbers(_page, %{page: current}), do: [current]
end
