defmodule DemoWeb.Tables.TaskBulkTest do
  @moduledoc """
  Row selection and the actions on the selected rows, in the mounted table
  of `Demo.Tracker.Task` at `/tasks`.

  Which rows are selected is known in the browser alone: the table's hook
  keeps it, and tells the server when a button of the line above the grid
  is used. These tests send what the hook sends (`bulk`, and `bulk_run` once
  the question is answered), fill in the panel's form as a person does, and
  read the page and the database. What the hook itself does is in the
  browser tests (`e2e/selection.spec.ts`).
  """
  use DemoWeb.ConnCase, async: true

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
          title: "Task #{String.pad_leading("#{day}", 2, "0")}",
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

  # every task there is, of whichever organization, by its title
  defp states do
    Task
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.title, &1.status})
  end

  # those of the world's first organization
  defp states(world) do
    Task
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&(&1.organization_id == world.organization.id))
    |> Map.new(&{&1.title, &1.status})
  end

  describe "the boxes" do
    setup do
      world = world(tasks: 0)
      %{world: world, task: task(world, 1, [])}
    end

    test "are the first column of the grid: a box in every row, one in the header for the page, and an empty filter cell",
         %{conn: conn, world: world, task: task} do
      {:ok, _view, html} = conn |> log_in(world.admin) |> live("/tasks")

      # the boxes, the expanders, the nineteen columns of the table, the actions
      assert attribute(html, "#task-table", "aria-colcount") == ["23"]
      assert attribute(html, "#task-table", "aria-multiselectable") == ["true"]
      assert attribute(html, "#task-grid", "data-select") == ["multi"]
      assert attribute(html, "#task-grid", "data-lead") == ["2"]

      assert attribute(html, "#task-head-row > th:first-child", "id") == ["task-select-head"]
      assert attribute(html, "#task-select-head", "role") == ["columnheader"]
      assert attribute(html, "#task-select-head", "aria-colindex") == ["1"]

      assert attribute(html, "#task-select-head > input[type=checkbox]", "aria-label") ==
               ["Select all rows of this page"]

      assert attribute(html, "#task-filter-row > td:first-child", "id") == ["task-select-filter"]
      assert text(html, "#task-select-filter") == ""
      assert attribute(html, "#task-select-filter", "aria-colindex") == ["1"]

      assert attribute(html, "[id='task-row-#{task.id}-r'] > td:first-child", "id") ==
               ["task-row-#{task.id}-s"]

      assert attribute(html, "[id='task-row-#{task.id}-s']", "role") == ["gridcell"]
      assert attribute(html, "[id='task-row-#{task.id}-s']", "aria-colindex") == ["1"]
      assert attribute(html, box(task.id), "aria-label") == ["Select row"]
      # neither box is a tab stop: the grid is one
      assert attribute(html, box(task.id), "tabindex") == ["-1"]
      assert attribute(html, "#task-select-head > input", "tabindex") == ["-1"]

      # the columns after it stand one further: the expander, the first
      # column, the actions
      assert attribute(html, "[id='task-row-#{task.id}-e']", "aria-colindex") == ["2"]
      assert attribute(html, "#task-expander-head", "aria-colindex") == ["2"]
      assert attribute(html, cell(task.id, "title"), "aria-colindex") == ["3"]
      assert attribute(html, actions_cell(task.id), "aria-colindex") == ["23"]
    end

    test "say nothing about which rows are selected: that is the hook's, and no row is sent again for it",
         %{conn: conn, world: world, task: task} do
      {:ok, _view, html} = conn |> log_in(world.admin) |> live("/tasks")

      assert attribute(html, box(task.id), "checked") == []
      assert attribute(html, "[id='task-row-#{task.id}-r']", "aria-selected") == []
      # a row whose key is its primary key as it is written says no more of it
      assert attribute(html, "[id='task-row-#{task.id}']", "data-key") == []
    end

    test "are there for whoever can run an action on several rows, and for nobody else",
         %{conn: conn, world: world, task: task} do
      # a member may run the actions on their own tasks
      {:ok, _view, html} = conn |> log_in(world.member) |> live("/tasks")
      assert attribute(html, box(task.id), "aria-label") == ["Select row"]
      assert attribute(html, "#task-table", "aria-multiselectable") == ["true"]

      # a viewer can run none: no boxes, no line, and the grid says nothing of selecting
      {:ok, _view, html} = conn |> log_in(world.viewer) |> live("/tasks")
      assert titles(html) == ["Task 01"]
      assert attribute(html, "#task-select-head", "id") == []
      assert attribute(html, "[id='task-row-#{task.id}-s']", "id") == []
      assert attribute(html, "#task-table", "aria-multiselectable") == []
      assert attribute(html, "#task-grid", "data-select") == []
      assert selection(html) == nil
      # the expanders and the sixteen columns a viewer has, as before
      assert attribute(html, "#task-table", "aria-colcount") == ["18"]
      assert attribute(html, "[id='task-row-#{task.id}-e']", "aria-colindex") == ["1"]
    end
  end

  describe "the line above the grid" do
    setup do
      world = world(tasks: 0)
      for day <- 1..3, do: task(world, day, [])
      %{world: world}
    end

    test "has a button to select all that match, one to clear, and one per action that runs on several rows",
         %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.admin) |> live("/tasks")

      assert %{
               buttons: [
                 "Select all 3 that match",
                 "Clear selection",
                 "Archive",
                 "Reassign",
                 "Set progress",
                 "Destroy"
               ],
               selected: "{n} selected",
               all: "All 3 that match are selected"
             } = selection(html)

      assert attribute(html, "#task-selection", "role") == ["group"]
      assert attribute(html, "#task-selection", "aria-label") == ["Selected rows"]
      # the count is a live region, which the hook fills
      assert attribute(html, "#task-selected", "role") == ["status"]
      assert text(html, "#task-selected") == ""
      # hidden until the hook knows of a selection
      assert attribute(html, "#task-selection-controls", "hidden") == [""]
      assert attribute(html, "#task-select-all", "hidden") == [""]
      # the one that deletes says so, for the colour of the answer in its question
      assert attribute(html, "#task-bulk-destroy", "data-destructive") == [""]
      assert attribute(html, "#task-bulk-archive", "data-destructive") == []
    end

    test "offers all that match only when there is more than the page shows",
         %{conn: conn, world: world} do
      conn = log_in(conn, world.admin)

      {:ok, view, html} = live(conn, "/tasks")
      refute selection(html).more?

      for day <- 4..30, do: task(world, day, [])
      {:ok, _view, html} = live(conn, "/tasks")
      assert %{more?: true, buttons: ["Select all 30 that match" | _]} = selection(html)

      # under a filter that leaves less than a page, there is no more
      html = filter(view, "task", "title", v: "Task 0")
      assert %{more?: false, buttons: ["Select all 9 that match" | _]} = selection(html)
    end

    test "stands for the filters, so that the hook gives a selection up when they change",
         %{conn: conn, world: world} do
      {:ok, view, html} = conn |> log_in(world.admin) |> live("/tasks")
      [scope] = attribute(html, "#task-selection", "data-scope")

      # another sort, the same selection
      html = view |> element("#task-head-title") |> render_click()
      assert attribute(html, "#task-selection", "data-scope") == [scope]

      html = filter(view, "task", "title", v: "Task 01")
      assert [filtered] = attribute(html, "#task-selection", "data-scope")
      assert filtered != scope
    end

    test "has the buttons of the actions a person can ever run", %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.member) |> live("/tasks")

      assert ["Select all 3 that match", "Clear selection" | actions] = selection(html).buttons
      assert actions == ["Archive", "Reassign", "Set progress", "Destroy"]
    end
  end

  describe "using a button of the line" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      tasks = for day <- 1..3, do: task(world, day, [])
      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")

      %{conn: conn, view: view, world: world, tasks: tasks}
    end

    test "runs nothing: the answer is the question to ask first, with the number of records",
         %{view: view, world: world, tasks: [first, second, third]} do
      html = bulk(view, "archive", [first.id])
      assert_reply view, %{ask: "Run “Archive” on 1 record?"}

      bulk(view, "archive", [first.id, second.id, third.id])
      assert_reply view, %{ask: "Run “Archive” on 3 records?"}

      # a row that is named twice is one row
      bulk(view, "archive", [first.id, first.id])
      assert_reply view, %{ask: "Run “Archive” on 1 record?"}

      assert panel(html) == nil
      assert bulk_result(html) == nil

      assert states(world) == %{
               "Task 01" => :in_progress,
               "Task 02" => :in_progress,
               "Task 03" => :in_progress
             }
    end

    test "asks the action's own question where it has one, and the number follows it",
         %{view: view, tasks: [first, second, _third]} do
      bulk(view, "destroy", [first.id, second.id])

      assert_reply view, %{
        ask: "Delete this task? This cannot be undone. 2 records are selected."
      }

      bulk(view, "destroy", [first.id])
      assert_reply view, %{ask: "Delete this task? This cannot be undone. 1 record is selected."}
    end

    test "for all that match, the number is what the table counted", %{view: view} do
      bulk(view, "archive", :all)
      assert_reply view, %{ask: "Run “Archive” on 3 records?"}

      filter(view, "task", "title", v: "Task 01")
      bulk(view, "destroy", :all)
      assert_reply view, %{ask: "Delete this task? This cannot be undone. 1 record is selected."}
    end

    test "opens the panel of an action with inputs, headed by the action and the number, with empty fields",
         %{view: view, tasks: [first, second, _third]} do
      html = bulk(view, "reassign", [first.id, second.id])
      assert_reply view, %{panel: true}

      assert %{
               heading: "Reassign: 2 records",
               submit: "Run",
               errors: [],
               fields: [
                 %{
                   name: "assignee_id",
                   label: "Assignee",
                   control: "reference",
                   value: "",
                   chosen: nil,
                   required?: false
                 },
                 %{name: "reason", label: "Reason", value: "", required?: true}
               ]
             } = panel(html)

      # the question is the panel's, asked when "Run" is used
      assert attribute(html, "#task-panel", "data-question") == ["Run “Reassign” on 2 records?"]

      cancel_panel(view)
      html = bulk(view, "set_progress", :all)
      assert %{heading: "Set progress: 3 records", fields: [%{name: "progress"}]} = panel(html)

      assert attribute(html, "#task-panel", "data-question") == [
               "Run “Set progress” on 3 records?"
             ]
    end

    test "answers nothing for what is no action on several rows, and for no selection",
         %{view: view, tasks: [first | _]} do
      for {action, selection} <- [
            # no action of the table, a create, an action of one cell
            {"nothing", [first.id]},
            {"create", [first.id]},
            {"reprioritise", [first.id]},
            {"update", [first.id]},
            # nothing selected
            {"archive", []}
          ] do
        html = bulk(view, action, selection)
        assert_reply view, %{ok: false}
        assert panel(html) == nil
      end

      # events of another shape
      for params <- [%{}, %{"action" => "archive"}, %{"action" => 1, "rows" => [first.id]}] do
        view |> element("#task-grid") |> render_hook("bulk", params)
        assert_reply view, %{ok: false}
        view |> element("#task-grid") |> render_hook("bulk_run", params)
      end

      assert stored!(first).status == :in_progress
    end
  end

  describe "an action on the selected rows" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      tasks = for day <- 1..4, do: task(world, day, [])
      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")

      %{conn: conn, view: view, world: world, tasks: tasks}
    end

    test "runs on exactly those records, says how many were done, and reads the table again",
         %{view: view, world: world, tasks: [first, second, third, fourth]} do
      html = run_bulk(view, "archive", [second.id, fourth.id])

      assert states(world) == %{
               "Task 01" => :in_progress,
               "Task 02" => :archived,
               "Task 03" => :in_progress,
               "Task 04" => :archived
             }

      assert bulk_result(html) == %{summary: "Archive: 2 done.", failures: []}
      assert announcement(html) == "Archive: 2 done."
      # nothing failed: no row stays selected
      assert_push_event view, "ash_table:bulk", %{table: "task", failed: []}

      # the rows are shown as they are now
      assert text(html, cell(second.id, "status")) == "Archived"
      assert text(html, cell(fourth.id, "status")) == "Archived"
      assert text(html, cell(first.id, "status")) == "In progress"
      assert text(html, cell(third.id, "status")) == "In progress"
      assert attribute(html, "#task-table", "aria-busy") == []
    end

    test "a destroy takes the records away, and the total follows",
         %{view: view, tasks: [first, second, third, fourth]} do
      html = run_bulk(view, "destroy", [first.id, third.id])

      assert {:ok, nil} = stored(first)
      assert {:ok, nil} = stored(third)
      assert {:ok, %Task{}} = stored(second)
      assert {:ok, %Task{}} = stored(fourth)

      assert bulk_result(html) == %{summary: "Destroy: 2 done.", failures: []}
      assert titles(html) == ["Task 04", "Task 02"]
      assert text(html, "#task-range") == "1–2 of 2"
    end

    test "runs on rows of other pages too: a selection outlives its page",
         %{conn: conn, world: world, tasks: tasks} do
      more = for day <- 5..30, do: task(world, day, [])
      {:ok, view, html} = live(conn, "/tasks")

      # the first page holds the 25 newest
      oldest = hd(tasks)
      refute "Task 01" in titles(html)

      html = run_bulk(view, "archive", [oldest.id, List.last(more).id])

      assert bulk_result(html).summary == "Archive: 2 done."
      assert stored!(oldest).status == :archived
      assert stored!(List.last(more)).status == :archived
      assert Enum.count(states(), fn {_title, status} -> status == :archived end) == 2
    end

    test "the result stays through a sort and a page, and goes when the selection or the filters change",
         %{view: view, tasks: [first | _]} do
      html = run_bulk(view, "archive", [first.id])
      assert bulk_result(html).summary == "Archive: 1 done."

      html = view |> element("#task-head-title") |> render_click()
      assert bulk_result(html).summary == "Archive: 1 done."

      # the hook says that the person has selected something else
      html = view |> element("#task-grid") |> render_hook("bulk_seen", %{})
      assert bulk_result(html) == nil

      run_bulk(view, "archive", [first.id])
      html = filter(view, "task", "title", v: "Task")
      assert bulk_result(html) == nil
    end
  end

  describe "an action that is refused on some of the selected rows" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      own = task(world, 1, title: "Mine", assignee_id: world.member.id)
      reported = task(world, 2, title: "Reported", reporter_id: world.member.id)
      other = task(world, 3, title: "Hers")
      another = task(world, 4, title: "Theirs")

      %{conn: conn, world: world, own: own, reported: reported, other: other, another: another}
    end

    test "by a policy: it runs on the records the person may change, and says of the others that they may not",
         %{conn: conn, world: world} = context do
      %{own: own, reported: reported, other: other, another: another} = context
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      html = run_bulk(view, "archive", [own.id, other.id, reported.id, another.id])

      assert states(world) == %{
               "Mine" => :archived,
               "Reported" => :archived,
               "Hers" => :in_progress,
               "Theirs" => :in_progress
             }

      assert bulk_result(html) == %{
               summary: "Archive: 2 done, 2 not done.",
               failures: ["You are not allowed to do this. (2)"]
             }

      assert announcement(html) ==
               "Archive: 2 done, 2 not done. You are not allowed to do this. (2)"

      # the rows on which it did not run stay selected: by their keys, which
      # are all the hook needs to name them
      assert_push_event view, "ash_table:bulk", %{table: "task", failed: failed}
      assert Enum.sort(failed) == Enum.sort([[other.id, nil], [another.id, nil]])
    end

    test "by a policy, for a destroy: the records the person may not delete are there still",
         %{conn: conn, world: world, own: own, other: other} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      html = run_bulk(view, "destroy", [own.id, other.id])

      assert {:ok, nil} = stored(own)
      assert {:ok, %Task{status: :in_progress}} = stored(other)

      assert bulk_result(html) == %{
               summary: "Destroy: 1 done, 1 not done.",
               failures: ["You are not allowed to do this. (1)"]
             }
    end

    test "by a policy, for all that match: no record is changed that the person could not change from its row",
         %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      html = run_bulk(view, "archive", :all)

      assert states(world) == %{
               "Mine" => :archived,
               "Reported" => :archived,
               "Hers" => :in_progress,
               "Theirs" => :in_progress
             }

      assert bulk_result(html).summary == "Archive: 2 done, 2 not done."
      assert_push_event view, "ash_table:bulk", %{failed: [_, _]}
    end

    test "by a validation: the others are done, and the action's message says why this one was not",
         %{conn: conn, world: world, own: own, other: other} do
      done = task(world, 5, title: "Done", status: :done, progress: 100)
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      html = bulk(view, "set_progress", [own.id, done.id, other.id])
      assert panel(html).heading == "Set progress: 3 records"
      run_panel(view, progress: "50")
      html = ran(view)

      assert panel(html) == nil
      assert stored!(own).progress == 50
      assert stored!(other).progress == 50
      assert stored!(done).progress == 100

      assert bulk_result(html) == %{
               summary: "Set progress: 2 done, 1 not done.",
               failures: ["Progress: must be 100 when the task is done (1)"]
             }

      assert_push_event view, "ash_table:bulk", %{failed: [[id, nil]]}
      assert id == done.id
    end

    test "for more than one reason: each message with the number of records it is about",
         %{conn: conn, world: world, own: own, other: other} do
      done =
        task(world, 5, title: "Done", status: :done, progress: 100, assignee_id: world.member.id)

      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      bulk(view, "set_progress", [own.id, done.id, other.id])
      run_panel(view, progress: "50")

      assert bulk_result(ran(view)) == %{
               summary: "Set progress: 1 done, 2 not done.",
               failures: [
                 "Progress: must be 100 when the task is done (1)",
                 "You are not allowed to do this. (1)"
               ]
             }
    end
  end

  describe "a selected record that is gone, or not the person's" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, 1, [])
      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")

      %{conn: conn, view: view, world: world, task: task}
    end

    test "counts as not done, and is no error", %{view: view, world: world, task: task} do
      deleted = task(world, 2, title: "Deleted")
      Ash.destroy!(deleted, authorize?: false)

      html = run_bulk(view, "archive", [task.id, deleted.id])

      assert stored!(task).status == :archived

      assert bulk_result(html) == %{
               summary: "Archive: 1 done, 1 not done.",
               failures: ["This record is no longer available. (1)"]
             }

      # it stays selected, for as long as the person leaves it so
      assert_push_event view, "ash_table:bulk", %{failed: [[id, nil]]}
      assert id == deleted.id
    end

    test "a record of another organization is not theirs: it is not changed, and nothing says that it is there",
         %{view: view, world: world, task: task} do
      [foreign | _] = world.other_tasks

      html = run_bulk(view, "archive", [foreign.id, task.id])

      assert stored!(foreign).status == foreign.status
      assert stored!(task).status == :archived

      assert bulk_result(html) == %{
               summary: "Archive: 1 done, 1 not done.",
               failures: ["This record is no longer available. (1)"]
             }

      html = run_bulk(view, "destroy", [foreign.id])
      assert {:ok, %Task{}} = stored(foreign)
      assert bulk_result(html).summary == "Destroy: 0 done, 1 not done."
    end

    test "what names no record at all counts the same, whatever it is", %{view: view, task: task} do
      rows = [
        Ash.UUID.generate(),
        "not a key",
        "",
        17,
        nil,
        %{"id" => task.id},
        [task.id, task.id],
        [[task.id]]
      ]

      html = run_bulk(view, "archive", rows)

      assert stored!(task).status == :in_progress

      assert bulk_result(html) == %{
               summary: "Archive: 0 done, 8 not done.",
               failures: ["This record is no longer available. (8)"]
             }
    end
  end

  describe "events a table never sends" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, 1, [])
      mine = task(world, 2, title: "Mine", assignee_id: world.member.id)

      %{conn: conn, world: world, task: task, mine: mine}
    end

    test "run nothing for a person who is offered no action on several rows",
         %{conn: conn, world: world, task: task} do
      for actor <- [world.viewer, world.nobody] do
        {:ok, view, _html} = conn |> log_in(actor) |> live("/tasks")

        for action <- ["archive", "destroy", "reassign", "set_progress"],
            selection <- [[task.id], :all] do
          bulk(view, action, selection)
          assert_reply view, %{ok: false}
          html = run_bulk(view, action, selection)
          assert bulk_result(html) == nil
          assert panel(html) == nil
        end

        html =
          render_hook(element(view, "#task-grid"), "panel_submit", %{
            "panel" => %{"progress" => "99"}
          })

        assert panel(html) == nil
      end

      assert {:ok, %Task{status: :in_progress, progress: 40}} = stored(task)
    end

    test "run an action with a panel through its panel only",
         %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      # `bulk_run` is for an action without inputs
      html = run_bulk(view, "reassign", [task.id])
      assert bulk_result(html) == nil

      html = run_bulk(view, "set_progress", :all)
      assert bulk_result(html) == nil

      assert %Task{progress: 40, internal_note: nil} = stored!(task)
    end

    test "take the panel's inputs by their names: nothing else that is sent reaches the action",
         %{conn: conn, world: world, task: task, mine: mine} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      bulk(view, "set_progress", [task.id, mine.id])

      send_panel(view, %{
        "panel" => %{
          "progress" => "70",
          "title" => "Renamed by hand",
          "status" => "done",
          "internal_note" => "By hand"
        }
      })

      ran(view)

      for task <- [task, mine] do
        assert %Task{progress: 70, status: :in_progress, internal_note: nil} = stored!(task)
        assert stored!(task).title == task.title
      end
    end

    test "do not let a member change what they could not change from its row, by any name",
         %{conn: conn, world: world, task: task, mine: mine} do
      [foreign | _] = world.other_tasks
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      for action <- ["archive", "destroy"] do
        run_bulk(view, action, [task.id, foreign.id])
      end

      bulk(view, "reassign", [task.id, foreign.id])
      run_panel(view, assignee_id: world.member.id, reason: "Mine now")
      ran(view)

      assert %Task{status: :in_progress, assignee_id: nil, internal_note: nil} = stored!(task)
      assert stored!(foreign).status == foreign.status
      assert stored!(foreign).assignee_id == foreign.assignee_id
      # their own task is theirs to change, and was not named
      assert stored!(mine).status == :in_progress
    end

    test "do not run on an outsider's behalf what is not theirs",
         %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = conn |> log_in(world.outsider) |> live("/tasks")

      html = run_bulk(view, "destroy", [task.id])

      assert {:ok, %Task{status: :in_progress}} = stored(task)
      assert bulk_result(html).summary == "Destroy: 0 done, 1 not done."

      # all that match is all of theirs
      own = Map.new(world.other_tasks, &{&1.title, :archived})
      run_bulk(view, "archive", :all)
      assert states() == Map.put(own, "Task 01", :in_progress) |> Map.put("Mine", :in_progress)
    end
  end

  describe "all that match" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      for day <- 1..30, do: task(world, day, [])
      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")

      %{conn: conn, view: view, world: world}
    end

    test "is every record of every page, and no record of another organization",
         %{view: view, world: world} do
      html = run_bulk(view, "archive", :all)

      assert bulk_result(html) == %{summary: "Archive: 30 done.", failures: []}

      states = states()
      assert Enum.count(states, fn {_title, status} -> status == :archived end) == 30
      for task <- world.other_tasks, do: assert(states[task.title] == task.status)
    end

    test "is what the filters match, as the table shows it", %{view: view} do
      filter(view, "task", "title", v: "Task 1")
      html = run_bulk(view, "archive", :all)

      assert bulk_result(html) == %{summary: "Archive: 10 done.", failures: []}
      archived = for {title, :archived} <- states(), do: title
      assert Enum.sort(archived) == for(day <- 10..19, do: "Task #{day}")
    end

    test "takes the inputs of a panel as the rows that are named do", %{view: view} do
      filter(view, "task", "title", v: "Task 0")
      html = bulk(view, "reassign", :all)
      assert panel(html).heading == "Reassign: 9 records"

      run_panel(view, assignee_id: "", reason: "Spring cleaning")
      ran(view)

      notes = for task <- Ash.read!(Task, authorize?: false), do: {task.title, task.internal_note}
      assert Enum.count(notes, fn {_title, note} -> note == "Spring cleaning" end) == 9
      assert {"Task 10", nil} in notes
    end

    test "that an action takes out of the filters are all done: none is skipped for it",
         %{view: view} do
      # every task is in progress; archived, it matches the filter no longer
      filter(view, "task", "status", v: "in_progress")
      html = run_bulk(view, "archive", :all)

      assert Enum.count(states(), fn {_title, status} -> status == :archived end) == 30
      assert titles(html) == []
    end
  end

  describe "the panel of an action on the selected rows" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      tasks = for day <- 1..2, do: task(world, day, [])
      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")

      %{conn: conn, view: view, world: world, tasks: tasks}
    end

    test "says what the action makes of a value as it is typed, and runs nothing",
         %{view: view, tasks: [first, second]} do
      bulk(view, "reassign", [first.id, second.id])
      html = type_in_panel(view, reason: "No", assignee_id: "not a key")

      assert %{errors: [], fields: [assignee, reason]} = panel(html)
      assert assignee.errors == ["is invalid"]
      assert reason.errors == ["length must be greater than or equal to 3"]
      assert stored!(first).internal_note == nil
    end

    test "stays open with the action's errors about its fields when Run is used, and nothing has run",
         %{view: view, tasks: [first, second]} do
      bulk(view, "reassign", [first.id, second.id])
      html = run_panel(view, reason: "", assignee_id: "")

      assert %{heading: "Reassign: 2 records", fields: [_assignee, reason]} = panel(html)
      assert reason.errors == ["is required"]
      assert announcement(html) == "Reassign failed: Reason: is required"
      assert bulk_result(html) == nil
      assert stored!(first).internal_note == nil

      # put right, it runs on both
      run_panel(view, reason: "Back from leave", assignee_id: "")
      html = ran(view)

      assert panel(html) == nil
      assert bulk_result(html) == %{summary: "Reassign: 2 done.", failures: []}
      assert stored!(first).internal_note == "Back from leave"
      assert stored!(second).internal_note == "Back from leave"
    end

    test "gives every record what its fields hold: an empty field is an empty value",
         %{view: view, world: world, tasks: [first, second]} do
      assigned = Ash.update!(first, %{assignee_id: world.member.id}, authorize?: false)
      assert assigned.assignee_id == world.member.id

      bulk(view, "reassign", [first.id, second.id])
      run_panel(view, reason: "Unassigned", assignee_id: "")
      ran(view)

      assert stored!(first).assignee_id == nil
      assert stored!(second).assignee_id == nil
    end

    test "can be given up: nothing runs", %{view: view, tasks: [first, second]} do
      bulk(view, "reassign", [first.id, second.id])
      type_in_panel(view, reason: "Never mind")
      html = cancel_panel(view)

      assert panel(html) == nil
      assert bulk_result(html) == nil
      assert stored!(first).internal_note == nil
    end
  end

  describe "in German" do
    test "the line, the question and the result are the table's own texts, translated",
         %{conn: conn} do
      world = world(tasks: 0)
      own = task(world, 1, assignee_id: world.member.id)
      other = task(world, 2, [])

      {:ok, view, html} =
        conn |> log_in(world.member) |> in_locale("de") |> live("/tasks")

      assert %{
               buttons: ["Alle 2 passenden auswählen", "Auswahl aufheben", "Archivieren" | _],
               selected: "{n} ausgewählt",
               all: "Alle 2 passenden sind ausgewählt"
             } = selection(html)

      assert attribute(html, box(own.id), "aria-label") == ["Zeile auswählen"]

      bulk(view, "archive", [own.id, other.id])
      assert_reply view, %{ask: "„Archivieren“ für 2 Einträge ausführen?"}

      bulk(view, "destroy", [own.id])

      assert_reply view, %{
        ask:
          "Diese Aufgabe löschen? Das lässt sich nicht rückgängig machen. 1 Eintrag ist ausgewählt."
      }

      html = bulk(view, "reassign", [own.id, other.id])
      assert panel(html).heading == "Neu zuweisen: 2 Einträge"
      cancel_panel(view)

      html = run_bulk(view, "archive", [own.id, other.id])

      assert %{summary: "Archivieren: 1 erledigt, 1 nicht erledigt.", failures: [_refusal]} =
               bulk_result(html)
    end
  end
end
