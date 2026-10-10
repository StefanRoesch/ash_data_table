defmodule DemoWeb.Tables.TaskEditTest do
  @moduledoc """
  Inline editing in the mounted table of `Demo.Tracker.Task` at `/tasks`.

  A cell's editor is opened, and its value typed, in the browser; the table's
  hook then sends one `save` event with the row, the column and the value as
  typed. These tests send that event as the hook does and read the page.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Task

  # One task of the world's first organization, reported by the admin.
  defp task(world, overrides) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          title: "Write the report",
          description: "Two pages at most.",
          status: :in_progress,
          priority: :medium,
          progress: 40,
          estimate_hours: Decimal.new("12.5"),
          billable?: false,
          due_on: ~D[2026-11-20],
          completed_at: nil,
          external_ref: "EXT-1",
          inserted_at: ~U[2026-01-01 12:00:00.000000Z],
          updated_at: ~U[2026-01-02 12:00:00.000000Z]
        ] ++ overrides
      )
    )
  end

  # The record as it is stored, whoever may see it.
  defp stored(task), do: Ash.get!(Task, task.id, authorize?: false)

  describe "what can be edited" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, [])
      {:ok, _view, html} = conn |> log_in(world.admin) |> live("/tasks")
      %{html: html, task: task}
    end

    test "cells of columns no action can save are marked read-only, the others are not",
         %{html: html, task: task} do
      editable =
        ~w(title status priority progress estimate_hours billable? due_on completed_at description)

      for field <- editable do
        assert attribute(html, cell(task.id, field), "aria-readonly") == [], field
      end

      for field <- ~w(overdue? comment_count headline external_ref inserted_at) do
        assert attribute(html, cell(task.id, field), "aria-readonly") == ["true"], field
      end
    end

    test "every editable column has an editor of its type, and no other column has one",
         %{html: html} do
      assert editors(html, "task") ==
               ~w(title status priority progress estimate_hours billable? due_on completed_at description tags checks project assignee)

      assert editor(html, "task", "title") == %{control: "textarea", choices: nil, confirm: nil}
      assert editor(html, "task", "description").control == "textarea"
      # a slider, which is the column's component (see `task_components_test.exs`)
      assert editor(html, "task", "progress") == %{control: "range", choices: nil, confirm: nil}
      assert editor(html, "task", "estimate_hours").control == "number"
      assert editor(html, "task", "billable?").control == "checkbox"
      assert editor(html, "task", "due_on").control == "date"
      assert editor(html, "task", "completed_at").control == "datetime-local"

      assert editor(html, "task", "priority") == %{
               control: "select",
               choices: ["Low", "Medium", "High", "Urgent"],
               confirm: nil
             }

      assert editor(html, "task", "external_ref") == nil
      assert editor(html, "task", "overdue?") == nil
    end
  end

  describe "saving a cell" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, [])
      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")
      %{conn: conn, view: view, task: task, world: world}
    end

    test "of text shows the new value in the row, and again when the page is reopened",
         %{conn: conn, view: view, task: task} do
      html = save(view, task.id, "title", "Write the summary")

      assert text(html, cell(task.id, "title")) == "Write the summary"

      {:ok, _view, html} = live(conn, "/tasks")
      assert text(html, cell(task.id, "title")) == "Write the summary"
    end

    test "of a number", %{conn: conn, view: view, task: task} do
      html = save(view, task.id, "estimate_hours", "7.25")

      assert text(html, cell(task.id, "estimate_hours")) == "7.25 h"

      {:ok, _view, html} = live(conn, "/tasks")
      assert text(html, cell(task.id, "estimate_hours")) == "7.25 h"
    end

    test "of a boolean", %{conn: conn, view: view, task: task} do
      html = save(view, task.id, "billable?", "true")

      assert text(html, cell(task.id, "billable?")) == "✓Yes"

      {:ok, view, html} = live(conn, "/tasks")
      assert text(html, cell(task.id, "billable?")) == "✓Yes"

      html = save(view, task.id, "billable?", "false")
      assert text(html, cell(task.id, "billable?")) == "–No"
    end

    test "of a date", %{conn: conn, view: view, task: task} do
      html = save(view, task.id, "due_on", "2026-12-24")

      assert text(html, cell(task.id, "due_on")) == "2026-12-24"

      {:ok, _view, html} = live(conn, "/tasks")
      assert text(html, cell(task.id, "due_on")) == "2026-12-24"
    end

    test "of a datetime, as a datetime input gives it", %{conn: conn, view: view, task: task} do
      html = save(view, task.id, "completed_at", "2026-10-05T09:30:15")

      assert text(html, cell(task.id, "completed_at")) == "2026-10-05T09:30:15"

      # a browser leaves the seconds out when they are zero
      html = save(view, task.id, "completed_at", "2026-10-06T14:45")
      assert text(html, cell(task.id, "completed_at")) == "2026-10-06T14:45:00"

      {:ok, _view, html} = live(conn, "/tasks")
      assert text(html, cell(task.id, "completed_at")) == "2026-10-06T14:45:00"
    end

    test "of a choice shows the label of the value chosen", %{conn: conn, view: view, task: task} do
      html = save(view, task.id, "status", "in_review")

      assert text(html, cell(task.id, "status")) == "In review"

      {:ok, _view, html} = live(conn, "/tasks")
      assert text(html, cell(task.id, "status")) == "In review"
    end
  end

  describe "the action that saves" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, status: :todo, progress: 0, internal_note: nil)
      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")
      %{conn: conn, view: view, task: task}
    end

    test "is the column's own: reporting progress starts a task that is still to do",
         %{view: view, task: task} do
      html = save(view, task.id, "progress", "10")

      assert text(html, cell(task.id, "progress")) == "10"
      # `set_progress` does that, `update` does not
      assert text(html, cell(task.id, "status")) == "In progress"
    end

    test "is the column's own: a change of priority leaves the trace of `reprioritise`",
         %{view: view, task: task} do
      html = save(view, task.id, "priority", "urgent")

      assert text(html, cell(task.id, "priority")) == "Urgent"
      assert stored(task).internal_note == "Reprioritised"
    end

    test "is the table's for the other columns: neither trace appears", %{view: view, task: task} do
      html = save(view, task.id, "title", "Write the summary")

      assert text(html, cell(task.id, "status")) == "To do"
      assert stored(task).internal_note == nil
    end
  end

  describe "a value that is the one the cell already shows" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, internal_note: nil)
      %{world: world, conn: conn, task: task}
    end

    # `reprioritise` leaves its trace whenever it runs, whatever the value.
    test "runs no action", %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      html = save(view, task.id, "priority", "medium")

      assert text(html, cell(task.id, "priority")) == "Medium"
      assert stored(task).internal_note == nil

      save(view, task.id, "priority", "high")
      assert stored(task).internal_note == "Reprioritised"
    end

    test "runs no action for any type of cell: the row is shown as it is, without an error",
         %{conn: conn, world: world, task: task} do
      # a viewer may run no update action at all, so any action run would be refused
      {:ok, view, _html} = conn |> log_in(world.viewer) |> live("/tasks")

      for {field, typed} <- [
            {"title", "Write the report"},
            {"status", "in_progress"},
            {"progress", "40"},
            {"billable?", "false"},
            {"due_on", "2026-11-20"},
            {"completed_at", ""},
            {"description", "Two pages at most."}
          ] do
        html = save(view, task.id, field, typed)
        assert attribute(html, cell(task.id, field), "aria-invalid") == [], field
      end
    end
  end

  describe "empty input" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, [])
      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")
      %{conn: conn, view: view, task: task}
    end

    test "is sent as typed and empties a field that can be empty", %{
      conn: conn,
      view: view,
      task: task
    } do
      for field <- ["due_on", "estimate_hours", "description"] do
        html = save(view, task.id, field, "")

        assert text(html, cell(task.id, field)) == "", field
        assert failure(html, task.id, field) == nil, field
      end

      assert %{due_on: nil, estimate_hours: nil, description: nil} = stored(task)

      {:ok, _view, html} = live(conn, "/tasks")
      assert text(html, cell(task.id, "due_on")) == ""
    end

    test "is refused by the action for a field that cannot be empty", %{view: view, task: task} do
      html = save(view, task.id, "title", "")

      assert failure(html, task.id, "title") == %{shown: "", message: "is required"}
      assert stored(task).title == "Write the report"
    end
  end

  describe "a save the action refuses" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, [])
      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")
      %{conn: conn, view: view, task: task, world: world}
    end

    test "for the value itself marks the cell, keeps what was typed and shows the action's message",
         %{conn: conn, view: view, task: task} do
      html = save(view, task.id, "title", "ab")

      assert failure(html, task.id, "title") == %{
               shown: "ab",
               message: "length must be greater than or equal to 3"
             }

      # nothing is saved
      assert stored(task).title == "Write the report"
      {:ok, _view, html} = live(conn, "/tasks")
      assert text(html, cell(task.id, "title")) == "Write the report"
      assert failure(html, task.id, "title") == nil
    end

    test "for a value that is not one of the column's type shows the action's message",
         %{view: view, task: task} do
      html = save(view, task.id, "progress", "plenty")

      assert failure(html, task.id, "progress") == %{shown: "plenty", message: "is invalid"}
      assert stored(task).progress == 40
    end

    test "because of another field shows that on the cell that was edited, naming the field",
         %{view: view, task: task} do
      # a task can only be done with progress 100, and this one has 40
      html = save(view, task.id, "status", "done")

      assert failure(html, task.id, "status") == %{
               shown: "Done",
               message: "Progress: must be 100 when the task is done"
             }

      assert failure(html, task.id, "progress") == nil
      assert text(html, cell(task.id, "progress")) == "40"
      assert stored(task).status == :in_progress
    end

    # A person who may run no update action is offered no editing, and an
    # event sent all the same is not run: see
    # `DemoWeb.Tables.TaskAuthorizationTest`.

    test "because the person may not change this record shows that on the cell",
         %{conn: conn, world: world, task: task} do
      # a member may change the tasks they are assigned to or reported: not this one
      mine = task(world, title: "My own task", assignee_id: world.member.id)
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      html = save(view, task.id, "progress", "90")

      assert failure(html, task.id, "progress") == %{
               shown: "90",
               message: "You are not allowed to change this."
             }

      assert stored(task).progress == 40

      html = save(view, mine.id, "progress", "90")

      assert failure(html, mine.id, "progress") == nil
      assert text(html, cell(mine.id, "progress")) == "90"
      assert stored(mine).progress == 90
    end

    test "is announced to screen readers when it happens", %{view: view, task: task} do
      html = save(view, task.id, "title", "ab")

      assert text(html, "#task-status") ==
               "Title was not saved: length must be greater than or equal to 3"

      assert attribute(html, "#task-status", "aria-live") == ["polite"]
    end
  end

  describe "after a save has failed" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, [])
      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")
      save(view, task.id, "title", "ab")
      %{conn: conn, view: view, task: task}
    end

    test "a value the action accepts is saved and the cell is no longer marked",
         %{view: view, task: task} do
      html = save(view, task.id, "title", "Write the summary")

      assert failure(html, task.id, "title") == nil
      assert text(html, cell(task.id, "title")) == "Write the summary"
      assert stored(task).title == "Write the summary"
    end

    test "another value the action refuses replaces what the cell shows", %{
      view: view,
      task: task
    } do
      html = save(view, task.id, "title", "x")

      assert failure(html, task.id, "title") == %{
               shown: "x",
               message: "length must be greater than or equal to 3"
             }
    end

    test "typing the saved value again runs nothing and the cell is no longer marked",
         %{view: view, task: task} do
      html = save(view, task.id, "title", "Write the report")

      assert failure(html, task.id, "title") == nil
      assert text(html, cell(task.id, "title")) == "Write the report"
    end

    test "giving the edit up, as Escape on the cell does, shows the saved value again",
         %{view: view, task: task} do
      html = discard(view, task.id, "title")

      assert failure(html, task.id, "title") == nil
      assert text(html, cell(task.id, "title")) == "Write the report"
      assert stored(task).title == "Write the report"
    end

    test "the cell stays marked when another cell of its row is saved", %{view: view, task: task} do
      html = save(view, task.id, "progress", "55")

      assert text(html, cell(task.id, "progress")) == "55"

      assert failure(html, task.id, "title") == %{
               shown: "ab",
               message: "length must be greater than or equal to 3"
             }

      # and when another cell of the row fails too, each keeps its own
      html = save(view, task.id, "status", "done")

      assert failure(html, task.id, "title").shown == "ab"
      assert failure(html, task.id, "status").shown == "Done"

      # giving one up leaves the other
      html = discard(view, task.id, "status")

      assert failure(html, task.id, "status") == nil
      assert text(html, cell(task.id, "status")) == "In progress"
      assert text(html, cell(task.id, "progress")) == "55"
      assert failure(html, task.id, "title").shown == "ab"
    end

    test "is forgotten when the page is read again", %{view: view, task: task} do
      view |> element("#task-head-title") |> render_click()
      html = render_async(view)

      assert failure(html, task.id, "title") == nil
      assert text(html, cell(task.id, "title")) == "Write the report"
    end
  end

  describe "the row after a save" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, due_on: ~D[2020-01-31])

      Generator.generate_many(
        Generator.comment(
          task_id: task.id,
          organization_id: world.organization.id,
          author_id: world.admin.id
        ),
        2
      )

      conn = log_in(conn, world.admin)
      {:ok, view, html} = live(conn, "/tasks")
      %{conn: conn, view: view, html: html, task: task, world: world}
    end

    test "still has its calculations and its aggregate, computed from the new values",
         %{view: view, html: html, task: task} do
      assert text(html, cell(task.id, "headline")) == "Medium: Write the report (40%)"
      assert text(html, cell(task.id, "overdue?")) == "✓Yes"
      assert text(html, cell(task.id, "comment_count")) == "2"

      html = save(view, task.id, "title", "Write the summary")

      assert text(html, cell(task.id, "headline")) == "Medium: Write the summary (40%)"
      assert text(html, cell(task.id, "overdue?")) == "✓Yes"
      assert text(html, cell(task.id, "comment_count")) == "2"

      html = save(view, task.id, "due_on", "2099-01-31")

      assert text(html, cell(task.id, "overdue?")) == "–No"
      assert text(html, cell(task.id, "headline")) == "Medium: Write the summary (40%)"
      assert text(html, cell(task.id, "comment_count")) == "2"
    end

    test "still has them when the save failed", %{view: view, task: task} do
      html = save(view, task.id, "title", "ab")

      assert text(html, cell(task.id, "headline")) == "Medium: Write the report (40%)"
      assert text(html, cell(task.id, "overdue?")) == "✓Yes"
      assert text(html, cell(task.id, "comment_count")) == "2"
    end
  end

  describe "a field hidden from the person on some rows" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      # The member may change both tasks: they reported them. They may see the
      # estimate only of the one assigned to them.
      theirs =
        task(world,
          title: "Assigned to me",
          reporter_id: world.member.id,
          assignee_id: world.member.id
        )

      other =
        task(world, title: "Assigned to nobody", reporter_id: world.member.id, assignee_id: nil)

      {:ok, view, html} = conn |> log_in(world.member) |> live("/tasks")
      %{view: view, html: html, theirs: theirs, other: other}
    end

    test "is not editable where it is hidden, and editable where it is shown",
         %{html: html, theirs: theirs, other: other} do
      assert text(html, cell(other.id, "estimate_hours")) == "Not available"
      assert attribute(html, cell(other.id, "estimate_hours"), "aria-readonly") == ["true"]

      assert text(html, cell(theirs.id, "estimate_hours")) == "12.5 h"
      assert attribute(html, cell(theirs.id, "estimate_hours"), "aria-readonly") == []
    end

    test "is still hidden in the row after another cell of that row was saved",
         %{view: view, other: other} do
      html = save(view, other.id, "title", "Still assigned to nobody")

      assert text(html, cell(other.id, "title")) == "Still assigned to nobody"
      assert text(html, cell(other.id, "estimate_hours")) == "Not available"
      assert attribute(html, cell(other.id, "estimate_hours"), "aria-readonly") == ["true"]
    end

    test "is still hidden in the row after the save of another cell failed",
         %{view: view, other: other} do
      html = save(view, other.id, "title", "ab")

      assert failure(html, other.id, "title").shown == "ab"
      assert text(html, cell(other.id, "estimate_hours")) == "Not available"
    end

    test "cannot be changed where it is hidden, whatever is sent", %{view: view, other: other} do
      html = save(view, other.id, "estimate_hours", "99")

      assert text(html, cell(other.id, "estimate_hours")) == "Not available"
      assert Decimal.equal?(stored(other).estimate_hours, Decimal.new("12.5"))
    end

    test "can be changed where it is shown", %{view: view, theirs: theirs} do
      html = save(view, theirs.id, "estimate_hours", "99")

      assert text(html, cell(theirs.id, "estimate_hours")) == "99 h"
      assert Decimal.equal?(stored(theirs).estimate_hours, Decimal.new("99"))
    end
  end

  describe "a row whose new value no longer fits what the page shows" do
    setup %{conn: conn} do
      world = world(tasks: 0)

      [apple, banana, cherry] =
        for {title, day} <- [{"Apple", 1}, {"Banana", 2}, {"Cherry", 3}] do
          task(world,
            title: title,
            inserted_at: DateTime.new!(Date.new!(2026, 1, day), ~T[12:00:00])
          )
        end

      conn = log_in(conn, world.admin)
      %{conn: conn, apple: apple, banana: banana, cherry: cherry}
    end

    test "stays in its place under a sort, until the page is read again",
         %{conn: conn, banana: banana} do
      {:ok, view, html} = live(conn, "/tasks?task[sort]=title")
      assert column(html, "task", "title") == ["Apple", "Banana", "Cherry"]

      html = save(view, banana.id, "title", "Zucchini")
      assert column(html, "task", "title") == ["Apple", "Zucchini", "Cherry"]

      {:ok, _view, html} = live(conn, "/tasks?task[sort]=title")
      assert column(html, "task", "title") == ["Apple", "Cherry", "Zucchini"]
    end

    test "stays on the page under a filter it no longer matches, until the page is read again",
         %{conn: conn, banana: banana} do
      {:ok, view, html} = live(conn, "/tasks?task[f][status]=in_progress&task[sort]=title")
      assert column(html, "task", "title") == ["Apple", "Banana", "Cherry"]

      html = save(view, banana.id, "status", "in_review")

      assert column(html, "task", "title") == ["Apple", "Banana", "Cherry"]
      assert column(html, "task", "status") == ["In progress", "In review", "In progress"]

      # it can still be edited where it stands
      html = save(view, banana.id, "title", "Banana bread")
      assert column(html, "task", "title") == ["Apple", "Banana bread", "Cherry"]

      {:ok, _view, html} = live(conn, "/tasks?task[f][status]=in_progress&task[sort]=title")
      assert column(html, "task", "title") == ["Apple", "Cherry"]
    end

    test "keeps its row index", %{conn: conn, banana: banana} do
      {:ok, view, html} = live(conn, "/tasks?task[sort]=title")
      assert attribute(html, "#task-row-#{banana.id}-r", "aria-rowindex") == ["4"]

      html = save(view, banana.id, "title", "Zucchini")
      assert attribute(html, "#task-row-#{banana.id}-r", "aria-rowindex") == ["4"]
    end
  end

  describe "a record that is gone when its cell is saved" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, [])
      other = task(world, title: "Another task")
      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")
      %{conn: conn, view: view, task: task, other: other, world: world}
    end

    test "because it was deleted: nothing is saved, and the person is told on the cell",
         %{view: view, task: task, other: other} do
      Ash.destroy!(task, authorize?: false)

      html = save(view, task.id, "title", "Write the summary")

      # The row stays as it was read: there is no record to show it from. The
      # hook marks the cell with the message the server answers with.
      assert_reply view, %{ok: false, error: "This record is no longer available."}

      assert text(html, "#task-status") ==
               "Title was not saved: This record is no longer available."

      assert text(html, cell(task.id, "title")) == "Write the report"

      # the rest of the page works on
      html = save(view, other.id, "title", "Yet another task")
      assert text(html, cell(other.id, "title")) == "Yet another task"
    end

    test "because the person can no longer read it: nothing is saved",
         %{view: view, task: task, world: world} do
      # the task moves to the other organization: it exists, but not for this admin
      Ash.Seed.update!(stored(task), %{organization_id: world.other_organization.id})

      html = save(view, task.id, "title", "Write the summary")

      assert_reply view, %{ok: false, error: "This record is no longer available."}

      assert text(html, "#task-status") ==
               "Title was not saved: This record is no longer available."

      assert stored(task).title == "Write the report"
    end
  end

  describe "somebody of another organization" do
    test "cannot change a task by sending its id", %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      task = task(world, [])

      project =
        Generator.generate(Generator.project(organization_id: world.other_organization.id))

      theirs =
        Generator.generate(
          Generator.task(
            organization_id: world.other_organization.id,
            project_id: project.id,
            reporter_id: world.outsider.id,
            title: "A Globex task"
          )
        )

      {:ok, view, html} = conn |> log_in(world.outsider) |> live("/tasks")
      assert column(html, "task", "title") == ["A Globex task"]

      html = save(view, task.id, "title", "Taken over")

      assert column(html, "task", "title") == ["A Globex task"]
      assert stored(task).title == "Write the report"

      # their own they can
      html = save(view, theirs.id, "title", "A better Globex task")
      assert column(html, "task", "title") == ["A better Globex task"]
    end
  end

  describe "a column that asks before saving" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, [])
      conn = log_in(conn, world.admin)
      {:ok, view, html} = live(conn, "/tasks")
      %{conn: conn, view: view, html: html, task: task}
    end

    test "gives its question to its editor, and the table has one dialog to ask it in",
         %{html: html} do
      assert editor(html, "task", "status") == %{
               control: "select",
               choices: ["Backlog", "To do", "In progress", "In review", "Done", "Archived"],
               confirm: "Change the state of this task?"
             }

      assert attribute(html, "#task dialog", "id") == ["task-dialog"]
      # named by the question, which the hook puts into it
      assert attribute(html, "#task-dialog", "aria-labelledby") == ["task-dialog-question"]
      assert text(html, "#task-dialog-question") == ""
      assert text(html, "#task-dialog button[value='cancel']") == "Cancel"
      assert text(html, "#task-dialog button[value='confirm']") == "Confirm"
    end

    test "saves once the person has confirmed, which is when the hook sends the value",
         %{view: view, task: task} do
      html = save(view, task.id, "status", "in_review")

      assert text(html, cell(task.id, "status")) == "In review"
      assert stored(task).status == :in_review
    end
  end

  describe "an event for a cell that cannot be edited" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, [])
      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")
      %{conn: conn, view: view, task: task}
    end

    test "in a column switched off with `update_action false` saves nothing",
         %{view: view, task: task} do
      html = save(view, task.id, "external_ref", "EXT-2")

      assert text(html, cell(task.id, "external_ref")) == "EXT-1"
      assert stored(task).external_ref == "EXT-1"
    end

    test "in a column no action accepts, a calculation or an unknown column saves nothing",
         %{view: view, task: task} do
      for field <- ["inserted_at", "headline", "comment_count", "internal_note", "nope"] do
        html = save(view, task.id, field, "2020-01-01T00:00:00")
        assert text(html, cell(task.id, "title")) == "Write the report", field
      end

      assert stored(task).inserted_at == ~U[2026-01-01 12:00:00.000000Z]
      assert stored(task).internal_note == task.internal_note
    end

    test "in a row that is not on the page, or with no value, saves nothing",
         %{view: view, task: task} do
      html = save(view, "00000000-0000-4000-8000-000000000000", "title", "Nobody's task")
      assert column(html, "task", "title") == ["Write the report"]

      html = view |> element("#task-grid") |> render_hook("save", %{"row" => task.id})
      assert column(html, "task", "title") == ["Write the report"]

      html =
        view
        |> element("#task-grid")
        |> render_hook("save", %{"row" => task.id, "column" => "title", "value" => %{"a" => 1}})

      assert column(html, "task", "title") == ["Write the report"]
      assert stored(task).title == "Write the report"
    end
  end

  describe "a table without an update action" do
    test "a table without an update action offers no editing: nothing is marked and there are no editors",
         %{conn: conn} do
      # the demo's one table that names no update action is the people's
      # (`Demo.Tracker.User`), which is only ever seen nested: here as the
      # task's reporter, for the admin, who may update a person
      world = world(tasks: 0)
      task = task(world, [])
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      expand(view, task.id)
      html = toggle(view, task.id, "reporter")
      id = nested(task.id, "reporter")

      assert column(html, id, "name") == [world.admin.name]
      assert attribute(html, "[id='#{id}-table'] td", "aria-readonly") == []
      assert editors(html, id) == []
      assert attribute(html, "[id='#{id}'] template", "id") == []
      assert attribute(html, "[id='#{id}'] dialog", "id") == []

      # and the event the table would send saves nothing
      html = save(view, id, world.admin.id, "name", "Renamed")
      assert column(html, id, "name") == [world.admin.name]

      assert Ash.get!(Demo.Tracker.User, world.admin.id, authorize?: false).name ==
               world.admin.name
    end
  end
end
