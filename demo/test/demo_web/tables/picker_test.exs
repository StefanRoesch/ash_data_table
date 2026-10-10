defmodule DemoWeb.Tables.PickerTest do
  @moduledoc """
  The picker, as a person meets it at `/tasks`: the reference cells
  "Project" and "Assignee" are edited by choosing a record of the related
  resource's own table.

  In the browser the table's hook asks for the picker with one `pick` event
  (Enter, F2 or a double click on the cell), and the picker's own hook sends
  one `picked` event with the row that was selected, as the hook of the
  picker's table names it. These tests send those events as the hooks do,
  and read the page. What a hand-made event can and cannot do is tested
  here too: the row it names is a claim.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Task

  @moment ~U[2026-01-01 12:00:00.000000Z]

  # A task of the world's first organization, in its first project, reported
  # by the admin and assigned to nobody.
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

  defp person(world, name, overrides \\ []) do
    Generator.generate(
      Generator.user([organization_id: world.organization.id, name: name] ++ overrides)
    )
  end

  defp stored!(task), do: Ash.get!(Task, task.id, authorize?: false)

  # the picker's table: a table's id like any other
  @people "task-pick-assignee"
  @projects "task-pick-project"

  describe "opening the picker of a reference cell" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      ada = person(world, "Ada Lovelace")
      task = task(world, "Write the report", assignee_id: ada.id)
      {:ok, view, html} = conn |> log_in(world.admin) |> live("/tasks")

      %{world: world, ada: ada, task: task, view: view, html: html}
    end

    test "is not rendered until it is opened", %{html: html} do
      assert picker(html) == nil
      refute html =~ "task-pick-"
      refute html =~ "task-picker"
    end

    test "shows a dialog headed by the column and what is chosen, with the related resource's table in it",
         %{view: view, task: task} do
      html = pick(view, task.id, "assignee")
      assert_reply view, %{ok: true}

      assert %{
               heading: "Assignee: choose user",
               table: @people,
               buttons: ["Cancel", "None", "Choose"],
               question: nil,
               error: nil
             } = picker(html)

      assert attribute(html, "#task-picker", "aria-labelledby") == ["task-picker-title"]
      # the grid in it is named as the people's table is
      assert attribute(html, "##{@people}-table", "aria-label") == ["User"]
    end

    test "the table is the destination's as declared: its columns, its filter row, its sort and its pages",
         %{view: view, world: world, task: task} do
      html = pick(view, task.id, "assignee")

      assert headers(html, @people) == ["Name", "Email", "Role", "Assigned hours"]

      # as the people's read action sorts them: by name
      assert column(html, @people, "name") ==
               Enum.sort(["Ada Lovelace", world.admin.name, world.member.name, world.viewer.name])

      assert %{operators: ["contains" | _], input: "text"} =
               filter_controls(html, @people, "name")

      assert attribute(html, "##{@people}-head-name", "aria-sort") == ["none"]
      assert text(html, "##{@people}-range") == "1–4 of 4"
    end

    test "the table is for choosing only: a radio button per row, and nothing to edit, run, create or expand",
         %{view: view, world: world, task: task} do
      html = pick(view, task.id, "project")

      # the projects' own table has all of this
      {:ok, _view, own} = build_conn() |> log_in(world.admin) |> live("/projects")
      assert editors(own, "project") != []
      assert attribute(own, "#project-create", "id") != []
      assert attribute(own, "#project-actions-head", "id") != []
      assert attribute(own, "#project-expander-head", "id") != []
      assert selection(own, "project") != nil

      assert attribute(html, "##{@projects}-grid", "data-select") == ["single"]
      assert attribute(html, "##{@projects}-grid", "data-choose") == [""]
      assert attribute(html, "##{@projects}-table", "aria-multiselectable") == ["false"]

      assert attribute(html, "##{@projects}-table td[data-selector] > input", "type") ==
               ["radio", "radio"]

      assert editors(html, @projects) == []
      assert attribute(html, "##{@projects}-table [aria-readonly]", "id") == []
      assert attribute(html, "##{@projects}-create", "id") == []
      assert attribute(html, "##{@projects}-actions-head", "id") == []
      assert attribute(html, "##{@projects}-expander-head", "id") == []
      assert attribute(html, "##{@projects}-table td[data-expander]", "id") == []
      assert selection(html, @projects) == nil
      assert attribute(html, "##{@projects}-dialog", "id") == []
    end

    test "marks the row of the record the cell points at now, where it is on the page",
         %{view: view, world: world, ada: ada, task: task} do
      html = pick(view, task.id, "assignee")
      assert current(html, @people) == [ada.id]

      cancel_picker(view)
      html = pick(view, task.id, "project")
      assert current(html, @projects) == [hd(world.projects).id]

      # none where the cell points at nobody
      cancel_picker(view)
      free = task(world, "Assigned to nobody")
      {:ok, view, _html} = build_conn() |> log_in(world.admin) |> live("/tasks")
      html = pick(view, free.id, "assignee")
      assert current(html, @people) == []
    end

    test "offers \"None\" where the key can be empty, and not where it cannot", %{
      view: view,
      task: task
    } do
      assert picker(pick(view, task.id, "assignee")).buttons == ["Cancel", "None", "Choose"]
      cancel_picker(view)
      # a task has to have a project
      assert picker(pick(view, task.id, "project")).buttons == ["Cancel", "Choose"]
    end

    test "carries the column's question, which is asked before a choice is saved", %{
      view: view,
      task: task
    } do
      assert picker(pick(view, task.id, "project")).question ==
               "Move this task to another project?"
    end

    test "is closed by Cancel, and nothing has changed", %{view: view, task: task, ada: ada} do
      pick(view, task.id, "assignee")
      html = cancel_picker(view)

      assert picker(html) == nil
      assert text(html, cell(task.id, "assignee")) == "Ada Lovelace"
      assert stored!(task).assignee_id == ada.id
    end

    test "is closed by a new read of the table it belongs to", %{view: view, task: task} do
      pick(view, task.id, "assignee")
      html = filter(view, "task", "title", v: "report")

      assert picker(html) == nil
      assert column(html, "task", "title") == ["Write the report"]
    end

    test "sorts, filters and pages by itself, and stays open", %{view: view, task: task} do
      pick(view, task.id, "assignee")

      html = filter(view, @people, "name", v: "Lovelace")
      assert column(html, @people, "name") == ["Ada Lovelace"]
      assert picker(html).heading == "Assignee: choose user"

      html = view |> element("##{@people}-head-email") |> render_click()
      render_async(view, 2000)
      assert attribute(html, "##{@people}-head-email", "aria-sort") == ["ascending"]

      # nothing of it is in the page's URL
      refute_received {_ref, {:patch, _topic, _to}}
    end
  end

  describe "who is offered what" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)

      foreign =
        Generator.generate(
          Generator.project(organization_id: world.other_organization.id, name: "Foreign")
        )

      task = task(world, "Write the report", reporter_id: world.member.id)
      %{world: world, task: task, foreign: foreign, conn: conn}
    end

    test "the records the destination's read action returns for this person, in their tenant, and no others",
         %{conn: conn, world: world, task: task, foreign: foreign} do
      for actor <- [world.admin, world.member] do
        {:ok, view, _html} = conn |> log_in(actor) |> live("/tasks")

        html = pick(view, task.id, "assignee")
        names = column(html, @people, "name")
        assert world.member.name in names
        # a person of another organization is nobody they may read
        refute world.outsider.name in names
        refute html =~ world.outsider.name

        cancel_picker(view)
        html = pick(view, task.id, "project")

        assert Enum.sort(column(html, @projects, "name")) ==
                 Enum.sort(Enum.map(world.projects, & &1.name))

        refute html =~ foreign.name
      end
    end

    test "the outsider is offered the people and the projects of their own organization",
         %{conn: conn, world: world, foreign: foreign} do
      theirs =
        Generator.generate(
          Generator.task(
            organization_id: world.other_organization.id,
            project_id: foreign.id,
            reporter_id: world.outsider.id,
            assignee_id: nil,
            title: "Abroad"
          )
        )

      {:ok, view, _html} = conn |> log_in(world.outsider) |> live("/tasks")

      html = pick(view, theirs.id, "assignee")
      assert column(html, @people, "name") == [world.outsider.name]

      cancel_picker(view)
      html = pick(view, theirs.id, "project")
      # their own organization's, and none of the other's
      assert "Foreign" in column(html, @projects, "name")
      refute Enum.any?(world.projects, &(&1.name in column(html, @projects, "name")))
    end

    test "a field of the people that this person never sees is no column of the picker either",
         %{conn: conn, world: world, task: task} do
      # `assigned_hours` is seen by admins alone
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      assert headers(pick(view, task.id, "assignee"), @people) == ["Name", "Email", "Role"]
    end

    test "a person who can run no update action has no picker: the viewer, and nobody", %{
      conn: conn,
      world: world,
      task: task
    } do
      for actor <- [world.viewer, nil] do
        {:ok, view, html} = conn |> log_in(actor) |> live("/tasks")

        assert editors(html, "task") == []

        html = pick(view, task.id, "project")
        assert_reply view, %{ok: false}
        assert picker(html) == nil
      end
    end
  end

  describe "choosing" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      ada = person(world, "Ada Lovelace")
      grace = person(world, "Grace Hopper")
      task = task(world, "Write the report", assignee_id: ada.id)
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      %{world: world, ada: ada, grace: grace, task: task, view: view}
    end

    test "saves the key of the chosen record through the column's update action, and shows the row from its result",
         %{view: view, task: task, grace: grace} do
      before = stored!(task)
      pick(view, task.id, "assignee")

      html = picked(view, grace.id)
      assert_reply view, %{ok: true}

      assert picker(html) == nil
      assert text(html, cell(task.id, "assignee")) == "Grace Hopper"
      assert failure(html, task.id, "assignee") == nil

      # one input, the key: nothing else of the record has changed
      now = stored!(task)
      assert now.assignee_id == grace.id

      assert Map.drop(now, [:assignee_id, :updated_at, :__meta__, :__metadata__]) ==
               Map.drop(before, [:assignee_id, :updated_at, :__meta__, :__metadata__])
    end

    test "the record the cell points at already calls nothing", %{
      view: view,
      task: task,
      ada: ada
    } do
      before = stored!(task)
      pick(view, task.id, "assignee")

      html = picked(view, ada.id)
      assert_reply view, %{ok: true}

      assert picker(html) == nil
      assert text(html, cell(task.id, "assignee")) == "Ada Lovelace"
      # not even the timestamp an update sets
      assert stored!(task).updated_at == before.updated_at
    end

    test "\"None\" empties the key, where it can be empty", %{view: view, task: task} do
      pick(view, task.id, "assignee")

      html = picked(view, nil)
      assert_reply view, %{ok: true}

      assert picker(html) == nil
      assert text(html, cell(task.id, "assignee")) == ""
      assert stored!(task).assignee_id == nil

      # and once more calls nothing
      before = stored!(task)
      pick(view, task.id, "assignee")
      picked(view, nil)
      assert stored!(task).updated_at == before.updated_at
    end

    test "no record for a key that cannot be empty is the action's to refuse: shown on the cell, nothing saved",
         %{view: view, world: world, task: task} do
      pick(view, task.id, "project")

      # nothing the picker offers: it has no "None" for a project
      html = confirm_picked(view, nil)
      assert_reply view, %{ok: false}

      assert picker(html) == nil
      assert %{shown: "", message: "is required"} = failure(html, task.id, "project")
      assert stored!(task).project_id == hd(world.projects).id

      # Escape on the cell gives it up
      html = discard(view, task.id, "project")
      assert failure(html, task.id, "project") == nil
      assert text(html, cell(task.id, "project")) == hd(world.projects).name
    end

    test "a column with a question asks first, and saves once the person has confirmed",
         %{view: view, world: world, task: task} do
      [first, second] = world.projects
      pick(view, task.id, "project")

      html = picked(view, second.id)
      assert_reply view, %{ask: "Move this task to another project?"}

      # nothing is saved, and the picker is still there
      assert picker(html) != nil
      assert stored!(task).project_id == first.id

      html = confirm_picked(view, second.id)
      assert_reply view, %{ok: true}

      assert picker(html) == nil
      assert text(html, cell(task.id, "project")) == second.name
      assert stored!(task).project_id == second.id
    end

    test "and asks nothing for the record the cell points at already", %{
      view: view,
      world: world,
      task: task
    } do
      pick(view, task.id, "project")

      html = picked(view, hd(world.projects).id)
      assert_reply view, %{ok: true}
      assert picker(html) == nil
    end

    test "a save the action refuses is shown on the cell as the action returned it, with what was chosen",
         %{world: world, grace: grace} do
      # a task that is done, and not at 100: every update of it is refused
      # by the tasks' validation
      stuck = task(world, "Stuck", status: :done, progress: 50)
      {:ok, view, _html} = build_conn() |> log_in(world.admin) |> live("/tasks")

      pick(view, stuck.id, "assignee")
      html = picked(view, grace.id)
      assert_reply view, %{ok: false}

      assert picker(html) == nil

      assert failure(html, stuck.id, "assignee") ==
               %{shown: "Grace Hopper", message: "Progress: must be 100 when the task is done"}

      assert announcement(html) ==
               "Assignee was not saved: Progress: must be 100 when the task is done"

      assert stored!(stuck).assignee_id == nil

      # the picker opens again on the record the row has, and Escape gives the failure up
      assert current(pick(view, stuck.id, "assignee"), @people) == []
      cancel_picker(view)
      html = discard(view, stuck.id, "assignee")
      assert failure(html, stuck.id, "assignee") == nil
      assert text(html, cell(stuck.id, "assignee")) == ""
    end

    test "a save the policies refuse says so on the cell: a member, on a task that is not theirs",
         %{conn: conn, world: world, task: task, ada: ada, grace: grace} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      pick(view, task.id, "assignee")
      html = picked(view, grace.id)
      assert_reply view, %{ok: false}

      assert failure(html, task.id, "assignee") ==
               %{shown: "Grace Hopper", message: "You are not allowed to change this."}

      assert stored!(task).assignee_id == ada.id
    end

    test "a row that has been deleted meanwhile says so, and nothing is saved", %{
      view: view,
      task: task,
      grace: grace
    } do
      pick(view, task.id, "assignee")
      Ash.destroy!(stored!(task), authorize?: false)

      html = picked(view, grace.id)
      assert_reply view, %{ok: false, error: "This record is no longer available."}
      assert picker(html) == nil

      # and there is nothing to open a picker for
      pick(view, task.id, "assignee")
      assert_reply view, %{ok: false, error: "This record is no longer available."}
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

    test "that names a record the person cannot read changes nothing: a person of another organization",
         %{view: view, world: world, task: task, ada: ada} do
      before = stored!(task)
      pick(view, task.id, "assignee")

      html = picked(view, world.outsider.id)
      assert_reply view, %{ok: false}

      # the picker stays, and says that the record is not there for them
      assert picker(html).error == "This record is no longer available."
      assert announcement(html) == "This record is no longer available."
      refute html =~ world.outsider.name

      assert stored!(task).assignee_id == ada.id
      assert stored!(task).updated_at == before.updated_at
      assert failure(html, task.id, "assignee") == nil
    end

    test "that names a record of another tenant changes nothing, confirmed or not", %{
      view: view,
      world: world,
      task: task,
      foreign: foreign
    } do
      before = stored!(task)
      pick(view, task.id, "project")

      for choose <- [&picked/2, &confirm_picked/2] do
        html = choose.(view, foreign.id)
        assert_reply view, %{ok: false}

        assert picker(html).error == "This record is no longer available."
        refute html =~ "Foreign"
      end

      assert stored!(task).project_id == hd(world.projects).id
      assert stored!(task).updated_at == before.updated_at
    end

    test "that names no record at all changes nothing", %{view: view, task: task, ada: ada} do
      pick(view, task.id, "assignee")

      for row <- [
            Ash.UUID.generate(),
            "not a key",
            "",
            [ada.id, ada.id],
            %{"id" => ada.id},
            42,
            true
          ] do
        html =
          view
          |> element("#task-picker")
          |> render_hook("picked", %{"row" => row, "confirmed" => true})

        assert picker(html).error == "This record is no longer available."
      end

      assert stored!(task).assignee_id == ada.id
    end

    test "is taken for the cell the picker was opened for, whatever else it says", %{
      view: view,
      task: task,
      ada: ada,
      world: world
    } do
      other = task(world, "Another task")
      pick(view, task.id, "assignee")

      view
      |> element("#task-picker")
      |> render_hook("picked", %{
        "row" => world.member.id,
        "for" => other.id,
        "column" => "reporter",
        "key" => other.id
      })

      assert stored!(task).assignee_id == world.member.id
      assert stored!(other).assignee_id == nil
      assert stored!(other).reporter_id == world.admin.id
      refute stored!(task).assignee_id == ada.id
    end

    test "that chooses without a picker does nothing", %{
      view: view,
      world: world,
      task: task,
      ada: ada
    } do
      view
      |> element("#task-grid")
      |> render_hook("picked", %{"row" => world.member.id, "confirmed" => true})

      assert_reply view, %{ok: false}
      assert stored!(task).assignee_id == ada.id
    end

    test "cannot open a picker for a column nobody edits, for another kind of column, or for a row that is not on the page",
         %{view: view, world: world, task: task} do
      hidden = hd(world_task_elsewhere(world))

      for {key, column} <- [
            {task.id, "reporter"},
            {task.id, "title"},
            {task.id, "assignee_id"},
            {task.id, "nothing"},
            {hidden.id, "assignee"},
            {Ash.UUID.generate(), "assignee"}
          ] do
        html = pick(view, key, column)
        assert_reply view, %{ok: false}
        assert picker(html) == nil
      end
    end

    # a task of the other organization: no row of this person's page
    defp world_task_elsewhere(world) do
      project =
        Generator.generate(Generator.project(organization_id: world.other_organization.id))

      [
        Generator.generate(
          Generator.task(
            organization_id: world.other_organization.id,
            project_id: project.id,
            reporter_id: world.outsider.id,
            title: "Elsewhere"
          )
        )
      ]
    end

    test "can do nothing in the picker's table but choose: no save, no action, no create, no run on the selection, no expanding",
         %{view: view, world: world, task: task} do
      [project | _] = world.projects
      pick(view, task.id, "project")

      html = save(view, @projects, project.id, "name", "Renamed in the picker")
      assert_reply view, %{ok: false}
      assert text(html, cell(@projects, project.id, "name")) == project.name

      for action <- ["set_status", "destroy"] do
        act(view, @projects, project.id, action)
        assert_reply view, %{ok: false}
      end

      html = view |> element("##{@projects}-grid") |> render_hook("create", %{})
      assert panel(html, @projects) == nil

      bulk(view, @projects, "set_status", [project.id])
      assert_reply view, %{ok: false}
      run_bulk(view, @projects, "set_status", [project.id])

      expand(view, @projects, project.id)
      assert_reply view, %{open: false}

      stored = Ash.get!(Demo.Tracker.Project, project.id, authorize?: false)
      assert stored.name == project.name
      assert stored.status == project.status
      assert picker(render(view)) != nil
    end
  end

  describe "in a nested table and in the full view" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      [project, other] = world.projects
      grace = person(world, "Grace Hopper")
      task = task(world, "Write the report")

      %{world: world, project: project, other: other, grace: grace, task: task, conn: conn}
    end

    test "a reference cell of a nested table has its own picker, and saves in its own table",
         %{conn: conn, world: world, project: project, grace: grace, task: task} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/projects")
      expand(view, "project", project.id)
      html = toggle(view, "project", project.id, "tasks")
      tasks = nested("project", project.id, "tasks")

      assert "assignee" in editors(html, tasks)

      html = pick(view, tasks, task.id, "assignee")
      assert %{heading: "Assignee: choose user", table: people} = picker(html, tasks)
      assert people == "#{tasks}-pick-assignee"
      assert world.member.name in column(html, people, "name")
      # the table around it has none
      assert picker(html, "project") == nil

      html = picked(view, tasks, grace.id)
      assert picker(html, tasks) == nil
      assert text(html, cell(tasks, task.id, "assignee")) == "Grace Hopper"
      assert stored!(task).assignee_id == grace.id

      # a hand-made choice of somebody they may not read changes nothing here either
      pick(view, tasks, task.id, "assignee")
      html = picked(view, tasks, world.outsider.id)
      assert picker(html, tasks).error == "This record is no longer available."
      assert stored!(task).assignee_id == grace.id
    end

    test "a task moved to another project from under its project stays in view until the table reads again",
         %{conn: conn, world: world, project: project, other: other, task: task} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/projects")
      expand(view, "project", project.id)
      toggle(view, "project", project.id, "tasks")
      tasks = nested("project", project.id, "tasks")

      pick(view, tasks, task.id, "project")
      html = confirm_picked(view, tasks, other.id)

      assert text(html, cell(tasks, task.id, "project")) == other.name
      assert stored!(task).project_id == other.id
    end

    test "the full view of a nested table chooses as a table of its own does", %{
      conn: conn,
      world: world,
      project: project,
      grace: grace,
      task: task
    } do
      {:ok, view, html} =
        conn |> log_in(world.admin) |> live("/tasks?task[of][project][tasks]=#{project.id}")

      assert column(html, "task", "title") == ["Write the report"]

      html = pick(view, task.id, "assignee")
      assert picker(html).heading == "Assignee: choose user"

      html = picked(view, grace.id)
      assert text(html, cell(task.id, "assignee")) == "Grace Hopper"
      assert stored!(task).assignee_id == grace.id
    end
  end

  describe "in German" do
    test "the picker's heading, its buttons and its table are translated", %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      task = task(world, "Write the report")

      {:ok, view, _html} = conn |> log_in(world.admin) |> in_locale("de") |> live("/tasks")
      html = pick(view, task.id, "assignee")

      assert %{
               heading: "Zugewiesen an: Person auswählen",
               buttons: ["Abbrechen", "Keine Auswahl", "Auswählen"]
             } = picker(html)

      assert headers(html, @people) == ["Name", "E-Mail", "Rolle", "Zugewiesene Stunden"]
      assert attribute(html, "##{@people}-table", "aria-label") == ["Personen"]

      cancel_picker(view)

      assert %{
               heading: "Projekt: Projekt auswählen",
               question: "Diese Aufgabe in ein anderes Projekt verschieben?"
             } = picker(pick(view, task.id, "project"))
    end
  end
end
