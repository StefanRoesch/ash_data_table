defmodule DemoWeb.Tables.FileActionsTest do
  @moduledoc """
  What a table does with an argument that takes a file, where the demo's
  own tables do not have the case: on a table that exists for the tests
  (`Demo.Support.Files.Scan` in `test/support/file_tables.ex`), mounted at
  `/support/scans`; its records are kept in memory.

  A file among the inputs of a row action, of a generic action in a row, of
  a table action, of the create action and of an action on the selected
  rows; two files in one action; a file that can be left out; what the
  upload is limited to; and what becomes of the file afterwards.

  A file is chosen and sent as LiveView's test client does it
  (`file_input/4`, `render_upload/3`), and the panel's button is the form's
  submit event. The demo's own, on Postgres, is in `label_import_test.exs`.
  """
  use DemoWeb.ModeCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Files.Scan

  setup do
    on_exit(fn -> Demo.Support.Ets.stop(Scan) end)
  end

  defp scan(title \\ "Page 1"), do: Ash.Seed.seed!(Scan, %{title: title})
  defp stored(scan), do: Ash.get!(Scan, scan.id, authorize?: false)
  defp shown(html, scan, field), do: text(html, cell("scan", scan.id, field))
  defp field(html, name), do: Enum.find(panel(html, "scan").fields, &(&1.name == name))

  # Chooses a file in the field of the argument `name`, and sends it, as
  # LiveView's client does when the panel's button is used.
  defp upload(view, name, file, content, type \\ "text/plain") do
    input =
      file_input(view, "[id='scan-panel-form']", "scan-file-#{name}", [
        %{name: file, content: content, type: type}
      ])

    render_upload(input, file)
  end

  defp run(view, values \\ %{}),
    do: view |> element("[id='scan-panel-form']") |> render_submit(%{"panel" => values})

  defp file_inputs(html) do
    for input <-
          html |> LazyHTML.from_fragment() |> LazyHTML.query("#scan-panel input[type=file]") do
      {List.first(LazyHTML.attribute(input, "name")),
       List.first(LazyHTML.attribute(input, "accept"))}
    end
  end

  # LiveView takes the file away when the process that received it is gone.
  defp gone?(path, tries \\ 50) do
    cond do
      not File.exists?(path) -> true
      tries == 0 -> false
      true -> Process.sleep(10) && gone?(path, tries - 1)
    end
  end

  describe "a file among the inputs of a row action" do
    setup %{conn: conn} do
      scan = scan()
      {:ok, view, _html} = live(conn, "/support/scans")
      %{scan: scan, view: view}
    end

    test "has a file input in the panel, beside the fields of the other inputs", %{
      view: view,
      scan: scan
    } do
      html = act(view, "scan", scan.id, "attach")
      assert_reply view, %{ok: true, panel: true}

      assert Enum.map(panel(html, "scan").fields, &{&1.name, &1.label, &1.control, &1.required?}) ==
               [
                 {"title", "Title", "textarea", true},
                 {"file", "File", "file", true}
               ]

      # limited as the block says
      assert file_inputs(html) == [{"scan-file-file", ".txt,text/plain"}]
    end

    test "the action is given the file when \"Run\" is used: its content, the name the browser gave, and its type",
         %{
           view: view,
           scan: scan
         } do
      act(view, "scan", scan.id, "attach")
      upload(view, "file", "notes.txt", "hello")

      html = run(view, %{"title" => "Page 1"})

      assert panel(html, "scan") == nil
      assert shown(html, scan, "content") == "hello"
      assert shown(html, scan, "file_name") == "notes.txt"
      assert shown(html, scan, "file_type") == "text/plain"
      assert shown(html, scan, "size") == "5"
      assert announcement(html, "scan") == "Attach: done"
    end

    test "the file is LiveView's, and gone when the action is done", %{view: view, scan: scan} do
      act(view, "scan", scan.id, "attach")
      upload(view, "file", "notes.txt", "hello")
      run(view, %{"title" => "Page 1"})

      path = stored(scan).path
      assert is_binary(path)
      assert gone?(path)
    end

    test "the name is a name: what the browser says of a way to it is left out", %{
      view: view,
      scan: scan
    } do
      act(view, "scan", scan.id, "attach")
      upload(view, "file", "../../etc/notes.txt", "hello")
      run(view, %{"title" => "Page 1"})

      assert stored(scan).file_name == "notes.txt"
    end

    test "what the action says of the file is shown at its field", %{view: view, scan: scan} do
      act(view, "scan", scan.id, "attach")
      upload(view, "file", "notes.txt", "refuse me")

      html = run(view, %{"title" => "Page 1"})

      assert %{errors: ["holds what nobody wants"]} = field(html, "file")
      assert field(html, "title").errors == []
      assert announcement(html, "scan") == "Attach failed: File: holds what nobody wants"
      assert stored(scan).content == nil
    end

    test "what it says of another field is shown there; the file was given, and is asked for again",
         %{
           view: view,
           scan: scan
         } do
      act(view, "scan", scan.id, "attach")
      upload(view, "file", "notes.txt", "hello")

      html = run(view, %{"title" => "x"})

      assert %{errors: ["length must be greater than or equal to 2"]} = field(html, "title")
      assert field(html, "file").errors == []
      assert stored(scan).content == nil

      # "Run" again, with the title put right and no file chosen
      html = run(view, %{"title" => "Page one"})
      assert %{errors: ["is required"]} = field(html, "file")
      assert field(html, "title").errors == []

      upload(view, "file", "notes.txt", "hello")
      html = run(view, %{"title" => "Page one"})
      assert panel(html, "scan") == nil
      assert shown(html, scan, "title") == "Page one"
      assert shown(html, scan, "content") == "hello"
    end

    test "typing into another field says nothing of the file, chosen or not", %{
      view: view,
      scan: scan
    } do
      act(view, "scan", scan.id, "attach")

      html = type_in_panel(view, "scan", title: "Page one")
      assert field(html, "file").errors == []

      file_input(view, "[id='scan-panel-form']", "scan-file-file", [
        %{name: "notes.txt", content: "hello", type: "text/plain"}
      ])
      |> preflight_upload()

      html = type_in_panel(view, "scan", title: "x")
      assert field(html, "file").errors == []
      assert %{errors: ["length must be greater than or equal to 2"]} = field(html, "title")
    end

    test "a form that comes without its file having been sent runs nothing", %{
      view: view,
      scan: scan
    } do
      act(view, "scan", scan.id, "attach")

      # chosen, and not sent: LiveView's client sends the file before the form
      file_input(view, "[id='scan-panel-form']", "scan-file-file", [
        %{name: "notes.txt", content: "hello", type: "text/plain"}
      ])
      |> preflight_upload()

      html = run(view, %{"title" => "Page 1"})

      assert panel(html, "scan") != nil
      assert announcement(html, "scan") == "The file could not be uploaded."
      assert stored(scan).content == nil
    end

    test "a file is never taken from what the form sends", %{view: view, scan: scan} do
      act(view, "scan", scan.id, "attach")

      html = run(view, %{"title" => "Page 1", "file" => "/etc/hostname"})

      assert %{errors: ["is required"]} = field(html, "file")
      assert stored(scan).content == nil
    end

    test "a file the upload does not take is refused before anything runs: of another kind, or too large",
         %{
           view: view,
           scan: scan
         } do
      act(view, "scan", scan.id, "attach")

      assert {:error, [[_ref, :not_accepted]]} =
               upload(view, "file", "notes.csv", "a,b", "text/csv")

      assert %{errors: ["This type of file is not accepted."]} = field(render(view), "file")

      html = run(view, %{"title" => "Page 1"})
      assert panel(html, "scan") != nil
      assert announcement(html, "scan") == "File: This type of file is not accepted."

      assert {:error, [[_ref, :too_large]]} =
               upload(view, "file", "long.txt", String.duplicate("a", 1_001))

      assert %{errors: ["The file is too large. The limit is 1 kB."]} =
               field(render(view), "file")

      assert stored(scan).content == nil
    end

    test "Cancel gives a chosen file up, and so does a new read of the table", %{
      view: view,
      scan: scan
    } do
      act(view, "scan", scan.id, "attach")
      upload(view, "file", "notes.txt", "hello")
      assert panel(cancel_panel(view, "scan"), "scan") == nil

      act(view, "scan", scan.id, "attach")
      assert %{errors: ["is required"]} = field(run(view, %{"title" => "Page 1"}), "file")
      cancel_panel(view, "scan")

      # the rows are read again while a file is chosen: the panel goes
      act(view, "scan", scan.id, "attach")
      upload(view, "file", "notes.txt", "hello")
      view |> element("#scan-sort-title") |> render_click()
      html = render_async(view)
      assert panel(html, "scan") == nil

      act(view, "scan", scan.id, "attach")
      upload(view, "file", "again.txt", "second")
      html = run(view, %{"title" => "Page 1"})
      assert shown(html, scan, "content") == "second"
    end
  end

  describe "two files in one action" do
    setup %{conn: conn} do
      scan = scan()
      {:ok, view, _html} = live(conn, "/support/scans")
      %{scan: scan, view: view}
    end

    test "each has its own field, within LiveView's own limits: any kind of file", %{
      view: view,
      scan: scan
    } do
      html = act(view, "scan", scan.id, "pair")

      assert Enum.map(panel(html, "scan").fields, &{&1.name, &1.control, &1.required?}) == [
               {"front", "file", true},
               {"rear", "file", false}
             ]

      assert file_inputs(html) == [{"scan-file-front", nil}, {"scan-file-rear", nil}]
    end

    test "the action is given both, each as its own argument", %{view: view, scan: scan} do
      act(view, "scan", scan.id, "pair")
      upload(view, "front", "front.bin", "recto", "application/octet-stream")
      upload(view, "rear", "rear.bin", "verso", "application/octet-stream")

      html = run(view)

      assert panel(html, "scan") == nil
      assert shown(html, scan, "content") == "recto"
      assert shown(html, scan, "back") == "verso"
    end

    test "one that can be left out is left out", %{view: view, scan: scan} do
      act(view, "scan", scan.id, "pair")
      upload(view, "front", "front.bin", "recto", "application/octet-stream")

      html = run(view)

      assert panel(html, "scan") == nil
      assert shown(html, scan, "content") == "recto"
      assert shown(html, scan, "back") == ""
    end
  end

  describe "an action whose only input is a file that can be left out" do
    test "opens its panel all the same: a file has no default to run with", %{conn: conn} do
      scan = scan()
      {:ok, view, _html} = live(conn, "/support/scans")

      html = act(view, "scan", scan.id, "annotate")
      assert [%{name: "note", control: "file", required?: false}] = panel(html, "scan").fields

      # without a file it runs, and changes nothing
      html = run(view)
      assert panel(html, "scan") == nil
      assert shown(html, scan, "content") == ""

      act(view, "scan", scan.id, "annotate")
      upload(view, "note", "note.md", "noted", "text/markdown")
      assert shown(run(view), scan, "content") == "noted"
    end
  end

  describe "a file for a generic action" do
    test "in a row: the action is given the row's key and the file, and the table says what it returned",
         %{conn: conn} do
      scan = scan()
      {:ok, view, _html} = live(conn, "/support/scans")

      html = act(view, "scan", scan.id, "measure")

      assert [%{name: "against", label: "Against", control: "file", required?: true}] =
               panel(html, "scan").fields

      upload(view, "against", "ruler.txt", "12345")
      html = run(view)

      assert panel(html, "scan") == nil
      assert result(html, "scan") == "Measure: 5"
    end

    test "on the table: beside its other arguments", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/support/scans")

      html = table_act(view, "scan", "ingest")

      assert Enum.map(panel(html, "scan").fields, &{&1.name, &1.control}) == [
               {"file", "file"},
               {"prefix", "textarea"}
             ]

      upload(view, "file", "pages.txt", "one\ntwo\n")
      html = run(view, %{"prefix" => "Page-"})

      assert panel(html, "scan") == nil
      assert result(html, "scan") == "Ingest: 2"
      assert Enum.sort(column(render_async(view), "scan", "title")) == ["Page-one", "Page-two"]
    end
  end

  describe "a file for the create action" do
    test "is given with the new record's other inputs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/support/scans")

      html = open_create(view, "scan")

      assert Enum.map(panel(html, "scan").fields, &{&1.name, &1.control, &1.required?}) == [
               {"title", "textarea", true},
               {"file", "file", false}
             ]

      upload(view, "file", "new.txt", "fresh")
      html = run(view, %{"title" => "Page 9"})

      assert panel(html, "scan") == nil
      assert [scan] = Ash.read!(Scan, authorize?: false)
      assert %{title: "Page 9", content: "fresh", file_name: "new.txt"} = scan
      assert shown(html, scan, "content") == "fresh"
    end
  end

  describe "a file for an action on the selected rows" do
    test "is given to every record: the run has a copy of it, which is gone when it is done", %{
      conn: conn
    } do
      first = scan("Page 1")
      second = scan("Page 2")
      {:ok, view, _html} = live(conn, "/support/scans")

      html = bulk(view, "scan", "attach", [first.id, second.id])
      assert_reply view, %{panel: true}
      assert %{heading: "Attach: 2 records"} = panel(html, "scan")
      assert %{control: "file", required?: true} = field(html, "file")

      upload(view, "file", "both.txt", "shared")
      run(view, %{"title" => "Both"})
      html = ran(view)

      assert bulk_result(html, "scan") == %{summary: "Attach: 2 done.", failures: []}

      paths =
        for scan <- [first, second] do
          assert %{title: "Both", content: "shared", file_name: "both.txt", path: path} =
                   stored(scan)

          path
        end

      # one copy for the run, the run's process's: gone when its process is
      assert [path] = Enum.uniq(paths)
      assert gone?(path)
    end

    test "what the action makes of the panel's values as such is shown first, and nothing runs",
         %{conn: conn} do
      first = scan("Page 1")
      {:ok, view, _html} = live(conn, "/support/scans")
      bulk(view, "scan", "attach", [first.id])

      upload(view, "file", "both.txt", "shared")
      html = run(view, %{"title" => "x"})

      assert %{errors: ["length must be greater than or equal to 2"]} = field(html, "title")
      assert stored(first).content == nil
    end

    test "a generic action in a row runs once per record, each with the file", %{conn: conn} do
      first = scan("Page 1")
      second = scan("Page 2")
      {:ok, view, _html} = live(conn, "/support/scans")

      bulk(view, "scan", "measure", [first.id, second.id])
      upload(view, "against", "ruler.txt", "12345")
      run(view)

      assert bulk_result(ran(view), "scan") == %{summary: "Measure: 2 done.", failures: []}
    end
  end
end
