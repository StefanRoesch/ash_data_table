defmodule DemoWeb.Tables.TaskArraysTest do
  @moduledoc """
  The array columns of the mounted table of `Demo.Tracker.Task` at `/tasks`,
  on Postgres: `tags`, an array of text with at most five values of two to
  twenty characters, edited value by value, and `checks`, an array of enum
  values, edited as multiple choice. Both are saved through `update`, which
  a member may run only on their own tasks and a viewer never.

  Everything else a table does with an array is in `array_table_test.exs`.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Task

  setup do
    world = world(tasks: 0, other_tasks: 0)
    [project | _] = world.projects

    task =
      Generator.generate(
        Generator.task(
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          title: "Write the report",
          tags: ["api", "mobile"],
          checks: [:tested, :reviewed],
          inserted_at: ~U[2026-01-02 12:00:00.000000Z]
        )
      )

    bare =
      Generator.generate(
        Generator.task(
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          title: "Nothing yet",
          tags: [],
          checks: [],
          inserted_at: ~U[2026-01-01 12:00:00.000000Z]
        )
      )

    %{world: world, project: project, task: task, bare: bare}
  end

  defp stored(task), do: Ash.get!(Task, task.id, authorize?: false)
  defp shown(html, task, field), do: text(html, cell(task.id, field))

  describe "the array columns" do
    setup %{conn: conn, world: world} do
      {:ok, view, html} = conn |> log_in(world.admin) |> live("/tasks")
      %{view: view, html: html}
    end

    test "show their values as text: tags as they are, checks by their labels, in the record's order",
         %{html: html, task: task, bare: bare} do
      assert shown(html, task, "tags") == "api, mobile"
      assert shown(html, task, "checks") == "Tested, Reviewed"
      assert shown(html, bare, "tags") == ""
      assert shown(html, bare, "checks") == ""
    end

    test "are edited in the side panel: a row per value, and a box per check", %{
      html: html,
      view: view,
      task: task
    } do
      assert editor(html, "task", "tags") == %{control: "panel", choices: nil, confirm: nil}
      assert editor(html, "task", "checks") == %{control: "panel", choices: nil, confirm: nil}

      assert %{fields: [%{name: "tags", control: "list", value: ["api", "mobile"]}]} =
               panel(edit(view, task.id, "tags"))

      cancel_panel(view)

      html = edit(view, task.id, "checks")

      assert %{fields: [%{name: "checks", control: "choices", value: ["reviewed", "tested"]}]} =
               panel(html)

      assert ["Reviewed", "Tested", "Documented", "Released"] ==
               html
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("#task-panel-f-checks > label")
               |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
    end

    test "have neither a sort nor a filter, on Postgres as anywhere", %{html: html} do
      for field <- ~w(tags checks) do
        assert attribute(html, "#task-head-#{field}", "data-sort") == []
        assert attribute(html, "#task-filter-#{field}", "data-filter") == []
      end
    end
  end

  # Edits the cell of `field` in the side panel, as the hook asks for it
  # (`edit`), and saves `values` there, as the panel's form sends them: one
  # entry of the field's own, then one per value.
  defp save_in_panel(view, task, field, values) do
    edit(view, task.id, field)
    send_panel(view, %{"panel" => %{field => ["" | values]}})
  end

  defp field(html, name), do: Enum.find(panel(html).fields, &(&1.name == name))

  describe "saving in the side panel" do
    setup %{conn: conn, world: world} do
      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")
      %{conn: conn, view: view}
    end

    test "of tags stores the values as typed, and the row shows them", %{
      conn: conn,
      view: view,
      task: task
    } do
      html = save_in_panel(view, task, "tags", ["api", "customer", "quick-win"])

      assert panel(html) == nil
      assert shown(html, task, "tags") == "api, customer, quick-win"
      assert stored(task).tags == ["api", "customer", "quick-win"]

      {:ok, _view, html} = live(conn, "/tasks")
      assert shown(html, task, "tags") == "api, customer, quick-win"
    end

    test "of checks stores the values that were ticked", %{conn: conn, view: view, bare: bare} do
      html = save_in_panel(view, bare, "checks", ["reviewed", "released"])

      assert shown(html, bare, "checks") == "Reviewed, Released"
      assert stored(bare).checks == [:reviewed, :released]

      {:ok, _view, html} = live(conn, "/tasks")
      assert shown(html, bare, "checks") == "Reviewed, Released"
    end

    test "of an array without values stores the empty array", %{view: view, task: task} do
      html = save_in_panel(view, task, "tags", [])
      assert shown(html, task, "tags") == ""

      html = save_in_panel(view, task, "checks", [])
      assert shown(html, task, "checks") == ""

      assert %{tags: [], checks: []} = stored(task)
    end

    test "of the values the task already has changes nothing: `updated_at` stays", %{
      view: view,
      task: task
    } do
      before = stored(task).updated_at

      assert panel(save_in_panel(view, task, "tags", ["api", "mobile"])) == nil
      assert panel(save_in_panel(view, task, "checks", ["tested", "reviewed"])) == nil

      assert stored(task).updated_at == before
    end

    test "that the action refuses stays open, keeps what was typed and shows the action's message",
         %{view: view, task: task} do
      # a tag has two characters at least
      html = save_in_panel(view, task, "tags", ["api", "x"])

      # the rows of the values are the panel's hook's (`phx-update="ignore"`),
      # which keeps what was typed
      assert field(html, "tags").errors == ["Tags 2: length must be greater than or equal to 2"]
      assert attribute(html, "#task-panel-f-tags-values", "phx-update") == ["ignore"]

      assert announcement(html) ==
               "Tags was not saved: Tags: Tags 2: length must be greater than or equal to 2"

      # the field says which value it was, for its rows to be marked
      assert attribute(html, "#task-panel-f-tags", "data-invalid") == ["[1]"]
      # the cell is as the record has it
      assert shown(html, task, "tags") == "api, mobile"
      assert failure(html, task.id, "tags") == nil

      # and a task has five tags at most
      html = send_panel(view, %{"panel" => %{"tags" => ["" | ~w(aa bb cc dd ee ff)]}})
      assert field(html, "tags").errors == ["must have 5 or fewer items"]
      cancel_panel(view)

      # a check that is none
      html = save_in_panel(view, task, "checks", ["tested", "approved"])
      assert field(html, "checks").errors == ["is invalid"]

      assert %{tags: ["api", "mobile"], checks: [:tested, :reviewed]} = stored(task)
    end

    test "keeps the row's calculations and reference cells", %{
      view: view,
      task: task,
      project: project
    } do
      html = save_in_panel(view, task, "tags", ["api"])

      assert shown(html, task, "project") == project.name
      assert shown(html, task, "headline") =~ "Write the report"
    end
  end

  describe "by a person who may not" do
    test "change this task is refused in the panel, for either array", %{
      conn: conn,
      world: world,
      task: task
    } do
      {:ok, view, html} = conn |> log_in(world.member) |> live("/tasks")

      # a member is offered editing on every task
      assert attribute(html, cell(task.id, "tags"), "tabindex") == ["0"]

      html = save_in_panel(view, task, "tags", ["mine"])
      assert panel(html).errors == ["You are not allowed to change this."]
      cancel_panel(view)

      html = save_in_panel(view, task, "checks", ["released"])
      assert panel(html).errors == ["You are not allowed to change this."]

      assert %{tags: ["api", "mobile"], checks: [:tested, :reviewed]} = stored(task)
    end

    test "change any task has no editor, and what is sent all the same saves nothing", %{
      conn: conn,
      world: world,
      task: task
    } do
      {:ok, view, html} = conn |> log_in(world.viewer) |> live("/tasks")

      assert editor(html, "task", "tags") == nil
      assert editor(html, "task", "checks") == nil
      assert shown(html, task, "tags") == "api, mobile"

      edit(view, task.id, "tags")
      assert_reply view, %{ok: false}
      assert panel(render(view)) == nil
      save(view, task.id, "tags", "theirs")
      assert stored(task).tags == ["api", "mobile"]
    end
  end

  describe "in German" do
    test "the values of an enum, the choices and what the panel's controls are called are translated",
         %{conn: conn, world: world, task: task} do
      {:ok, view, html} = conn |> log_in(world.admin) |> in_locale("de") |> live("/tasks")

      assert shown(html, task, "checks") == "Getestet, Durchgesehen"

      html = edit(view, task.id, "checks")

      assert ["Durchgesehen", "Getestet", "Dokumentiert", "Veröffentlicht"] ==
               html
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("#task-panel-f-checks > label")
               |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      cancel_panel(view)
      html = edit(view, task.id, "tags")

      # the list of the tags: its button, and the names its hook gives the
      # controls of the values it adds, with `{n}` where a value's place goes
      for {attribute, text} <- [
            {"data-value-label", "Schlagwörter {n}"},
            {"data-remove-label", "Schlagwörter {n} entfernen"}
          ] do
        assert html =~ ~s(#{attribute}="#{text}")
      end

      assert html =~ "Wert hinzufügen"
      assert text(html, "#task-panel-f-tags-label") == "Schlagwörter"
    end
  end

  describe "creating a task" do
    test "takes tags value by value and checks as multiple choice", %{
      conn: conn,
      world: world,
      project: project
    } do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      open_create(view)

      # what a browser sends for the field of an array: one entry of the
      # field's own, then one per value
      html =
        send_panel(view, %{
          "panel" => %{
            "title" => "Brand new",
            "project_id" => project.id,
            "tags" => ["", "fresh", "api"],
            "checks" => ["", "documented"]
          }
        })

      assert panel(html) == nil

      assert %{tags: ["fresh", "api"], checks: [:documented]} =
               Enum.find(Ash.read!(Task, authorize?: false), &(&1.title == "Brand new"))
    end

    test "shows what the action says about an array at its field", %{
      conn: conn,
      world: world,
      project: project
    } do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      open_create(view)

      html =
        send_panel(view, %{
          "panel" => %{
            "title" => "Brand new",
            "project_id" => project.id,
            "tags" => ["", "x"],
            "checks" => [""]
          }
        })

      assert Enum.find(panel(html).fields, &(&1.name == "tags")).errors ==
               ["Tags 1: length must be greater than or equal to 2"]

      refute Enum.any?(Ash.read!(Task, authorize?: false), &(&1.title == "Brand new"))
    end
  end
end
