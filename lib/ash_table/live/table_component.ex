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
  #   * `aria-colindex` is computed through `colindex/1`, which is where a
  #     leading expander column will be counted in; an actions column goes
  #     after the last data column. Neither position holds a cell yet.
  #
  # Use it through `AshTable.table/1`.
  use Phoenix.LiveComponent

  require Logger

  alias AshTable.Edit
  alias AshTable.Errors
  alias AshTable.Format
  alias AshTable.Model
  alias AshTable.Model.Operator
  alias AshTable.Query
  alias AshTable.Resource.Info, as: TableInfo
  alias AshTable.State
  alias AshTable.Text
  alias Phoenix.LiveView.JS

  # Columns before the first data column: none until rows can be expanded.
  @leading_columns 0

  # The rows above the data rows: the header and the filter row.
  @header_rows 2

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> stream_configure(:rows, dom_id: & &1.dom_id)
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
     |> assign(rejected: %{})}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      assign(
        socket,
        Map.take(
          assigns,
          [:id, :resource, :scope, :actor, :tenant, :authorize?, :url, :label, :mounted?]
        )
      )

    # Unless the table is told, it authorizes as its resource's domain says.
    socket =
      assign(socket,
        authorize?:
          case socket.assigns[:authorize?] do
            nil -> AshTable.Domain.Info.authorize?(socket.assigns.resource)
            authorize? -> authorize?
          end
      )

    # The table as the person asking meets it: without the columns they can
    # never see, and with the columns they can never edit read-only. Ash is
    # asked again on every update, which for a table with its state in the
    # URL is every sort, filter and page change; it costs no query.
    model =
      socket.assigns.resource
      |> Model.build()
      |> Model.for_actor(reader(socket.assigns))
      |> in_words()

    state = current_state(socket.assigns, model)

    {:ok,
     socket
     |> assign(model: model, state: state, editing?: Enum.any?(model.columns, & &1.editable?))
     |> read()}
  end

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

    %{model | columns: columns}
  end

  # A table whose state lives in the URL takes it from there on every update;
  # an embedded table keeps what its own events set.
  defp current_state(%{url: url, id: id}, model) when is_binary(url) do
    State.from_params(model, url |> query_params() |> Map.get(id))
  end

  defp current_state(%{state: state}, _model), do: state

  # Reads again only when something a read depends on has changed. The first
  # read is done in place, so that the first render has rows; later ones run
  # beside the process, with the previous rows left in view and the grid
  # marked busy.
  defp read(socket) do
    %{model: model, state: state} = socket.assigns
    opts = reader(socket.assigns)
    read = {model, state, opts}

    cond do
      read == socket.assigns.read ->
        socket

      is_nil(socket.assigns.read) ->
        socket |> assign(read: read) |> show(Query.read(model, state, opts), :first)

      true ->
        socket
        |> assign(read: read, busy?: true)
        |> start_async(:read, fn -> Query.read(model, state, opts) end)
    end
  end

  # Who is reading and saving.
  defp reader(assigns), do: Map.to_list(Map.take(assigns, [:scope, :actor, :tenant, :authorize?]))

  @impl true
  def handle_async(:read, {:ok, result}, socket) do
    {:noreply, socket |> assign(busy?: false) |> show(result, :later)}
  end

  def handle_async(:read, {:exit, reason}, socket) do
    {:noreply, socket |> assign(busy?: false) |> show({:error, reason}, :later)}
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
          # 1-based, the header rows counted
          rowindex: (page.offset || 0) + index + @header_rows + 1
        }
      end)

    socket
    |> assign(page: %{page | records: []}, row_count: length(rows), error: nil, gone?: false)
    |> assign(
      rows: Map.new(rows, &{&1.key, %{rowindex: &1.rowindex, pk: primary_key(model, &1.record)}}),
      failed: %{}
    )
    |> announce(page)
    |> stream(:rows, Enum.map(rows, &item(id, &1.key, &1.record, &1.rowindex, %{})), reset: true)
  end

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

  # The error is an alert of its own.
  defp show_error(socket, error) do
    socket
    |> assign(page: nil, row_count: 0, rows: %{}, failed: %{}, announce?: false, gone?: false)
    |> assign(error: error_text(error, socket.assigns.model))
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
  # typed into a cell whose save failed and the action's message.
  defp item(id, key, record, rowindex, failed) do
    %{dom_id: "#{id}-row-#{key}", record: record, rowindex: rowindex, failed: failed}
  end

  # Puts a row of the page into the stream again, in its place: with the
  # record as an action returned it or as it was read again, and with the
  # edits of the row that have failed.
  defp put_row(socket, key, record) do
    %{id: id, rows: rows, failed: failed} = socket.assigns
    cells = get_in(failed, [key, :cells]) || %{}

    stream_insert(socket, :rows, item(id, key, record, rows[key].rowindex, cells))
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

  # After a filter change, the result is put into the live region: the count
  # when the read action counts, else only that the rows have changed.
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

  # Sent by the form of the filter row when a filter is left or a choice is
  # made, with every filter of the row.
  def handle_event("filter", params, socket) do
    %{state: state, model: model} = socket.assigns
    {state, rejected} = State.filter(state, model, Map.get(params, "filter", %{}))

    {:noreply, socket |> assign(rejected: rejected) |> refilter(state)}
  end

  def handle_event("clear_filter", %{"column" => name}, socket) do
    {:noreply, refilter(socket, State.clear_filter(socket.assigns.state, name))}
  end

  def handle_event("clear_filters", _params, socket) do
    state = State.clear_filters(socket.assigns.state)

    {:noreply, socket |> assign(rejected: %{}) |> refilter(state)}
  end

  def handle_event("page", %{"to" => to}, socket) do
    {:noreply, go(socket, target(socket.assigns, to))}
  end

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
    params =
      case State.to_params(state, socket.assigns.model) do
        empty when empty == %{} -> Map.delete(query_params(url), id)
        params -> Map.put(query_params(url), id, params)
      end

    path = URI.parse(url).path || "/"

    to =
      if params == %{}, do: path, else: path <> "?" <> Plug.Conn.Query.encode(params)

    push_patch(socket, to: to)
  end

  defp go(socket, state), do: socket |> assign(state: state) |> read()

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
      <div id={"#{@id}-grid"} phx-hook=".Grid" phx-target={@myself} class="overflow-x-auto">
        <table
          id={"#{@id}-table"}
          role="grid"
          aria-label={@label}
          aria-rowcount={aria_rowcount(@page)}
          aria-colcount={length(@model.columns)}
          aria-busy={@busy? && "true"}
          class={
            [
              "table aria-busy:opacity-60",
              # what every cell looks like is set once here, to keep each cell's markup small:
              # the focus ring, which a cell keeps while its editor has the focus
              "[&_:is(td,th):focus]:outline-2 [&_:is(td,th):focus]:-outline-offset-2 [&_:is(td,th):focus]:outline-primary",
              "[&_tbody_td:focus-within]:outline-2 [&_tbody_td:focus-within]:-outline-offset-2 [&_tbody_td:focus-within]:outline-primary",
              # a cell whose save failed, and one whose save is on its way
              "[&_td[aria-invalid]]:inset-ring-2 [&_td[aria-invalid]]:inset-ring-error [&_td[aria-busy]]:opacity-60",
              # one line per row: long text is cut off, not wrapped
              "[&_tbody_td]:max-w-80 [&_tbody_td]:truncate"
            ]
          }
          phx-update="stream"
        >
          <thead id={"#{@id}-head"}>
            <tr id={"#{@id}-head-row"} role="row" aria-rowindex="1">
              <th
                :for={{column, index} <- Enum.with_index(@model.columns)}
                id={"#{@id}-head-#{column.name}"}
                role="columnheader"
                scope="col"
                aria-colindex={colindex(index)}
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
                :for={{column, index} <- Enum.with_index(@model.columns)}
                id={"#{@id}-filter-#{column.name}"}
                role="gridcell"
                aria-colindex={colindex(index)}
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
          whenever the row is, and a cell's text must not be padded. --%>
          <tbody :for={{dom_id, row} <- @streams.rows} id={dom_id} phx-no-format><tr
            id={"#{dom_id}-r"}
            role="row"
            aria-rowindex={row.rowindex}
          ><td
            :for={{column, index} <- Enum.with_index(@model.columns)}
            id={"#{dom_id}-c-#{column.name}"}
            role="gridcell"
            aria-colindex={colindex(index)}
            tabindex="-1"
            {cell_attributes(@editing?, "#{dom_id}-c-#{column.name}", column, row)}
          >{cell_content("#{dom_id}-c-#{column.name}", column, row)}</td></tr></tbody>
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
      <p :if={@error} id={"#{@id}-error"} role="alert" class="py-8 text-center text-sm font-medium">
        {@error}
      </p>
      <p
        :if={is_nil(@error) and @row_count == 0}
        id={"#{@id}-empty"}
        class="py-8 text-center text-sm opacity-70"
      >
        {Text.t(:no_records)}
      </p>
      <nav
        :if={@page && @model.pagination.strategy != :none}
        id={"#{@id}-pagination"}
        aria-label={Text.t(:pagination, table: @label)}
        class="mt-4 flex flex-wrap items-center justify-between gap-4"
      >
        <p id={"#{@id}-range"} class="text-sm">{range_text(@page, @row_count, @state)}</p>
        <div class="join">
          <button
            type="button"
            id={"#{@id}-previous"}
            class="join-item btn btn-sm"
            disabled={is_nil(@page.previous)}
            phx-click="page"
            phx-value-to="previous"
            phx-target={@myself}
          >
            {Text.t(:previous)}
          </button>
          <button
            :for={number <- page_numbers(@page, @state)}
            :if={@model.pagination.strategy == :offset}
            type="button"
            id={"#{@id}-page-#{number}"}
            class={["join-item btn btn-sm", number == @state.page && "btn-active"]}
            aria-label={Text.t(:go_to_page, page: number)}
            aria-current={number == @state.page && "page"}
            phx-click="page"
            phx-value-to={number}
            phx-target={@myself}
          >
            {number}
          </button>
          <button
            type="button"
            id={"#{@id}-next"}
            class="join-item btn btn-sm"
            disabled={is_nil(@page.next)}
            phx-click="page"
            phx-value-to="next"
            phx-target={@myself}
          >
            {Text.t(:next)}
          </button>
        </div>
      </nav>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Grid">
        // Keyboard, focus and editing for one grid: a single tab stop with a
        // roving tabindex, moved by the arrow keys.
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

        export default {
          mounted() {
            // the table's id, which every id in it starts with
            this.id = this.el.id.replace(/-grid$/, "")
            // the cell arrow keys start from: the first cell of the first data
            // row, or of the last header row while there are no rows
            this.pos = {r: this.headRows(), c: 0}
            this.col = 0
            this.activeId = null
            this.hadFocus = false
            // the edit in progress: {cell, input, type, saved, old, confirm},
            // and `attributes` once a patch has brought the cell's row again
            this.editing = null
            // cells this hook has marked as failed itself, with what they showed before
            this.marked = new WeakMap()
            // the cell under the pointer, and the message that is showing
            this.pointed = null
            this.message = null
            this.el.addEventListener("keydown", e => this.onKeydown(e))
            this.el.addEventListener("focusin", e => this.onFocusin(e))
            this.el.addEventListener("focusout", e => this.onFocusout(e))
            this.el.addEventListener("click", e => this.onClick(e))
            this.el.addEventListener("dblclick", e => this.onDblclick(e))
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
            return cell && this.el.contains(cell) ? cell : null
          },

          cellAt(r, c) {
            const rows = this.rows()
            if (rows.length === 0) return null
            const row = rows[Math.max(0, Math.min(r, rows.length - 1))]
            return row.cells[Math.max(0, Math.min(c, row.cells.length - 1))] || null
          },

          setActive(cell) {
            const previous = this.activeId && document.getElementById(this.activeId)
            if (previous && previous !== cell && previous.tabIndex !== -1) previous.tabIndex = -1
            this.activeId = cell.id
            this.pos = {r: cell.parentElement.rowIndex, c: cell.cellIndex}
            // while a cell is edited its editor is the tab stop, so that
            // Shift+Tab from the editor leaves the grid as Tab does
            const tabIndex = this.editing && this.editing.cell === cell ? -1 : 0
            if (cell.tabIndex !== tabIndex) cell.tabIndex = tabIndex
          },

          // After every patch: the server renders each cell with tabindex -1,
          // so the one tab stop has to be put back, and so has focus when the
          // focused cell did not survive the patch.
          sync() {
            let cell = this.activeId && document.getElementById(this.activeId)
            if (cell && !this.el.contains(cell)) cell = null
            if (!cell) cell = this.cellAt(this.pos.r, this.pos.c)
            if (!cell) return
            this.setActive(cell)
            // while the dialog asks, focus is in the dialog and stays there
            if (this.editing && this.editing.asking) return
            if (this.hadFocus && !this.el.contains(document.activeElement)) {
              cell.focus({preventScroll: true})
            }
            // a patch may have brought, replaced or taken away a message
            this.showMessage()
          },

          move(r, c) {
            const cell = this.cellAt(r, c)
            if (cell) cell.focus()
          },

          onFocusin(e) {
            const cell = this.cellOf(e.target)
            if (!cell) { this.hadFocus = false; return }
            this.hadFocus = true
            this.col = cell.cellIndex
            this.setActive(cell)
            this.showMessage()
          },

          onFocusout(e) {
            if (e.relatedTarget) {
              if (!this.el.contains(e.relatedTarget)) this.hadFocus = false
            } else {
              // No new target: either focus really left (a click on nothing),
              // or a patch removed the focused cell and sync() puts it back.
              const target = e.target
              setTimeout(() => {
                if (target.isConnected && !this.el.contains(document.activeElement)) this.hadFocus = false
              }, 0)
            }
            setTimeout(() => this.showMessage(), 0)
          },

          onClick(e) {
            const cell = this.cellOf(e.target)
            if (!cell) return
            this.col = cell.cellIndex
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
            const control = cell.querySelector("[id$='-value']") || cell.querySelector("select,button")
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
              case "Tab": {
                const controls = Array.from(cell.querySelectorAll("input,select,button"))
                const next = controls[controls.indexOf(control) + (e.shiftKey ? -1 : 1)]
                if (next) {
                  next.focus()
                  e.preventDefault()
                }
                break
              }
            }
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
            switch (e.key) {
              case "ArrowRight": this.col = Math.min(c + 1, lastC); this.move(r, this.col); break
              case "ArrowLeft": this.col = Math.max(c - 1, 0); this.move(r, this.col); break
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
                this.col = row.cells.length - 1
                this.move(row.rowIndex, this.col)
                break
              }
              case "Enter":
                if (cell.tagName === "TH" && cell.dataset.sort !== undefined) cell.click()
                else if (cell.dataset.filter !== undefined) this.enter(cell)
                else if (this.canEdit(cell)) this.startEdit(cell, null)
                else handled = false
                break
              case "F2":
                if (cell.dataset.filter !== undefined) this.enter(cell)
                else if (this.canEdit(cell)) this.startEdit(cell, null)
                else handled = false
                break
              // gives up the edit of a cell whose save failed
              case "Escape":
                if (cell.hasAttribute("aria-invalid")) this.discard(cell)
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
            return cell.tagName === "TD" && cell.parentElement.parentElement.tagName === "TBODY" &&
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
            if (this.activeId === cell.id) cell.tabIndex = 0
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

  # 1-based position of a data column among all columns of the grid.
  defp colindex(index), do: @leading_columns + index + 1

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
    value = Map.get(row.record, column.name)

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

  # A cell whose save failed shows what was typed, as the cell would show it
  # had it been saved, and holds the action's message. The message is a
  # popover the hook opens while the cell has focus or the pointer, so that
  # the row keeps its height; it is in the text colour on the page's
  # background, as the error colour is too faint for small text.
  defp cell_content(id, column, row) do
    value = Map.get(row.record, column.name)

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

  defp range_text(_page, _row_count, _state), do: nil

  # The page numbers offered: the first, the last and those around the
  # current one. Without a total only the current page is known.
  defp page_numbers(%{pages: pages}, %{page: current}) when is_integer(pages) do
    [1, pages | Enum.to_list((current - 2)..(current + 2)//1)]
    |> Enum.filter(&(&1 >= 1 and &1 <= max(pages, current)))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp page_numbers(_page, %{page: current}), do: [current]
end
