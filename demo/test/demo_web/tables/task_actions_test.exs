defmodule DemoWeb.Tables.TaskActionsTest do
  @moduledoc """
  Row actions in the mounted table of `Demo.Tracker.Task` at `/tasks`: the
  actions column, the actions that run straight away, and the ones that open
  the action panel.

  A button of the actions column is used in the browser; the table's hook
  then sends one `act` event with the row and the action, after the
  question of an action that has one. These tests send that event as the
  hook does, fill in the panel's form as a person does, and read the page.
  """
  use DemoWeb.ModeCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Task

  # One task of the world's first organization, reported by the admin and
  # assigned to nobody. Each is created a day after `day`: the highest first.
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
          description: nil,
          status: :in_progress,
          priority: :medium,
          progress: 40,
          estimate_hours: Decimal.new("12.5"),
          billable?: false,
          due_on: nil,
          completed_at: nil,
          external_ref: nil,
          internal_note: nil,
          inserted_at: DateTime.add(~U[2026-01-01 12:00:00.000000Z], day, :day)
        ] ++ overrides
      )
    )
  end

  defp stored(task), do: Ash.get(Task, task.id, authorize?: false, not_found_error?: false)
  defp stored!(task), do: Ash.get!(Task, task.id, authorize?: false)
  defp titles(html), do: column(html, "task", "title")

  describe "the actions column" do
    setup do
      world = world(tasks: 0)
      %{world: world, task: task(world, 1, [])}
    end

    test "is the last column of the grid, with a header, an empty filter cell and a button per action",
         %{conn: conn, world: world, task: task} do
      {:ok, _view, html} = conn |> log_in(world.admin) |> live("/tasks")

      # the boxes, the expanders, the nineteen columns of the table, the actions
      assert attribute(html, "#task-table", "aria-colcount") == ["25"]

      assert text(html, "#task-actions-head") == "Actions"
      assert attribute(html, "#task-actions-head", "role") == ["columnheader"]
      assert attribute(html, "#task-actions-head", "aria-colindex") == ["25"]

      assert attribute(html, "#task-head-row > [role=columnheader]:last-child", "id") == [
               "task-actions-head"
             ]

      assert text(html, "#task-actions-filter") == ""
      assert attribute(html, "#task-actions-filter", "aria-colindex") == ["25"]

      assert attribute(html, "#task-filter-row > [role=gridcell]:last-child", "id") == [
               "task-actions-filter"
             ]

      assert attribute(html, actions_cell(task.id), "role") == ["gridcell"]
      assert attribute(html, actions_cell(task.id), "aria-colindex") == ["25"]

      assert attribute(html, "[id='task-row-#{task.id}-r'] > [role=gridcell]:last-child", "id") ==
               ["task-row-#{task.id}-a"]

      # the columns before it are where they were
      assert attribute(html, cell(task.id, "reporter"), "aria-colindex") == ["24"]

      assert actions(html, task.id) == [
               "Archive",
               "Reassign",
               "Set progress",
               "Destroy",
               "Set labels"
             ]
    end

    test "has the buttons of the actions a person can ever run, and is not there when that is none",
         %{conn: conn, world: world, task: task} do
      # a member may run them on their own tasks: the buttons are there on every row
      {:ok, _view, html} = conn |> log_in(world.member) |> live("/tasks")

      assert actions(html, task.id) == [
               "Archive",
               "Reassign",
               "Set progress",
               "Destroy",
               "Set labels"
             ]

      # a viewer may run none
      {:ok, _view, html} = conn |> log_in(world.viewer) |> live("/tasks")
      assert titles(html) == ["Task 1"]
      assert attribute(html, "#task-actions-head", "id") == []
      assert attribute(html, actions_cell(task.id), "id") == []
      # the expanders (a viewer is offered some lines) and the sixteen columns a viewer has
      assert attribute(html, "#task-table", "aria-colcount") == ["20"]
    end

    test "is there for a person of another organization, on their own records only",
         %{conn: conn, world: world, task: task} do
      {:ok, view, html} = conn |> log_in(world.outsider) |> live("/tasks")
      [own | _] = world.other_tasks

      assert length(titles(html)) == length(world.other_tasks)

      assert actions(html, own.id) == [
               "Archive",
               "Reassign",
               "Set progress",
               "Destroy",
               "Set labels"
             ]

      assert text(html, "#task-create") == "New task"

      # a task of the first organization is no row of theirs: by its key nothing runs
      act(view, task.id, "archive")
      act(view, task.id, "destroy")
      assert panel(act(view, task.id, "reassign")) == nil
      assert {:ok, %Task{status: :in_progress}} = stored(task)
    end

    test "has nothing in it for nobody, who has no rows, no create button, and can run nothing",
         %{conn: conn, world: world, task: task} do
      {:ok, view, html} = conn |> log_in(world.nobody) |> live("/tasks")

      assert titles(html) == []
      assert text(html, "#task-create") == nil
      assert html |> attribute("#task-table button[data-action]", "id") == []

      act(view, task.id, "destroy")
      forge(view, "task", "create", %{})

      html =
        forge(view, "task", "panel_submit", %{
          "panel" => %{"title" => "Anonymous"}
        })

      assert panel(html) == nil
      assert {:ok, %Task{}} = stored(task)
    end
  end

  describe "an action without inputs" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      [project | _] = world.projects
      task = task(world, 2, title: "Write the report", assignee_id: world.member.id)
      other = task(world, 1, title: "File the report")

      Generator.generate(
        Generator.comment(
          organization_id: world.organization.id,
          task_id: task.id,
          author_id: world.admin.id
        )
      )

      conn = log_in(conn, world.admin)
      {:ok, view, html} = live(conn, "/tasks")

      %{
        conn: conn,
        view: view,
        html: html,
        world: world,
        task: task,
        other: other,
        project: project
      }
    end

    test "runs when its button is used: the record is changed, and no other",
         %{view: view, task: task, other: other} do
      html = act(view, task.id, "archive")

      assert text(html, cell(task.id, "status")) == "Archived"
      assert text(html, cell(other.id, "status")) == "In progress"

      assert stored!(task).status == :archived
      assert stored!(other).status == :in_progress

      # nothing is asked for first
      assert panel(html) == nil
      assert action_failure(html, task.id) == nil
      assert announcement(html) == "Archive: done"
    end

    test "shows the row again as the action returned it, with everything its columns show",
         %{view: view, world: world, task: task, project: project} do
      html = act(view, task.id, "archive")

      assert titles(html) == ["Write the report", "File the report"]
      assert text(html, cell(task.id, "title")) == "Write the report"
      # an aggregate, a calculation computed in Elixir, and two reference cells
      assert text(html, cell(task.id, "comment_count")) == "1"
      assert text(html, cell(task.id, "headline")) == "Medium: Write the report (40%)"
      assert text(html, cell(task.id, "project")) == project.name
      assert text(html, cell(task.id, "assignee")) == world.member.name
      # and its buttons
      assert actions(html, task.id) == [
               "Archive",
               "Reassign",
               "Set progress",
               "Destroy",
               "Set labels"
             ]
    end
  end

  describe "an action that ran straight away and failed" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      # a member may change the tasks they are assigned to or reported
      own = task(world, 2, title: "Mine", assignee_id: world.member.id)
      foreign = task(world, 1, title: "Somebody else's")

      conn = log_in(conn, world.member)
      {:ok, view, _html} = live(conn, "/tasks")
      %{conn: conn, view: view, world: world, own: own, foreign: foreign}
    end

    test "shows the action's refusal on the row's actions cell, and changes nothing",
         %{view: view, own: own, foreign: foreign} do
      html = act(view, foreign.id, "archive")

      assert action_failure(html, foreign.id) == "You are not allowed to do this."
      assert announcement(html) == "Archive failed: You are not allowed to do this."
      # nothing pops up over the page
      assert panel(html) == nil

      assert text(html, cell(foreign.id, "status")) == "In progress"
      assert stored!(foreign).status == :in_progress

      assert actions(html, foreign.id) == [
               "Archive",
               "Reassign",
               "Set progress",
               "Destroy",
               "Set labels"
             ]

      # the other row has nothing to say
      assert action_failure(html, own.id) == nil
    end

    test "is cleared by the next action that runs in the row", %{
      view: view,
      world: world,
      foreign: foreign
    } do
      assert action_failure(act(view, foreign.id, "archive"), foreign.id) != nil

      # the task becomes the member's
      Ash.update!(foreign, %{assignee_id: world.member.id}, action: :update, authorize?: false)

      html = act(view, foreign.id, "archive")

      assert action_failure(html, foreign.id) == nil
      assert text(html, cell(foreign.id, "status")) == "Archived"
    end

    test "is cleared when the person gives it up with Escape on the cell",
         %{view: view, foreign: foreign} do
      assert action_failure(act(view, foreign.id, "archive"), foreign.id) != nil

      html = dismiss(view, foreign.id)

      assert action_failure(html, foreign.id) == nil
      assert text(html, cell(foreign.id, "title")) == "Somebody else's"
    end

    test "is forgotten by the next read", %{view: view, foreign: foreign} do
      assert action_failure(act(view, foreign.id, "archive"), foreign.id) != nil

      view |> element("#task-head-title") |> render_click()
      html = render_async(view)

      assert titles(html) == ["Mine", "Somebody else's"]
      assert action_failure(html, foreign.id) == nil
    end

    test "stands beside a cell of the row whose save failed", %{view: view, foreign: foreign} do
      save(view, foreign.id, "title", "Renamed")
      html = act(view, foreign.id, "archive")

      assert failure(html, foreign.id, "title") == %{
               shown: "Renamed",
               message: "You are not allowed to change this."
             }

      assert action_failure(html, foreign.id) == "You are not allowed to do this."

      # each is given up by itself
      html = dismiss(view, foreign.id)
      assert action_failure(html, foreign.id) == nil
      assert failure(html, foreign.id, "title").shown == "Renamed"
    end

    test "says that the record is gone when it is, and leaves the row as it is",
         %{view: view, own: own} do
      Ash.destroy!(own, authorize?: false)

      html = act(view, own.id, "archive")

      # there is no record to show the row from: the hook marks the cell
      # with the message the table sends back
      assert text(html, cell(own.id, "title")) == "Mine"
      assert announcement(html) == "Archive failed: This record is no longer available."
    end
  end

  describe "a destroy action" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      first = task(world, 3, title: "First")
      second = task(world, 2, title: "Second")
      third = task(world, 1, title: "Third")

      comment =
        Generator.generate(
          Generator.comment(
            organization_id: world.organization.id,
            task_id: second.id,
            author_id: world.admin.id
          )
        )

      conn = log_in(conn, world.admin)
      {:ok, view, html} = live(conn, "/tasks")

      %{conn: conn, view: view, html: html, world: world, comment: comment}
      |> Map.merge(%{first: first, second: second, third: third})
    end

    test "carries its question to the button, for the hook to ask before the event is sent",
         %{html: html, second: second} do
      button = "[id='task-row-#{second.id}-a-destroy']"

      assert attribute(html, button, "data-question") == [
               "Delete this task? This cannot be undone."
             ]

      assert attribute(html, "[id='task-row-#{second.id}-a-archive']", "data-question") == []
      # the table has the dialog the question is asked in
      assert attribute(html, "#task-dialog", "aria-labelledby") == ["task-dialog-question"]
    end

    test "takes the row out of the page, and the record out of the database",
         %{view: view, html: before, first: first, second: second, third: third} do
      assert titles(before) == ["First", "Second", "Third"]
      assert text(before, "#task-range") == "1–3 of 3"
      # three tasks, the two header rows and the footer row of the summaries
      assert attribute(before, "#task-table", "aria-rowcount") == ["6"]

      html = act(view, second.id, "destroy")

      assert titles(html) == ["First", "Third"]
      assert stored(second) == {:ok, nil}
      assert {:ok, %Task{}} = stored(first)
      assert {:ok, %Task{}} = stored(third)

      # the total is one less, and so is everything said from it
      assert text(html, "#task-range") == "1–2 of 2"
      assert attribute(html, "#task-table", "aria-rowcount") == ["5"]
      assert announcement(html) == "Destroy: done"
    end

    test "moves the rows after it up by one: a row that is shown again says so",
         %{view: view, html: before, first: first, second: second, third: third} do
      assert attribute(before, "[id='task-row-#{third.id}-r']", "aria-rowindex") == ["5"]

      act(view, second.id, "destroy")
      html = save(view, third.id, "title", "Third, renamed")
      assert attribute(html, "[id='task-row-#{third.id}-r']", "aria-rowindex") == ["4"]

      html = save(view, first.id, "title", "First, renamed")
      assert attribute(html, "[id='task-row-#{first.id}-r']", "aria-rowindex") == ["3"]
    end

    test "takes what was open under the row with it", %{
      view: view,
      second: second,
      comment: comment
    } do
      expand(view, second.id)
      html = toggle(view, second.id, "comments")
      comments = nested(second.id, "comments")
      assert column(html, comments, "body") == [comment.body]

      html = act(view, second.id, "destroy")

      refute html =~ comments
      refute html =~ "task-row-#{second.id}"
      assert titles(html) == ["First", "Third"]
    end

    test "reads the page again when it took the last row of it", %{view: view} = context do
      for task <- [context.first, context.second], do: act(view, task.id, "destroy")
      html = act(view, context.third.id, "destroy")
      html = if html =~ "task-empty", do: html, else: render_async(view)

      assert titles(html) == []
      assert text(html, "#task-empty") == "No records"
      # the two header rows and the footer row of the summaries
      assert attribute(html, "#task-table", "aria-rowcount") == ["3"]
    end

    test "that is refused leaves the row, with the refusal on its actions cell",
         %{conn: conn, world: world, second: second} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      html = act(view, second.id, "destroy")

      assert titles(html) == ["First", "Second", "Third"]
      assert action_failure(html, second.id) == "You are not allowed to do this."
      assert {:ok, %Task{}} = stored(second)
      assert text(html, "#task-range") == "1–3 of 3"
    end
  end

  describe "an action with inputs" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, 2, title: "Write the report", assignee_id: world.member.id, progress: 40)
      other = task(world, 1, title: "File the report")

      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")
      %{conn: conn, view: view, world: world, task: task, other: other}
    end

    test "opens the action panel and runs nothing yet", %{view: view, world: world, task: task} do
      html = act(view, task.id, "reassign")

      assert %{heading: "Reassign: Write the report", submit: "Run", errors: []} = panel(html)
      assert attribute(html, "#task-panel", "aria-labelledby") == ["task-panel-title"]

      assert stored!(task).assignee_id == world.member.id
      assert stored!(task).internal_note == nil
    end

    test "has a field per input, top to bottom: the attributes with the record's values, then the arguments",
         %{view: view, world: world, task: task} do
      assert panel(act(view, task.id, "reassign")).fields == [
               # the key of a related record is chosen in the picker: the field
               # holds the key, says what the record is called, and is
               # labelled as the table's column of the relationship
               %{
                 name: "assignee_id",
                 label: "Assignee",
                 control: "reference",
                 value: world.member.id,
                 chosen: world.member.name,
                 required?: false,
                 errors: []
               },
               %{
                 name: "reason",
                 label: "Reason",
                 control: "textarea",
                 value: "",
                 required?: true,
                 errors: []
               }
             ]
    end

    test "labels the field of an attribute as its column, with the editor its column has",
         %{view: view, task: task} do
      assert panel(act(view, task.id, "set_progress")) == %{
               heading: "Set progress: Write the report",
               fields: [
                 %{
                   name: "progress",
                   label: "Progress",
                   # the slider of the column's component
                   control: "range",
                   value: "40",
                   required?: true,
                   errors: []
                 }
               ],
               errors: [],
               submit: "Run"
             }
    end

    test "runs with what the person gave, on the right record, and closes the panel",
         %{view: view, world: world, task: task, other: other} do
      act(view, task.id, "reassign")

      html = run_panel(view, assignee_id: world.admin.id, reason: "Back from leave")

      assert panel(html) == nil
      assert announcement(html) == "Reassign: done"

      # the row is shown as the action returned it, reference cell and all
      assert text(html, cell(task.id, "assignee")) == world.admin.name
      assert text(html, cell(task.id, "title")) == "Write the report"
      assert text(html, cell(other.id, "assignee")) == ""

      assert %{assignee_id: assignee_id, internal_note: "Back from leave"} = stored!(task)
      assert assignee_id == world.admin.id
      assert %{assignee_id: nil, internal_note: nil} = stored!(other)
    end

    test "runs with an attribute's value changed in its field", %{
      view: view,
      task: task,
      other: other
    } do
      act(view, task.id, "set_progress")

      html = run_panel(view, progress: "75")

      assert panel(html) == nil
      assert text(html, cell(task.id, "progress")) == "75"
      assert stored!(task).progress == 75
      assert stored!(other).progress == 40
    end

    test "is given what is typed as it is typed, and shows the action's errors at their fields",
         %{view: view, task: task} do
      act(view, task.id, "reassign")

      html = type_in_panel(view, reason: "No")

      assert [%{name: "assignee_id", errors: []}, %{name: "reason", value: "No", errors: [error]}] =
               panel(html).fields

      assert error == "length must be greater than or equal to 3"

      # the field says so to assistive technology too
      assert attribute(html, "#task-panel-f-reason", "aria-invalid") == ["true"]

      # with its counter: the reason has a most it can be long
      assert attribute(html, "#task-panel-f-reason", "aria-describedby") == [
               "task-panel-f-reason-error task-panel-f-reason-count"
             ]

      assert text(html, "#task-panel-f-reason-error") == error
      assert attribute(html, "#task-panel-f-assignee_id", "aria-invalid") == []

      # and no longer once it is put right
      html = type_in_panel(view, reason: "Not any more")
      assert [%{errors: []}, %{value: "Not any more", errors: []}] = panel(html).fields
      assert attribute(html, "#task-panel-f-reason", "aria-invalid") == []

      # nothing has run
      assert stored!(task).internal_note == nil
    end

    test "that fails stays open with the errors at their fields, and changes nothing",
         %{view: view, world: world, task: task} do
      act(view, task.id, "reassign")

      html = run_panel(view, assignee_id: "not a key", reason: "")

      assert %{heading: "Reassign: Write the report", errors: []} = panel(html)

      assert [
               %{name: "assignee_id", value: "not a key", errors: ["is invalid"]},
               %{name: "reason", value: "", errors: ["is required"]}
             ] = panel(html).fields

      assert announcement(html) == "Reassign failed: Assignee: is invalid; Reason: is required"

      assert stored!(task).assignee_id == world.member.id
      assert text(html, cell(task.id, "assignee")) == world.member.name

      # and runs once it is put right
      html = run_panel(view, assignee_id: world.viewer.id, reason: "Third time lucky")
      assert panel(html) == nil
      assert stored!(task).assignee_id == world.viewer.id
    end

    test "is closed by Cancel, and nothing has run", %{view: view, world: world, task: task} do
      act(view, task.id, "reassign")
      type_in_panel(view, reason: "Never mind")

      html = cancel_panel(view)

      assert panel(html) == nil
      assert stored!(task).assignee_id == world.member.id
      assert stored!(task).internal_note == nil

      # opened again, it starts from the record
      assert [%{value: value}, %{name: "reason", value: ""}] =
               panel(act(view, task.id, "reassign")).fields

      assert value == world.member.id
    end

    test "that the resource refuses says so above the fields, and stays open",
         %{conn: conn, world: world, other: other} do
      # a member may reassign their own tasks only
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")
      act(view, other.id, "reassign")

      html = run_panel(view, assignee_id: world.member.id, reason: "I will take it")

      assert %{heading: "Reassign: File the report", errors: ["You are not allowed to do this."]} =
               panel(html)

      assert attribute(html, "#task-panel-errors", "role") == ["alert"]
      assert announcement(html) == "Reassign failed: You are not allowed to do this."
      assert stored!(other).assignee_id == nil
      assert action_failure(html, other.id) == nil
    end

    test "whose record is gone when it is run says so, and nothing crashes",
         %{view: view, task: task} do
      act(view, task.id, "reassign")
      Ash.destroy!(task, authorize?: false)

      html = run_panel(view, reason: "Too late")

      assert panel(html).errors == ["This record is no longer available."]
      assert panel(cancel_panel(view)) == nil
    end

    test "whose record is gone when its button is used opens no panel", %{view: view, task: task} do
      Ash.destroy!(task, authorize?: false)

      html = act(view, task.id, "reassign")

      assert panel(html) == nil
      assert announcement(html) == "Reassign failed: This record is no longer available."
    end

    test "is closed when the table reads again: its row may be another one by then",
         %{view: view, task: task} do
      assert panel(act(view, task.id, "reassign")) != nil

      view |> element("#task-head-title") |> render_click()
      html = render_async(view)

      assert titles(html) == ["File the report", "Write the report"]
      assert panel(html) == nil

      # what its form would send now runs nothing
      forge(view, "task", "panel_submit", %{"panel" => %{"reason" => "Late"}})

      assert stored!(task).internal_note == nil
    end
  end

  describe "an event sent by hand" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, 1, title: "Write the report", assignee_id: world.member.id)
      foreign = hd(world.other_tasks)
      %{conn: conn, world: world, task: task, foreign: foreign}
    end

    defp raw(view, event, params), do: forge(view, "task", event, params, on: :grid)

    test "for an action the table does not declare runs nothing", %{
      conn: conn,
      world: world,
      task: task
    } do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      # `update` and `reprioritise` are actions of the resource, and no row actions
      for name <- ["update", "reprioritise", "create", "read", "nothing", ""] do
        html = raw(view, "act", %{"row" => task.id, "action" => name})
        assert panel(html) == nil
        assert action_failure(html, task.id) == nil
      end

      assert stored!(task).internal_note == nil
      assert {:ok, %Task{status: :in_progress}} = stored(task)
    end

    test "for an action the person can never run is refused before anything is read",
         %{conn: conn, world: world, task: task} do
      {:ok, view, html} = conn |> log_in(world.viewer) |> live("/tasks")
      assert titles(html) == ["Write the report"]

      for name <- ["archive", "destroy", "reassign", "set_progress"] do
        assert panel(raw(view, "act", %{"row" => task.id, "action" => name})) == nil
      end

      assert {:ok, %Task{status: :in_progress}} = stored(task)
    end

    test "for a row that is not on the page runs nothing", %{
      conn: conn,
      world: world,
      task: task,
      foreign: foreign
    } do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      # a task of the other organization, by its key; and no key at all
      for key <- [foreign.id, "", "no-such-row"] do
        assert panel(raw(view, "act", %{"row" => key, "action" => "reassign"})) == nil
        raw(view, "act", %{"row" => key, "action" => "destroy"})
        raw(view, "dismiss", %{"row" => key})
      end

      assert {:ok, %Task{}} = stored(foreign)
      assert {:ok, %Task{}} = stored(task)
    end

    test "of a shape the table never sends changes nothing and crashes nothing",
         %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      for params <- [
            %{},
            %{"row" => task.id},
            %{"action" => "archive"},
            %{"row" => %{"id" => task.id}, "action" => "archive"},
            %{"row" => task.id, "action" => ["archive"]},
            %{"row" => task.id, "action" => %{"name" => "destroy"}},
            %{"row" => 1, "action" => 2}
          ],
          event <- ["act", "dismiss", "panel_validate", "panel_submit", "panel_cancel", "create"] do
        raw(view, event, params)
      end

      assert {:ok, %Task{status: :in_progress}} = stored(task)
      assert titles(render(view)) == ["Write the report"]
    end

    test "with values for fields the action does not take gives the action none of them",
         %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      act(view, task.id, "set_progress")

      html =
        send_panel(view, %{
          "panel" => %{
            "progress" => "55",
            # attributes of the task that `set_progress` does not accept
            "title" => "Hijacked",
            "status" => "done",
            "organization_id" => world.other_organization.id,
            "id" => foreign_id(world),
            "internal_note" => "by hand",
            "no_such_field" => "x"
          },
          "row" => foreign_id(world),
          "action" => "destroy"
        })

      assert panel(html) == nil

      assert %{progress: 55, title: "Write the report", status: :in_progress, internal_note: nil} =
               stored!(task)

      assert stored!(task).organization_id == world.organization.id
    end

    defp foreign_id(world), do: hd(world.other_tasks).id

    test "for a record the person may read, and that is not on the page they are shown, runs nothing",
         %{conn: conn, world: world, task: task} do
      elsewhere = task(world, 2, title: "Not shown", assignee_id: world.member.id)
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      # the filter leaves one row on the page
      html = filter(view, "task", "title", v: "Write")
      assert titles(html) == ["Write the report"]

      raw(view, "act", %{"row" => elsewhere.id, "action" => "archive"})
      raw(view, "act", %{"row" => elsewhere.id, "action" => "destroy"})
      assert panel(raw(view, "act", %{"row" => elsewhere.id, "action" => "reassign"})) == nil

      assert {:ok, %Task{status: :in_progress}} = stored(elsewhere)
      assert {:ok, %Task{status: :in_progress}} = stored(task)
    end
  end
end
