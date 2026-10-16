defmodule AshDataTable.RegistryTest do
  @moduledoc """
  The tables one `AshDataTable.Table` shows (`AshDataTable.Live.Registry`,
  stage 5): which nested tables a table renders and which are closed
  (`Live.Core.Nesting.reconcile/1`), by their place and never by a prefix
  of their ids; the entry the live core works on (`within/3`); the stream
  names of the pool; the order of the portals.

  On a socket of its own, with entries made by hand: what a table renders
  is decided by its `open` lines and its `rows`, and an entry that its
  table around it told what it tells it now is not told again.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.Live.Core.Nesting
  alias AshDataTable.Live.Entry
  alias AshDataTable.Live.Registry
  alias AshDataTable.Model.Relationship
  alias AshDataTable.Table
  alias Phoenix.LiveView.Socket

  defp relationship(name),
    do:
      struct!(Relationship,
        name: name,
        label: "#{name}",
        kind: :has_many,
        cardinality: :many,
        source: __MODULE__,
        destination: __MODULE__,
        read_action: :read
      )

  # the table on the page, "t", with one row ("1"), and nothing open yet
  defp socket do
    # a socket as LiveView makes a component's: with its lifecycle, for streams
    socket = %Socket{
      assigns: %{__changed__: %{}, myself: 1},
      private: %{
        lifecycle: %Phoenix.LiveView.Lifecycle{},
        live_temp: %{},
        ash_data_table: %{current: :table}
      }
    }

    socket = Phoenix.Component.assign(socket, table: Table.new())
    {stream, socket} = Registry.take_stream(socket)

    top = %{
      socket.assigns.table.entry
      | id: "t",
        path: ["t"],
        stream: stream,
        expandable?: true,
        model: %{
          relationships: [relationship(:comments), relationship(:comments_archive)],
          columns: [],
          read_arguments: %{}
        },
        rows: %{"1" => %{pk: %{id: 1}, rowindex: 3}, "2" => %{pk: %{id: 2}, rowindex: 4}}
    }

    Phoenix.Component.assign(socket, table: %{socket.assigns.table | entry: top})
  end

  defp open(socket, lines) do
    top = %{socket.assigns.table.entry | open: lines}
    Phoenix.Component.assign(socket, table: %{socket.assigns.table | entry: top})
  end

  # opens, as `reconcile/1` would, each table the top renders, told what it
  # is told (`Core.told/2` reads; here only the entry is made)
  defp opened(socket) do
    Enum.reduce(Nesting.children(socket, "t"), socket, fn {id, given, target}, socket ->
      socket = Registry.add(socket, id, target)

      Registry.within(socket, id, fn socket ->
        entry = %{socket.assigns.table.entry | path: ["t", id], given: given}
        Phoenix.Component.assign(socket, table: %{socket.assigns.table | entry: entry})
      end)
    end)
  end

  defp ids(socket), do: socket.assigns.table.entries |> Map.keys() |> Enum.sort()

  test "a table renders the nested table of each open line of a row on its page, into that line's cell" do
    socket = socket() |> open(%{"1" => [:comments], "2" => [], "3" => [:comments]})

    assert [{"t-row-1-t-comments", given, "t-row-1-n-comments-c"}] = Nesting.children(socket, "t")
    assert %{id: "t-row-1-t-comments", parent_key: %{id: 1}, url: nil, mounted?: false} = given
    assert given.path == ["t"]
  end

  test "closing is by place: the sibling whose name the closed one's id begins is left open" do
    socket = socket() |> open(%{"1" => [:comments, :comments_archive]}) |> opened()
    assert ids(socket) == ["t-row-1-t-comments", "t-row-1-t-comments_archive"]
    %{"t-row-1-t-comments" => %{stream: closed}} = socket.assigns.table.entries

    socket = socket |> open(%{"1" => [:comments_archive]}) |> Nesting.reconcile()

    assert ids(socket) == ["t-row-1-t-comments_archive"]
    assert_targets(socket)
    # its stream is the pool's again
    assert closed in socket.assigns.table.pool.free
  end

  test "a row that is no longer on the page takes the tables under it away" do
    socket = socket() |> open(%{"1" => [:comments], "2" => [:comments]}) |> opened()
    top = %{socket.assigns.table.entry | rows: Map.delete(socket.assigns.table.entry.rows, "2")}
    socket = Phoenix.Component.assign(socket, table: %{socket.assigns.table | entry: top})

    socket = Nesting.reconcile(socket)
    assert ids(socket) == ["t-row-1-t-comments"]
    assert_targets(socket)
  end

  # Every open table's cell is the cell of an open line of a row its table
  # around it has on its page: a portal never outlives its target.
  defp assert_targets(socket) do
    %{entry: top, entries: entries} = socket.assigns.table

    for {_id, %{path: path, target: target}} <- entries do
      parent = if Enum.at(path, -2) == top.id, do: top, else: entries[Enum.at(path, -2)]

      assert Enum.any?(parent.open, fn {key, lines} ->
               is_map_key(parent.rows, key) and
                 Enum.any?(lines, &(target == "#{parent.id}-row-#{key}-n-#{&1}-c"))
             end)
    end
  end

  test "a stream name closed and opened in one callback is used again, by one table at a time" do
    socket = socket() |> open(%{"1" => [:comments]}) |> opened()
    %{"t-row-1-t-comments" => %{stream: name}} = socket.assigns.table.entries

    # closed and the other opened, before anything is rendered
    socket =
      socket
      |> open(%{})
      |> Nesting.reconcile()
      |> open(%{"2" => [:comments]})
      |> opened()

    assert %{"t-row-2-t-comments" => %{stream: ^name}} = socket.assigns.table.entries
    streams = [socket.assigns.table.entry | Map.values(socket.assigns.table.entries)]
    assert streams |> Enum.map(& &1.stream) |> Enum.uniq() |> length() == length(streams)
  end

  test "within/3 shows the entry to the core as the table, and puts the table on the page back" do
    socket = socket() |> open(%{"1" => [:comments]}) |> opened()

    {:reply, :seen, socket} =
      Registry.within(socket, "t-row-1-t-comments", fn socket ->
        # the entry, placed by the table it is in, with the top among the others
        assert %{entry: %{id: "t-row-1-t-comments"}, entries: %{"t" => _}} = socket.assigns.table
        assert %{url: nil, heading: false, mounted?: false} = socket.assigns.table.options
        {:reply, :seen, socket}
      end)

    assert %{entry: %{id: "t"}, entries: entries} = socket.assigns.table
    assert Map.keys(entries) == ["t-row-1-t-comments"]
  end

  test "the portals come parents first: LiveView moves them in the order of the page" do
    table = %Table{
      entries: %{
        "b" => %Entry{id: "b", path: ["t", "a", "b"], target: "x"},
        "a" => %Entry{id: "a", path: ["t", "a"], target: "y"},
        "c" => %Entry{id: "c", path: ["t", "c"], target: "z"},
        "p" => %Entry{id: "p", path: ["t", "p"], target: nil}
      }
    }

    assert table |> Registry.portals() |> Enum.map(& &1.id) == ["a", "c", "b"]
  end
end
