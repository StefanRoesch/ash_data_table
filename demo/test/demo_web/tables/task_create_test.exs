defmodule DemoWeb.Tables.TaskCreateTest do
  @moduledoc """
  Row create in the mounted table of `Demo.Tracker.Task` at `/tasks`: the
  create button on the line of the table's name, the action panel with the
  create action's inputs, and the new row at the top of the page.
  """
  use DemoWeb.ModeCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Task

  defp task(world, day, overrides) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          assignee_id: nil,
          title: "Task #{day}",
          status: :in_progress,
          progress: 40,
          inserted_at: DateTime.add(~U[2026-01-01 12:00:00.000000Z], day, :day)
        ] ++ overrides
      )
    )
  end

  defp titles(html), do: column(html, "task", "title")

  # every task of the organization, whoever may see it
  defp stored(world) do
    Task
    |> Ash.read!(authorize?: false, tenant: world.organization.id)
    |> Enum.sort_by(& &1.title)
  end

  setup do
    world = world(tasks: 0)
    %{world: world, old: task(world, 2, title: "Older"), oldest: task(world, 1, title: "Oldest")}
  end

  describe "the create button" do
    test "stands on the line of the table's name, at its other end, named after the resource",
         %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.admin) |> live("/tasks")

      assert text(html, "#task-header > h1") == "Tasks"
      assert text(html, "#task-header > div > button#task-create") == "New task"
      assert attribute(html, "#task-header > :first-child", "id") == ["task-name"]
      assert attribute(html, "#task-create", "type") == ["button"]
    end

    test "is there for a person who may ever create, and for nobody else", %{
      conn: conn,
      world: world
    } do
      {:ok, _view, html} = conn |> log_in(world.member) |> live("/tasks")
      assert text(html, "#task-create") == "New task"

      for actor <- [world.viewer, nil] do
        {:ok, _view, html} = conn |> log_in(actor) |> live("/tasks")
        assert text(html, "#task-create") == nil
        # the name is on its line all the same
        assert text(html, "#task-header > h1") == "Tasks"
      end
    end

    test "opens the action panel with the create action's inputs, and creates nothing yet",
         %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      html = open_create(view)

      assert %{heading: "New task", submit: "Create", errors: []} = panel(html)

      assert Enum.map(
               panel(html).fields,
               &{&1.name, &1.label, &1.control, &1.value, &1.required?}
             ) ==
               [
                 {"title", "Title", "textarea", "", true},
                 {"description", "Description", "textarea", "", false},
                 # labelled as its column is, and starting with the attribute's default
                 {"status", "State", "select", "todo", true},
                 {"priority", "Priority", "select", "medium", true},
                 # the slider of the column's component
                 {"progress", "Progress", "range", "0", true},
                 {"estimate_hours", "Estimate hours", "number", "", false},
                 # a box is never empty, so it is never marked as required
                 {"billable?", "Billable?", "checkbox", "false", false},
                 {"due_on", "Due on", "date", "", false},
                 {"external_ref", "External ref", "textarea", "", false},
                 # keys: plain fields until there is a picker
                 # the keys of related records, chosen in the picker
                 {"project_id", "Project", "reference", "", true},
                 {"assignee_id", "Assignee", "reference", "", false},
                 # arrays: value by value, and multiple choice. Both start
                 # with the attribute's default, which is no values
                 {"tags", "Tags", "list", [], false},
                 {"checks", "Checks", "choices", [], false},
                 # a map that declares its fields: a group, not there until it is added
                 {"recurrence", "Repeats", "group", false, false}
               ]

      assert length(stored(world)) == 2
    end

    test "leaves out the field of an attribute the person can never see", %{
      conn: conn,
      world: world
    } do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      names = Enum.map(panel(open_create(view)).fields, & &1.name)

      # `external_ref` is an admin's; `estimate_hours` is seen on a person's own tasks
      refute "external_ref" in names
      assert "estimate_hours" in names
    end
  end

  describe "creating a record" do
    setup %{conn: conn, world: world} do
      conn = log_in(conn, world.member)
      {:ok, view, html} = live(conn, "/tasks")
      open_create(view)
      %{conn: conn, view: view, before: html, project: hd(world.projects)}
    end

    test "runs the create action with what the person gave, as that person and in their organization",
         %{view: view, world: world, project: project} do
      html =
        run_panel(view,
          title: "Brand new",
          description: "Fresh from the panel",
          priority: "urgent",
          progress: "5",
          billable?: "true",
          due_on: "2026-12-24",
          project_id: project.id
        )

      assert panel(html) == nil
      assert announcement(html) == "Task created"

      assert [new, %{title: "Older"}, %{title: "Oldest"}] = stored(world)

      assert %{
               title: "Brand new",
               description: "Fresh from the panel",
               # the default of the attribute, as the field showed it
               status: :todo,
               priority: :urgent,
               progress: 5,
               billable?: true,
               due_on: ~D[2026-12-24]
             } = new

      assert new.project_id == project.id
      # the tenant is the person's, and so is the reporter: the action says so
      assert new.organization_id == world.organization.id
      assert new.reporter_id == world.member.id
    end

    test "shows the new record as the first row of the page, a row like the others",
         %{view: view, world: world, project: project, before: before} do
      assert titles(before) == ["Older", "Oldest"]
      assert text(before, "#task-range") == "1–2 of 2"

      html = run_panel(view, title: "Brand new", project_id: project.id)
      [new | _] = stored(world)

      assert titles(html) == ["Brand new", "Older", "Oldest"]
      assert attribute(html, "#task-table > tbody:first-of-type", "id") == ["task-row-#{new.id}"]

      # with everything its columns show, and its actions
      assert text(html, cell(new.id, "status")) == "To do"
      assert text(html, cell(new.id, "comment_count")) == "0"
      assert text(html, cell(new.id, "headline")) == "Medium: Brand new (0%)"
      assert text(html, cell(new.id, "project")) == project.name
      assert text(html, cell(new.id, "reporter")) == world.member.name

      assert actions(html, new.id) == [
               "Archive",
               "Reassign",
               "Set progress",
               "Destroy",
               "Set labels"
             ]

      # counted in: one row more on the page, one record more in all
      assert text(html, "#task-range") == "1–3 of 3"
      # with the two header rows and the footer row of the summaries
      assert attribute(html, "#task-table", "aria-rowcount") == ["6"]
      assert attribute(html, "[id='task-row-#{new.id}-r']", "aria-rowindex") == ["3"]
    end

    test "leaves a row that can be edited, expanded and acted on where it is",
         %{view: view, world: world, project: project, old: old} do
      run_panel(view, title: "Brand new", project_id: project.id)
      [new | _] = stored(world)

      html = save(view, new.id, "title", "Renamed")
      assert titles(html) == ["Renamed", "Older", "Oldest"]

      # the rows after it have moved down by one
      Ash.update!(old, %{assignee_id: world.member.id}, action: :update, authorize?: false)
      html = save(view, old.id, "title", "Older, renamed")
      assert attribute(html, "[id='task-row-#{old.id}-r']", "aria-rowindex") == ["4"]
      assert titles(html) == ["Renamed", "Older, renamed", "Oldest"]

      expand(view, new.id)
      html = toggle(view, new.id, "comments")
      assert text(html, "[id='#{nested(new.id, "comments")}-empty']") == "No records"

      html = act(view, new.id, "archive")
      assert text(html, cell(new.id, "status")) == "Archived"
      assert titles(html) == ["Renamed", "Older, renamed", "Oldest"]
    end

    test "stays at the top until the table reads again, which puts it where it belongs",
         %{view: view, project: project} do
      html = run_panel(view, title: "Zebra crossing", project_id: project.id)
      assert titles(html) == ["Zebra crossing", "Older", "Oldest"]

      view |> element("#task-head-title") |> render_click()
      html = render_async(view)

      assert titles(html) == ["Older", "Oldest", "Zebra crossing"]
      assert text(html, "#task-range") == "1–3 of 3"
    end

    test "that the action refuses stays open with the errors at their fields, and creates nothing",
         %{view: view, world: world, project: project} do
      html = run_panel(view, title: "No", project_id: "")

      assert %{heading: "New task", errors: []} = panel(html)

      assert [%{name: "title", value: "No", errors: [title_error]} | _] = panel(html).fields
      assert title_error == "length must be greater than or equal to 3"

      assert Enum.find(panel(html).fields, &(&1.name == "project_id")).errors == ["is required"]
      assert attribute(html, "#task-panel-f-title", "aria-invalid") == ["true"]
      assert length(stored(world)) == 2
      assert titles(html) == ["Older", "Oldest"]

      # put right, it runs
      html = run_panel(view, title: "Now it fits", project_id: project.id)
      assert panel(html) == nil
      assert titles(html) == ["Now it fits", "Older", "Oldest"]
    end

    test "is given up with Cancel", %{view: view, world: world} do
      type_in_panel(view, title: "Never mind")

      html = cancel_panel(view)

      assert panel(html) == nil
      assert length(stored(world)) == 2
      # opened again, the panel is empty
      assert hd(panel(open_create(view)).fields).value == ""
    end
  end

  describe "a create sent by hand" do
    test "by a person who may never create opens nothing and creates nothing", %{
      conn: conn,
      world: world
    } do
      {:ok, view, _html} = conn |> log_in(world.viewer) |> live("/tasks")
      assert panel(forge(view, "task", "create", %{})) == nil

      html =
        forge(view, "task", "panel_submit", %{
          "panel" => %{"title" => "Smuggled in", "project_id" => hd(world.projects).id}
        })

      assert panel(html) == nil
      assert length(stored(world)) == 2
    end

    test "cannot put the record into another organization, or give it what the action does not take",
         %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")
      open_create(view)

      send_panel(view, %{
        "panel" => %{
          "title" => "By hand",
          "project_id" => hd(world.projects).id,
          "organization_id" => world.other_organization.id,
          "reporter_id" => world.admin.id,
          "internal_note" => "smuggled",
          "completed_at" => "2026-01-01T00:00:00",
          # an attribute the action accepts, and this person never sees
          "external_ref" => "EXT-STOLEN"
        }
      })

      assert [new, _older, _oldest] = stored(world)

      assert %{title: "By hand", internal_note: nil, completed_at: nil, external_ref: nil} = new
      assert new.organization_id == world.organization.id
      assert new.reporter_id == world.member.id
    end
  end
end
