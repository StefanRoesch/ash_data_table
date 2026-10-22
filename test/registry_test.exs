defmodule AshDataTable.RegistryTest do
  @moduledoc """
  The tables one `AshDataTable.Table` shows (`AshDataTable.Live.Registry`,
  stage 5): which nested tables a table renders and which are closed
  (`Live.Core.Nesting.reconcile/1`), by their place and never by a prefix
  of their ids; the entry the live core works on (`within/3`); the stream
  names of the pool, and their effects; the order of the portals; and the
  files a run on the selection is handed (`owned/1`).

  Over the table, with no socket (stage 9g), with entries made by hand: what
  a table renders is decided by its `open` lines and its `rows`, and an
  entry that its table around it told what it tells it now is not told
  again. What LiveView would be told of the streams is among the effects
  the table gathers.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.Live.Core.Nesting
  alias AshDataTable.Live.Entry
  alias AshDataTable.Live.Registry
  alias AshDataTable.Model.Relationship
  alias AshDataTable.Table

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

  # the table on the page, "t", with two rows ("1", "2"), and nothing open yet
  defp table do
    {stream, table} = Registry.take_stream(Table.new())

    Table.put(table,
      id: "t",
      path: ["t"],
      stream: stream,
      expandable?: true,
      model: %{
        relationships: [relationship(:comments), relationship(:comments_archive)],
        columns: [],
        read_arguments: %{}
      },
      rows: %{"1" => %{pk: %{id: 1}, rowindex: 3}, "2" => %{pk: %{id: 2}, rowindex: 4}}
    )
  end

  defp open(table, lines), do: Table.put(table, open: lines)

  # opens, as `reconcile/1` would, each table the top renders, told what it
  # is told (`Core.Told.told/2` reads; here only the entry is made)
  defp opened(table) do
    Enum.reduce(Nesting.children(table, "t"), table, fn {id, given, target}, table ->
      table
      |> Registry.add(id, target)
      |> Registry.within(id, &Table.put(&1, path: ["t", id], given: given))
    end)
  end

  defp ids(table), do: table.entries |> Map.keys() |> Enum.sort()

  test "a table renders the nested table of each open line of a row on its page, into that line's cell and its heading onto the line" do
    table = open(table(), %{"1" => [:comments], "2" => [], "3" => [:comments]})

    assert [{"t-row-1-t-comments", given, {"t-row-1-n-comments-c", "t-row-1-l-comments-h"}}] =
             Nesting.children(table, "t")

    assert %{id: "t-row-1-t-comments", parent_key: %{id: 1}, url: nil, mounted?: false} = given
    assert given.path == ["t"]
  end

  test "closing is by place: the sibling whose name the closed one's id begins is left open" do
    table = table() |> open(%{"1" => [:comments, :comments_archive]}) |> opened()
    assert ids(table) == ["t-row-1-t-comments", "t-row-1-t-comments_archive"]
    %{"t-row-1-t-comments" => %{stream: closed}} = table.entries

    table = table |> open(%{"1" => [:comments_archive]}) |> Nesting.reconcile()

    assert ids(table) == ["t-row-1-t-comments_archive"]
    assert_targets(table)
    # its stream is the pool's again, emptied
    assert closed in table.pool.free
    assert {:stream, {:reset, closed, []}} == hd(table.effects)
  end

  test "a row that is no longer on the page takes the tables under it away" do
    table = table() |> open(%{"1" => [:comments], "2" => [:comments]}) |> opened()
    table = Table.put(table, rows: Map.delete(table.entry.rows, "2"))

    table = Nesting.reconcile(table)
    assert ids(table) == ["t-row-1-t-comments"]
    assert_targets(table)
  end

  # Every open table's cell is the cell of an open line of a row its table
  # around it has on its page: a portal never outlives its target.
  defp assert_targets(table) do
    %{entry: top, entries: entries} = table

    for {_id, %{path: path, target: target}} <- entries do
      parent = if Enum.at(path, -2) == top.id, do: top, else: entries[Enum.at(path, -2)]

      assert Enum.any?(parent.open, fn {key, lines} ->
               is_map_key(parent.rows, key) and
                 Enum.any?(lines, &(target == "#{parent.id}-row-#{key}-n-#{&1}-c"))
             end)
    end
  end

  test "a stream name closed and opened in one callback is used again, by one table at a time" do
    table = table() |> open(%{"1" => [:comments]}) |> opened()
    %{"t-row-1-t-comments" => %{stream: name}} = table.entries

    # closed and the other opened, before anything is rendered
    table =
      table
      |> open(%{})
      |> Nesting.reconcile()
      |> open(%{"2" => [:comments]})
      |> opened()

    assert %{"t-row-2-t-comments" => %{stream: ^name}} = table.entries
    streams = [table.entry | Map.values(table.entries)]
    assert streams |> Enum.map(& &1.stream) |> Enum.uniq() |> length() == length(streams)
  end

  test "a stream name is configured once, the first time it is taken, and emptied each time" do
    {name, table} = Registry.take_stream(Table.new())

    assert Enum.reverse(table.effects) == [
             {:stream, {:configure, name}},
             {:stream, {:reset, name, []}}
           ]

    table = %{Registry.give_back(table, name) | effects: []}
    {^name, table} = Registry.take_stream(table)
    assert table.effects == [{:stream, {:reset, name, []}}]
  end

  test "within/3 shows the entry to the core as the table, and puts the table on the page back" do
    table = table() |> open(%{"1" => [:comments]}) |> opened()

    {table, :seen} =
      Registry.within(table, "t-row-1-t-comments", fn table ->
        # the entry, placed by the table it is in, with the top among the others
        assert %{entry: %{id: "t-row-1-t-comments"}, entries: %{"t" => _}} = table
        assert %{url: nil, heading: false, mounted?: false} = table.options
        {table, :seen}
      end)

    assert %{entry: %{id: "t"}, entries: entries} = table
    assert Map.keys(entries) == ["t-row-1-t-comments"]
  end

  test "the portals come in the order the tables opened: parents first, a new one last" do
    [a, b, c, p] = for id <- ~w(a b c p), do: %{Entry.new() | id: id}

    table = %Table{
      entries: %{
        "b" => %{b | path: ["t", "a", "b"], target: "x"},
        "a" => %{a | path: ["t", "a"], target: "y"},
        "c" => %{c | path: ["t", "c"], target: "z"},
        "p" => %{p | path: ["t", "p"], target: nil}
      }
    }

    # a opened before b, the table it is in; c opened after both and comes
    # last, so that no portal before it moves
    assert table |> Registry.portals() |> Enum.map(& &1.id) == ["a", "b", "c"]
  end

  describe "a run's files (owned/1, #66)" do
    # a temporary file of the calling process, as `Files.copies/1` makes it
    defp file(text) do
      path = Plug.Upload.random_file!("ash_data_table")
      File.write!(path, text)
      path
    end

    # Plug.Upload deletes a process's files once it saw the process go
    defp gone?(path, tries \\ 50) do
      cond do
        not File.exists?(path) -> true
        tries == 0 -> false
        true -> Process.sleep(10) && gone?(path, tries - 1)
      end
    end

    test "are the run's once handed over: the page may go, and the work still reads them" do
      test = self()

      # a page that starts a run owning one of its two files, hands that one
      # over and goes; the run's work reads only once the test says so
      view =
        spawn(fn ->
          [given, kept] = Enum.map(~w(given kept), &file/1)

          {task, hand_over} =
            Registry.owned(fn ->
              receive do
                :read -> send(test, {:worked, File.read(given)})
              end
            end)

          {:ok, run} = Task.start(task)
          hand_over.([given])
          send(test, {:started, self(), run, kept})

          receive do
            :go -> :ok
          end
        end)

      assert_receive {:started, ^view, run, kept}
      watch = Process.monitor(view)
      send(view, :go)
      assert_receive {:DOWN, ^watch, :process, ^view, :normal}

      # the file the page kept went with it; the one it handed over did not
      assert gone?(kept)
      send(run, :read)
      assert_receive {:worked, {:ok, "given"}}
    end

    test "go with a page that goes before the hand-over, and the work never runs" do
      test = self()

      view =
        spawn(fn ->
          path = file("given")
          {task, _hand_over} = Registry.owned(fn -> send(test, :worked) end)
          {:ok, run} = Task.start(task)
          send(test, {:started, self(), run, path})

          receive do
            :go -> :ok
          end
        end)

      assert_receive {:started, ^view, run, path}
      watch = Process.monitor(run)
      send(view, :go)

      assert_receive {:DOWN, ^watch, :process, ^run, {:shutdown, {:page_gone, :normal}}}
      refute_received :worked
      assert gone?(path)
    end

    # the hand-over waits five seconds for the run to say who it is
    @tag timeout: 10_000
    test "a hand-over to a run that never started raises" do
      {_task, hand_over} = Registry.owned(fn -> :ok end)

      assert_raise RuntimeError, "ash_data_table: the run on the selection did not start", fn ->
        hand_over.([])
      end
    end
  end
end
