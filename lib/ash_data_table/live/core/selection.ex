defmodule AshDataTable.Live.Core.Selection do
  @moduledoc false
  # What is selected (stage 6 D10, RQ1): the entry holds it, the hook paints
  # the rows, and the line above the grid is drawn from it (`whole_page?/1`). The hook says what a person selects on every change (`select`); the
  # server decides when a selection ends or narrows, and tells the hook with
  # `ash_data_table:select` (`{table, all, rows}`, each row `[key, named]`,
  # as the hook keeps it):
  #
  #   * the filters, the arguments or what the table is limited to (`of`)
  #     changed: it was made under others, and ends (`scoped/1`, after
  #     every callback);
  #   * a row went: it is selected no longer (`gone/2`);
  #   * a run on it is done: only the rows it did not run on stay
  #     (`AshDataTable.Live.Core.Bulk`).
  #
  # The rows are what the hook names them by, the primary key of each: claims
  # until a run reads each record as the person. A picker's table holds its
  # selection too, for the picker's own flow (`picked`), and never ends it
  # under a filter: what is chosen there is kept while the person looks for
  # another record.

  import Phoenix.LiveView, only: [push_event: 3]

  alias AshDataTable.Event
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Notify
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Errors
  alias AshDataTable.Query
  alias AshDataTable.Record
  alias AshDataTable.Sensitive
  alias AshDataTable.Text

  # Sent by the hook on every change of what a person has selected: every
  # record that matches (`all`), or the rows, by their primary keys.
  def on({:select, selection}, socket), do: {:noreply, put(socket, selection, false)}

  @doc """
  Makes `selection` (`:all`, or `{:rows, rows}`) what is selected, and tells
  the host when that changed (`:selection_changed`). `told?` is for a change
  the server made, of which the hook is told.
  """
  def put(socket, selection, told?) do
    %{id: id, model: model, selected: before, all?: all_before} = Core.table(socket).entry

    {all?, rows} =
      case selection do
        :all -> {true, []}
        {:rows, rows} -> {false, Enum.uniq(rows)}
      end

    socket = Core.put(socket, selected: rows, all?: all?)

    socket =
      if told?,
        do:
          push_event(socket, "ash_data_table:select", %{
            table: id,
            all: all?,
            rows: for(row <- rows, pk = key(model, row), do: as_kept(model, pk))
          }),
        else: socket

    if {all?, MapSet.new(rows)} != {all_before, MapSet.new(before)},
      do:
        Notify.told(
          socket,
          Event.selection(Enum.flat_map(rows, &List.wrap(key(model, &1))), all?)
        ),
      else: socket
  end

  # A selection is given up when what it was made under changes: the
  # filters, the arguments, and the record the table is limited to. Not the
  # sort, nor the page: a selection outlives its page.
  def scoped(socket) do
    %{state: state, related: related, choose: choose, selected_under: held} =
      entry = Core.table(socket).entry

    scope =
      if choose, do: :choose, else: {state.filters, state.arguments, related && related.param}

    socket = Core.put(socket, selected_under: scope)

    if not is_nil(held) and held != scope and (entry.all? or entry.selected != []),
      do: put(socket, {:rows, []}, true),
      else: socket
  end

  # A row that went, with the primary key `pk`, is selected no longer.
  def gone(socket, pk) do
    %{model: model, selected: selected} = Core.table(socket).entry

    case Enum.reject(selected, &(key(model, &1) == pk)) do
      ^selected -> socket
      rows -> put(socket, {:rows, rows}, true)
    end
  end

  @doc """
  The records that are selected, read again as the person through the
  table's read action with its arguments and what the page gives
  (`AshDataTable.selected_records/2`): those of the keys held, or with
  `all?` everything that matches, read in batches; scrubbed of sensitive
  values. `{:error, message}` where the read fails.
  """
  def records(socket) do
    %{model: model, selected: rows, all?: all?, state: state, parent_key: parent} =
      Core.table(socket).entry

    opts = Reading.read_opts(socket)

    keys =
      if all?,
        do: :all,
        else: rows |> Enum.map(&key(model, &1)) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    read =
      case {model.via, keys} do
        {nil, :all} -> {:ok, Query.records(model, Query.matching(model, state, opts), opts)}
        {nil, keys} -> {:ok, Query.records(model, keys, opts)}
        {_via, keys} -> Query.related_records(model, state, parent, keys, opts)
      end

    case read do
      {:ok, records} -> {:ok, Enum.map(records, &Sensitive.scrub(&1, model.columns))}
      {:error, error} -> {:error, failed(error, model)}
    end
  rescue
    error -> {:error, failed(error, Core.table(socket).entry.model)}
  end

  defp failed(error, model) do
    case Errors.of_read(error, model) do
      [] -> Text.say({:text, :read_failed, []})
      messages -> Text.say(Errors.joined(messages))
    end
  end

  @doc """
  A token of what is selected now: the rows (or every record that matches)
  and what they were selected under. The question before an action on the
  selection carries it, and Confirm sends it back: the action runs only on
  the selection the question named (`AshDataTable.Live.Core.Bulk`). It
  says nothing the page does not show: the rows are the page's own claims.
  """
  def token(%{selected: rows, all?: all?, selected_under: under}) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary({all?, Enum.sort(rows), under}))
    |> binary_part(0, 12)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Whether every row of the page is selected (or every record that
  matches): the line above the grid offers "all that match" then. A row
  is named as the hook names it (`select`), by what its `data-key` says,
  else by the key in its DOM id.
  """
  def whole_page?(%{all?: true}), do: true
  def whole_page?(%{rows: rows}) when map_size(rows) == 0, do: false

  def whole_page?(%{rows: rows, selected: selected, model: model}) do
    selected = MapSet.new(selected)

    Enum.all?(rows, fn {key, row} ->
      MapSet.member?(selected, Reading.names(model, row.pk, key) || key)
    end)
  end

  @doc """
  What is selected of the rows of the page, as the hook names them: in a
  table to choose one record from, the record a person can take.
  """
  def in_view(%{rows: rows, selected: selected, model: model}) do
    shown = MapSet.new(rows, fn {key, row} -> Reading.names(model, row.pk, key) || key end)
    Enum.filter(selected, &MapSet.member?(shown, &1))
  end

  @doc "A primary key as the hook names its row: what `select` sends for it."
  def named(model, pk) do
    row_key = Reading.row_key(model, pk, 0)
    Reading.names(model, pk, row_key) || row_key
  end

  # A row as the hook keeps it: the key in its DOM id, and what it names the
  # row by where that is not the key itself.
  defp as_kept(model, pk) do
    row_key = Reading.row_key(model, pk, 0)
    [row_key, Reading.names(model, pk, row_key)]
  end

  # What the hook names a row by, as a primary key; nil for anything else.
  defp key(model, named), do: Record.key(model.resource, named)
end
