defmodule DemoWeb.Tables.LabelImportTest do
  @moduledoc """
  An argument that takes a file, in the mounted table of
  `Demo.Tracker.Label` at `/labels`: the table action "Import" makes a
  label of each line of a CSV file. Its panel has a file input, which is an
  upload of LiveView's; the action is given the file when "Run" is used,
  and reads it. On Postgres and in a tenant.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Label

  setup do
    world = world(tasks: 0, labels: 0)

    Generator.generate(
      Generator.label(organization_id: world.organization.id, name: "bug", colour: "#aa0000")
    )

    %{world: world}
  end

  defp stored do
    Label
    |> Ash.read!(authorize?: false)
    |> Enum.map(&{&1.name, &1.colour})
    |> Enum.sort()
  end

  defp field(html, name), do: Enum.find(panel(html, "label").fields, &(&1.name == name))

  # Chooses a file in the panel's file input, as a person does.
  defp choose(view, name, content, type \\ "text/csv") do
    file_input(view, "[id='label-panel-form']", "label-file-file", [
      %{name: name, content: content, type: type}
    ])
  end

  defp run(view), do: view |> element("[id='label-panel-form']") |> render_submit(%{})

  describe "the panel of an action with a file argument" do
    test "has a file input for it, marked as required, limited as the block says", %{
      conn: conn,
      world: world
    } do
      {:ok, view, html} = conn |> log_in(world.admin) |> live("/labels")

      assert "Import" in table_actions(html, "label")

      html = table_act(view, "label", "import")

      assert %{heading: "Import", submit: "Run"} = panel(html, "label")

      assert [%{name: "file", label: "File", control: "file", required?: true, errors: []}] =
               panel(html, "label").fields

      [input] =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#label-panel input[type=file]")
        |> Enum.to_list()

      assert LazyHTML.attribute(input, "accept") == [".csv"]
      assert LazyHTML.attribute(input, "multiple") == []
      # its label is for it
      [id] = LazyHTML.attribute(input, "id")
      assert attribute(html, "#label-panel label[for='#{id}']", "class") != []
    end

    test "is not there for a person who cannot run the action", %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.member) |> live("/labels")
      refute "Import" in table_actions(html, "label")
    end
  end

  describe "Run" do
    test "gives the action the file, which reads it: a label per line", %{
      conn: conn,
      world: world
    } do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/labels")
      table_act(view, "label", "import")

      file = choose(view, "labels.csv", "idea,#00aa00\nlater\n\n")
      assert render_upload(file, "labels.csv") =~ "label-panel"

      html = run(view)

      assert panel(html, "label") == nil
      assert result(html, "label") == "Import: 2"

      html = render_async(view)
      assert column(html, "label", "name") == ["bug", "idea", "later"]

      assert stored() == [{"bug", "#aa0000"}, {"idea", "#00aa00"}, {"later", "#64748b"}]
    end

    test "without a file says what the action says of an empty argument, at the field", %{
      conn: conn,
      world: world
    } do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/labels")
      table_act(view, "label", "import")

      html = run(view)

      assert %{errors: ["is required"]} = field(html, "file")
      assert announcement(html, "label") == "Import failed: File: is required"
      assert stored() == [{"bug", "#aa0000"}]
    end

    test "what the action says of the file is shown at the field, and the panel stays", %{
      conn: conn,
      world: world
    } do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/labels")
      table_act(view, "label", "import")

      file = choose(view, "labels.csv", "idea,#00aa00\nlater,red\n")
      render_upload(file, "labels.csv")

      html = run(view)

      assert %{errors: ["line 2: colour must match the pattern ~r/^#[0-9a-f]{6}$/"]} =
               field(html, "file")

      assert announcement(html, "label") =~ "Import failed: File: line 2: colour must match"
      # nothing of the file was made: the action runs in a transaction
      assert stored() == [{"bug", "#aa0000"}]

      # it is said until another file is chosen
      assert %{errors: ["line 2: colour must match" <> _]} = field(render(view), "file")

      file = choose(view, "better.csv", "idea,#00aa00\n")
      html = render_upload(file, "better.csv")
      assert field(html, "file").errors == []

      html = run(view)
      assert panel(html, "label") == nil
      assert result(html, "label") == "Import: 1"
    end

    test "a file is given once: \"Run\" again, without choosing one, runs without a file", %{
      conn: conn,
      world: world
    } do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/labels")
      table_act(view, "label", "import")

      file = choose(view, "labels.csv", "nope,red\n")
      render_upload(file, "labels.csv")

      assert %{errors: ["line 1: colour must match" <> _]} = field(run(view), "file")
      assert %{errors: ["is required"]} = field(run(view), "file")
      assert stored() == [{"bug", "#aa0000"}]
    end

    test "another file takes the place of the one that was chosen", %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/labels")
      table_act(view, "label", "import")

      choose(view, "first.csv", "nope,red\n") |> preflight_upload()

      file = choose(view, "better.csv", "idea,#00aa00\n")
      html = render_upload(file, "better.csv")
      assert field(html, "file").errors == []

      html = run(view)
      assert panel(html, "label") == nil
      assert result(html, "label") == "Import: 1"
      assert stored() == [{"bug", "#aa0000"}, {"idea", "#00aa00"}]
    end

    test "a file that is no text is refused by the action", %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/labels")
      table_act(view, "label", "import")

      file = choose(view, "labels.csv", <<0xFF, 0xFE, 0x00>>)
      render_upload(file, "labels.csv")

      assert %{errors: ["is not a text file"]} = field(run(view), "file")
    end

    test "a file that holds nothing is refused by the action", %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/labels")
      table_act(view, "label", "import")

      file = choose(view, "labels.csv", "\n \n")
      render_upload(file, "labels.csv")

      assert %{errors: ["is empty"]} = field(run(view), "file")
    end
  end

  describe "a file the upload does not take" do
    test "is refused as it is chosen: too large, said at the field and read out", %{
      conn: conn,
      world: world
    } do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/labels")
      table_act(view, "label", "import")

      file = choose(view, "labels.csv", String.duplicate("a,#000000\n", 12_000))
      assert {:error, [[_ref, :too_large]]} = render_upload(file, "labels.csv")

      # the form's change event, which a browser sends as the file is chosen
      html = view |> element("[id='label-panel-form']") |> render_change(%{})

      assert %{errors: ["The file is too large. The limit is 100 kB."]} = field(html, "file")
      assert announcement(html, "label") == "File: The file is too large. The limit is 100 kB."

      # and nothing runs
      html = run(view)
      assert panel(html, "label") != nil
      assert announcement(html, "label") == "File: The file is too large. The limit is 100 kB."
      assert stored() == [{"bug", "#aa0000"}]
    end

    test "of a kind the block does not accept", %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/labels")
      table_act(view, "label", "import")

      file = choose(view, "labels.txt", "idea\n", "text/plain")
      assert {:error, [[_ref, :not_accepted]]} = render_upload(file, "labels.txt")

      assert %{errors: ["This type of file is not accepted."]} = field(render(view), "file")
    end
  end

  describe "Cancel" do
    test "gives the file up: the next panel starts without one", %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/labels")
      table_act(view, "label", "import")

      file = choose(view, "labels.csv", "idea\n")
      render_upload(file, "labels.csv")

      html = cancel_panel(view, "label")
      assert panel(html, "label") == nil

      table_act(view, "label", "import")
      html = run(view)

      assert %{errors: ["is required"]} = field(html, "file")
      assert stored() == [{"bug", "#aa0000"}]
    end
  end

  describe "in a nested table" do
    test "the labels under a task have the action on their line, and its panel has the upload of the nested table",
         %{conn: conn, world: world} do
      [project | _] = world.projects

      task =
        Generator.generate(
          Generator.task(
            organization_id: world.organization.id,
            project_id: project.id,
            reporter_id: world.admin.id,
            title: "Write the report"
          )
        )

      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      expand(view, task.id)
      toggle(view, task.id, "labels")
      ran(view)

      nested = nested(task.id, "labels")
      html = table_act(view, nested, "import", on: "task-row-#{task.id}-l-labels-do-import")

      assert %{heading: "Import", fields: [%{name: "file", control: "file"}]} =
               panel(html, nested)

      # the upload of the panel, which a file input inside a portal is, is
      # used in the browser test "in a nested table" of `files.spec.ts`
    end
  end
end
