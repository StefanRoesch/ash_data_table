defmodule DemoWeb.Tables.PickerPanelTest do
  @moduledoc """
  The picker in the action panel, as a person meets it at `/tasks`: an input
  that is the key of a related record ("Assignee" of "Reassign", "Project"
  and "Assignee" of "New task") says what the record is called and has a
  button that opens the picker, on top of the panel. The key goes into the
  panel's form; nothing runs until the panel's own button is used.

  A key is all the form sends, and a key from the browser is a claim: what
  a hand-made form can and cannot do is tested here too.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Task

  @moment ~U[2026-01-01 12:00:00.000000Z]

  defp task(world, title, overrides \\ []) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          assignee_id: nil,
          title: title,
          status: :in_progress,
          progress: 40,
          internal_note: nil,
          inserted_at:
            DateTime.add(@moment, System.unique_integer([:positive, :monotonic]), :millisecond)
        ] ++ overrides
      )
    )
  end

  defp person(world, name) do
    Generator.generate(Generator.user(organization_id: world.organization.id, name: name))
  end

  defp stored!(task), do: Ash.get!(Task, task.id, authorize?: false)
  defp field(html, name), do: Enum.find(panel(html).fields, &(&1.name == name))

  defp tasks_of(world) do
    Task
    |> Ash.read!(authorize?: false, tenant: world.organization.id)
    |> Enum.map(&{&1.title, &1.project_id, &1.assignee_id})
    |> Enum.sort()
  end

  defp titles_of(world), do: Enum.map(tasks_of(world), &elem(&1, 0))

  @people "task-pick-assignee_id"
  @projects "task-pick-project_id"

  describe "the field of a key, in the panel of a row action" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      ada = person(world, "Ada Lovelace")
      grace = person(world, "Grace Hopper")
      task = task(world, "Write the report", assignee_id: ada.id)
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      %{world: world, ada: ada, grace: grace, task: task, view: view}
    end

    test "holds the key, says what the record is called, and has a button that opens the picker",
         %{view: view, task: task, ada: ada} do
      html = act(view, task.id, "reassign")

      assert field(html, "assignee_id") == %{
               name: "assignee_id",
               label: "Assignee",
               control: "reference",
               value: ada.id,
               chosen: "Ada Lovelace",
               required?: false,
               errors: []
             }

      # the label names the group of the text and the button
      assert attribute(html, "#task-panel-f-assignee_id", "role") == ["group"]

      assert attribute(html, "#task-panel-f-assignee_id", "aria-labelledby") ==
               ["task-panel-f-assignee_id-label"]

      assert text(html, "#task-panel-f-assignee_id-choose") == "Choose"

      assert attribute(html, "#task-panel-f-assignee_id-choose", "aria-describedby") ==
               ["task-panel-f-assignee_id-chosen"]

      # the picker is not there until the button is used
      assert picker(html) == nil
      refute html =~ "task-pick-"
    end

    test "is empty where the record has no related record, or one this person may not read",
         %{conn: conn, world: world} do
      free = task(world, "Assigned to nobody", reporter_id: world.member.id)

      abroad =
        task(world, "Assigned abroad",
          reporter_id: world.member.id,
          assignee_id: world.outsider.id
        )

      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      assert %{value: "", chosen: nil} = field(act(view, free.id, "reassign"), "assignee_id")
      cancel_panel(view)

      # the key is held all the same: nothing changes unless they choose
      html = act(view, abroad.id, "reassign")
      assert %{value: value, chosen: nil} = field(html, "assignee_id")
      assert value == world.outsider.id
      refute html =~ world.outsider.name
    end

    test "opens the picker on top of the panel, on the record the field holds", %{
      view: view,
      task: task,
      ada: ada
    } do
      act(view, task.id, "reassign")
      html = pick_input(view, "assignee_id")

      assert %{
               heading: "Assignee: choose user",
               table: @people,
               buttons: ["Cancel", "None", "Choose"],
               question: nil
             } = picker(html)

      assert current(html, @people) == [ada.id]
      # the panel is still there, under it
      assert panel(html).heading == "Reassign: Write the report"
    end

    test "a choice puts the key into the field, with what the record is called, and leaves what else was typed",
         %{view: view, task: task, grace: grace, ada: ada} do
      act(view, task.id, "reassign")
      type_in_panel(view, reason: "Back from leave")
      pick_input(view, "assignee_id")

      html = picked(view, grace.id)
      assert_reply view, %{ok: true}

      assert picker(html) == nil
      assert %{value: value, chosen: "Grace Hopper", errors: []} = field(html, "assignee_id")
      assert value == grace.id
      assert field(html, "reason").value == "Back from leave"

      # nothing has run
      assert stored!(task).assignee_id == ada.id
      assert stored!(task).internal_note == nil

      # the panel's own button runs the action, with the key the field holds
      html = run_panel(view, [])
      assert panel(html) == nil
      assert text(html, cell(task.id, "assignee")) == "Grace Hopper"
      assert %{assignee_id: assignee_id, internal_note: "Back from leave"} = stored!(task)
      assert assignee_id == grace.id
    end

    test "\"None\" empties the field", %{view: view, task: task} do
      act(view, task.id, "reassign")
      pick_input(view, "assignee_id")

      html = picked(view, nil)
      assert picker(html) == nil
      assert %{value: "", chosen: nil} = field(html, "assignee_id")

      run_panel(view, reason: "Nobody has the time")
      assert stored!(task).assignee_id == nil
    end

    test "Cancel in the picker leaves the field and the panel as they were", %{
      view: view,
      task: task,
      ada: ada
    } do
      act(view, task.id, "reassign")
      type_in_panel(view, reason: "Back from leave")
      pick_input(view, "assignee_id")

      html = cancel_picker(view)

      assert picker(html) == nil
      assert %{value: value, chosen: "Ada Lovelace"} = field(html, "assignee_id")
      assert value == ada.id
      assert field(html, "reason").value == "Back from leave"
    end

    test "closing the panel takes its picker with it", %{view: view, task: task} do
      act(view, task.id, "reassign")
      pick_input(view, "assignee_id")

      html = cancel_panel(view)
      assert panel(html) == nil
      assert picker(html) == nil
    end

    test "an error of the action at the field is shown at it, once a record was chosen",
         %{view: view, task: task, grace: grace} do
      act(view, task.id, "reassign")
      pick_input(view, "assignee_id")
      picked(view, grace.id)

      html = run_panel(view, reason: "No")

      assert %{value: value, chosen: "Grace Hopper", errors: []} = field(html, "assignee_id")
      assert value == grace.id
      assert [_too_short] = field(html, "reason").errors
    end
  end

  describe "the fields of keys, in the panel of the create action" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      grace = person(world, "Grace Hopper")
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      %{world: world, grace: grace, view: view}
    end

    test "start empty, and the one of a key that cannot be empty says that it is required",
         %{view: view} do
      html = open_create(view)

      assert %{label: "Project", control: "reference", value: "", chosen: nil, required?: true} =
               field(html, "project_id")

      assert %{label: "Assignee", control: "reference", value: "", chosen: nil, required?: false} =
               field(html, "assignee_id")

      assert text(html, "#task-panel-f-project_id-label .sr-only") == "required"
      assert attribute(html, "#task-panel-f-assignee_id-label .sr-only", "class") == []
    end

    test "each opens its own picker; one that is required offers no \"None\"", %{view: view} do
      open_create(view)

      assert %{
               heading: "Project: choose project",
               table: @projects,
               buttons: ["Cancel", "Choose"]
             } =
               picker(pick_input(view, "project_id"))

      cancel_picker(view)

      assert %{heading: "Assignee: choose user", table: @people, buttons: [_, "None", _]} =
               picker(pick_input(view, "assignee_id"))
    end

    test "a record is created with the records that were chosen", %{
      view: view,
      world: world,
      grace: grace
    } do
      [_first, second] = world.projects
      open_create(view)
      type_in_panel(view, title: "Brand new")

      pick_input(view, "project_id")
      html = picked(view, second.id)
      assert %{chosen: chosen} = field(html, "project_id")
      assert chosen == second.name
      assert field(html, "title").value == "Brand new"

      pick_input(view, "assignee_id")
      html = picked(view, grace.id)
      assert field(html, "assignee_id").chosen == "Grace Hopper"
      # the first choice is still there
      assert field(html, "project_id").value == second.id

      html = run_panel(view, [])
      assert panel(html) == nil
      assert tasks_of(world) == [{"Brand new", second.id, grace.id}]
    end

    test "the required key that is left empty is the action's to refuse, at the field", %{
      view: view,
      world: world
    } do
      open_create(view)

      html = run_panel(view, title: "Without a project")

      assert field(html, "project_id").errors == ["is required"]
      assert tasks_of(world) == []
    end
  end

  describe "the field of a key, in the panel of an action on the selected rows" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      grace = person(world, "Grace Hopper")
      first = task(world, "First")
      second = task(world, "Second")
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      %{world: world, grace: grace, first: first, second: second, view: view}
    end

    test "starts empty and is chosen once, for every selected record", %{
      view: view,
      grace: grace,
      first: first,
      second: second
    } do
      html = bulk(view, "reassign", [first.id, second.id])
      assert %{value: "", chosen: nil} = field(html, "assignee_id")

      pick_input(view, "assignee_id")
      html = picked(view, grace.id)
      assert field(html, "assignee_id").chosen == "Grace Hopper"

      run_panel(view, reason: "Spring cleaning")
      ran(view)

      assert stored!(first).assignee_id == grace.id
      assert stored!(second).assignee_id == grace.id
    end
  end

  describe "a hand-made event" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)

      foreign =
        Generator.generate(
          Generator.project(organization_id: world.other_organization.id, name: "Foreign")
        )

      ada = person(world, "Ada Lovelace")
      task = task(world, "Write the report", assignee_id: ada.id)
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      %{world: world, ada: ada, task: task, foreign: foreign, view: view}
    end

    test "that chooses a record the person cannot read puts nothing into the field", %{
      view: view,
      world: world,
      task: task,
      ada: ada
    } do
      act(view, task.id, "reassign")
      pick_input(view, "assignee_id")

      html = picked(view, world.outsider.id)
      assert_reply view, %{ok: false}

      assert picker(html).error == nil
      assert %{value: value, chosen: "Ada Lovelace"} = field(html, "assignee_id")
      assert value == ada.id
      refute html =~ world.outsider.name
    end

    test "that submits the key of a record the person cannot read runs nothing: a row action",
         %{view: view, world: world, task: task, ada: ada} do
      before = stored!(task)
      act(view, task.id, "reassign")

      html = run_panel(view, assignee_id: world.outsider.id, reason: "Smuggled in")

      # the panel stays open and says which field
      assert panel(html).errors == ["Assignee: This record is no longer available."]
      assert announcement(html) =~ "Assignee: This record is no longer available."
      refute html =~ world.outsider.name

      assert stored!(task).assignee_id == ada.id
      assert stored!(task).internal_note == nil
      assert stored!(task).updated_at == before.updated_at
    end

    test "that submits the key of a record of another tenant creates nothing", %{
      view: view,
      world: world,
      foreign: foreign
    } do
      open_create(view)

      html = run_panel(view, title: "Smuggled in", project_id: foreign.id)

      assert panel(html).errors == ["Project: This record is no longer available."]
      refute html =~ "Foreign"
      assert titles_of(world) == ["Write the report"]

      # nor with a person of another organization beside a project of their own
      html =
        run_panel(view,
          title: "Smuggled in",
          project_id: hd(world.projects).id,
          assignee_id: world.outsider.id
        )

      assert panel(html).errors == ["Assignee: This record is no longer available."]
      assert titles_of(world) == ["Write the report"]

      # and both are said when both are wrong
      html =
        run_panel(view,
          title: "Smuggled in",
          project_id: foreign.id,
          assignee_id: world.outsider.id
        )

      assert panel(html).errors == [
               "Project: This record is no longer available. Assignee: This record is no longer available."
             ]
    end

    test "that submits the key of a record the person cannot read runs on none of the selected rows",
         %{world: world, task: task, ada: ada} do
      other = task(world, "Another")
      {:ok, view, _html} = build_conn() |> log_in(world.admin) |> live("/tasks")

      bulk(view, "reassign", [task.id, other.id])
      html = run_panel(view, assignee_id: world.outsider.id, reason: "Smuggled in")

      assert panel(html).errors == ["Assignee: This record is no longer available."]
      assert stored!(task).assignee_id == ada.id
      assert stored!(other).assignee_id == nil
      assert stored!(other).internal_note == nil
    end

    test "the key a record holds already is nobody's choice: it is given back as it is, though the person may not read that record",
         %{conn: conn, world: world} do
      # reported by the member, who may reassign it; assigned to a person
      # of another organization, whom the member may not read
      abroad =
        task(world, "Assigned abroad",
          reporter_id: world.member.id,
          assignee_id: world.outsider.id
        )

      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")
      act(view, abroad.id, "reassign")

      html = run_panel(view, reason: "Left as it is")

      assert panel(html) == nil
      assert %{assignee_id: assignee_id, internal_note: "Left as it is"} = stored!(abroad)
      assert assignee_id == world.outsider.id
    end

    test "a value that is no key at all is the action's to refuse, at the field", %{
      view: view,
      task: task,
      ada: ada
    } do
      act(view, task.id, "reassign")

      html = run_panel(view, assignee_id: "not a key", reason: "Back from leave")

      assert %{value: "not a key", chosen: nil, errors: ["is invalid"]} =
               field(html, "assignee_id")

      assert stored!(task).assignee_id == ada.id
    end

    test "cannot open a picker for a field that holds no key, or without a panel", %{
      view: view,
      task: task
    } do
      html =
        forge(view, "task", "pick_input", %{"input" => "assignee_id"})

      assert picker(html) == nil

      act(view, task.id, "reassign")

      for name <- ["reason", "nothing", "title"] do
        html = forge(view, "task", "pick_input", %{"input" => name})
        assert picker(html) == nil
      end
    end
  end

  describe "in a nested table" do
    test "the create panel of the tasks under a project chooses the assignee, and is given the project by the table",
         %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      [project | _] = world.projects
      grace = person(world, "Grace Hopper")

      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/projects")
      expand(view, "project", project.id)
      toggle(view, "project", project.id, "tasks")
      tasks = nested("project", project.id, "tasks")

      html = click(view, "[id='project-row-#{project.id}-l-tasks-create']")
      names = Enum.map(panel(html, tasks).fields, & &1.name)
      assert "assignee_id" in names
      refute "project_id" in names

      html = pick_input(view, tasks, "assignee_id")
      assert %{heading: "Assignee: choose user", table: people} = picker(html, tasks)
      assert people == "#{tasks}-pick-assignee_id"

      picked(view, tasks, grace.id)
      run_panel(view, tasks, title: "Under the project")

      assert tasks_of(world) == [{"Under the project", project.id, grace.id}]
    end
  end

  describe "in German" do
    test "the field and its button are translated", %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      {:ok, view, _html} = conn |> log_in(world.admin) |> in_locale("de") |> live("/tasks")

      html = open_create(view)

      assert %{label: "Projekt", required?: true} = field(html, "project_id")
      assert text(html, "#task-panel-f-project_id-choose") == "Auswählen"
      assert text(html, "#task-panel-f-project_id-label .sr-only") == "erforderlich"
      assert picker(pick_input(view, "project_id")).heading == "Projekt: Projekt auswählen"
    end
  end
end
