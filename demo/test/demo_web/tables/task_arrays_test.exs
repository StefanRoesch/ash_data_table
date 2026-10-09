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

    test "have their editors: a row per value, and a box per check", %{html: html} do
      assert editor(html, "task", "tags") == %{
               control: {"list", "textarea"},
               choices: nil,
               confirm: nil
             }

      assert editor(html, "task", "checks") == %{
               control: "choices",
               choices: ["Reviewed", "Tested", "Documented", "Released"],
               confirm: nil
             }
    end

    test "have neither a sort nor a filter, on Postgres as anywhere", %{html: html} do
      for field <- ~w(tags checks) do
        assert attribute(html, "#task-head-#{field}", "data-sort") == []
        assert attribute(html, "#task-filter-#{field}", "data-filter") == []
      end
    end
  end

  describe "saving" do
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
      html = save(view, task.id, "tags", ["api", "customer", "quick-win"])

      assert shown(html, task, "tags") == "api, customer, quick-win"
      assert failure(html, task.id, "tags") == nil
      assert stored(task).tags == ["api", "customer", "quick-win"]

      {:ok, _view, html} = live(conn, "/tasks")
      assert shown(html, task, "tags") == "api, customer, quick-win"
    end

    test "of checks stores the values that were ticked", %{conn: conn, view: view, bare: bare} do
      html = save(view, bare.id, "checks", ["reviewed", "released"])

      assert shown(html, bare, "checks") == "Reviewed, Released"
      assert stored(bare).checks == [:reviewed, :released]

      {:ok, _view, html} = live(conn, "/tasks")
      assert shown(html, bare, "checks") == "Reviewed, Released"
    end

    test "of an array without values stores the empty array", %{view: view, task: task} do
      html = save(view, task.id, "tags", [])
      assert shown(html, task, "tags") == ""

      html = save(view, task.id, "checks", [])
      assert shown(html, task, "checks") == ""

      assert %{tags: [], checks: []} = stored(task)
    end

    test "of the values the task already has changes nothing: `updated_at` stays", %{
      view: view,
      task: task
    } do
      before = stored(task).updated_at

      html = save(view, task.id, "tags", ["api", "mobile"])
      assert failure(html, task.id, "tags") == nil

      html = save(view, task.id, "checks", ["tested", "reviewed"])
      assert failure(html, task.id, "checks") == nil

      assert stored(task).updated_at == before
    end

    test "that the action refuses marks the cell, keeps what was typed and shows the action's message",
         %{view: view, task: task} do
      # a tag has two characters at least
      html = save(view, task.id, "tags", ["api", "x"])

      assert failure(html, task.id, "tags") == %{
               shown: "api, x",
               message: "Tags 2: length must be greater than or equal to 2"
             }

      assert announcement(html) ==
               "Tags was not saved: Tags 2: length must be greater than or equal to 2"

      # the cell says which value it was, for its editor to mark
      assert attribute(html, cell(task.id, "tags"), "data-invalid") == ["[1]"]

      # and a task has five tags at most
      html = save(view, task.id, "tags", ~w(aa bb cc dd ee ff))

      assert failure(html, task.id, "tags") == %{
               shown: "aa, bb, cc, dd, ee, ff",
               message: "must have 5 or fewer items"
             }

      # a check that is none
      html = save(view, task.id, "checks", ["tested", "approved"])

      assert failure(html, task.id, "checks") == %{
               shown: "Tested, approved",
               message: "is invalid"
             }

      assert %{tags: ["api", "mobile"], checks: [:tested, :reviewed]} = stored(task)
    end

    test "keeps the row's calculations and reference cells", %{
      view: view,
      task: task,
      project: project
    } do
      html = save(view, task.id, "tags", ["api"])

      assert shown(html, task, "project") == project.name
      assert shown(html, task, "headline") =~ "Write the report"
    end
  end

  describe "by a person who may not" do
    test "change this task is refused on the cell, for either array", %{
      conn: conn,
      world: world,
      task: task
    } do
      {:ok, view, html} = conn |> log_in(world.member) |> live("/tasks")

      # a member is offered editing on every task
      assert attribute(html, cell(task.id, "tags"), "aria-readonly") == []

      html = save(view, task.id, "tags", ["mine"])

      assert failure(html, task.id, "tags") == %{
               shown: "mine",
               message: "You are not allowed to change this."
             }

      html = save(view, task.id, "checks", ["released"])

      assert failure(html, task.id, "checks") == %{
               shown: "Released",
               message: "You are not allowed to change this."
             }

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

      save(view, task.id, "tags", ["theirs"])
      assert stored(task).tags == ["api", "mobile"]
    end
  end

  describe "in German" do
    test "the values of an enum, the choices and what the editor's controls are called are translated",
         %{conn: conn, world: world, task: task} do
      {:ok, view, html} = conn |> log_in(world.admin) |> in_locale("de") |> live("/tasks")

      assert shown(html, task, "checks") == "Getestet, Durchgesehen"

      assert editor(html, "task", "checks").choices ==
               ["Durchgesehen", "Getestet", "Dokumentiert", "Veröffentlicht"]

      # the list of the tags: its name, its button, and the names its hook
      # gives the controls, with `{n}` where a value's place goes
      for {attribute, text} <- [
            {"aria-label", "Schlagwörter"},
            {"data-value-label", "Schlagwörter {n}"},
            {"data-remove-label", "Schlagwörter {n} entfernen"}
          ] do
        assert html =~ ~s(#{attribute}="#{text}")
      end

      assert html =~ "Wert hinzufügen"

      # what was typed is shown with the labels of this language
      html = save(view, task.id, "checks", ["released", "approved"])
      assert failure(html, task.id, "checks").shown == "Veröffentlicht, approved"
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
