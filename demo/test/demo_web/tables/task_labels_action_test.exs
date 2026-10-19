defmodule DemoWeb.Tables.TaskLabelsActionTest do
  @moduledoc """
  A relationship that an action manages, as a person meets it at `/tasks`:
  "Set labels" takes the labels of a task as an argument, a list of keys,
  and hands them to the relationship (`manage_relationship`,
  `:append_and_remove`). Its panel lists the task's labels, each with a
  button that takes it out again, and "Choose" opens the picker: the table
  of the labels, in which any number of rows is selected. Nothing runs until
  the panel's own button is used.

  The keys are all the form sends, and a key from the browser is a claim:
  what a hand-made form can and cannot do is tested here too, and what the
  action's own policies say.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.{Label, Task, TaskLabel}

  @moment ~U[2026-01-01 12:00:00.000000Z]
  @labels "task-pick-labels"

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
          inserted_at:
            DateTime.add(@moment, System.unique_integer([:positive, :monotonic]), :millisecond)
        ] ++ overrides
      )
    )
  end

  defp label(world, name, organization \\ nil) do
    Generator.generate(
      Generator.label(organization_id: (organization || world.organization).id, name: name)
    )
  end

  defp carry(task, labels) do
    for label <- labels do
      Generator.generate(
        Generator.task_label(
          task_id: task.id,
          label_id: label.id,
          organization_id: task.organization_id
        )
      )
    end

    task
  end

  defp labels_of(task) do
    Task
    |> Ash.get!(task.id, authorize?: false, load: [:labels])
    |> Map.fetch!(:labels)
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp field(html, name \\ "labels"), do: Enum.find(panel(html).fields, &(&1.name == name))

  # A world with three labels of its own, called by what they are for.
  defp labelled(_context) do
    world = world(tasks: 0, other_tasks: 0, labels: 0)
    [bug, docs, urgent] = for name <- ["Bug", "Docs", "Urgent"], do: label(world, name)

    %{world: world, bug: bug, docs: docs, urgent: urgent}
  end

  describe "the button" do
    setup :labelled

    test "is a row action like the others, and opens the action panel though its argument has nothing typed into it",
         %{conn: conn, world: world} do
      task = task(world, "Write the report")
      {:ok, view, html} = conn |> log_in(world.admin) |> live("/tasks")

      assert "Set labels" in actions(html, task.id)

      html = act(view, task.id, "set_labels")
      assert_reply view, %{ok: true, panel: true}
      assert %{heading: "Set labels: Write the report", submit: "Run"} = panel(html)
    end

    test "is not there for a viewer, who can run no action on a task", %{conn: conn, world: world} do
      task = task(world, "Write the report")
      {:ok, _view, html} = conn |> log_in(world.viewer) |> live("/tasks")

      assert actions(html, task.id) == []
    end
  end

  describe "the field of the labels" do
    setup :labelled

    setup %{conn: conn, world: world, bug: bug, urgent: urgent} do
      task = carry(task(world, "Write the report"), [urgent, bug])
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      %{task: task, view: view}
    end

    test "starts with the labels the task carries: their keys, and what each is called",
         %{view: view, task: task, bug: bug, urgent: urgent} do
      html = act(view, task.id, "set_labels")

      assert %{
               name: "labels",
               label: "Labels",
               control: "references",
               required?: false,
               errors: []
             } = field = field(html)

      assert Enum.sort(field.value) == Enum.sort([bug.id, urgent.id])
      assert Enum.sort(field.chosen) == ["Bug", "Urgent"]
    end

    test "is a group named by its label, with a button per label that takes it out, and one that opens the picker",
         %{view: view, task: task} do
      html = act(view, task.id, "set_labels")
      id = "#task-panel-f-labels"

      assert attribute(html, id, "role") == ["group"]
      assert attribute(html, id, "aria-labelledby") == ["task-panel-f-labels-label"]
      assert text(html, "#{id}-label") == "Labels"
      assert text(html, "#{id}-choose") == "Choose"
      assert attribute(html, "#{id}-choose", "type") == ["button"]

      # each button says which label it takes out
      [first, second] = field(html).chosen

      assert attribute(html, "#{id}-r-0", "aria-label") == ["Remove #{first}"]
      assert attribute(html, "#{id}-r-1", "aria-label") == ["Remove #{second}"]
      assert attribute(html, "#{id}-r-0", "type") == ["button"]

      # the keys are sent as the values of an array are: after an entry of
      # the field's own, so that a list without labels is sent at all
      assert attribute(html, "#{id} input", "name") ==
               ["panel[labels][]", "panel[labels][]", "panel[labels][]"]

      assert hd(attribute(html, "#{id} input", "value")) == ""

      # the picker is not there until the button is used
      assert picker(html) == nil
      refute html =~ @labels
    end

    test "is empty for a task without labels", %{view: view, world: world} do
      bare = task(world, "No labels yet")
      html = render(view)
      refute html =~ "No labels yet"

      {:ok, view, _html} = build_conn() |> log_in(world.admin) |> live("/tasks")
      html = act(view, bare.id, "set_labels")

      assert %{value: [], chosen: []} = field(html)
      assert text(html, "#task-panel-f-labels-choose") == "Choose"
    end

    test "takes a label out with its button, which changes nothing of the task",
         %{view: view, task: task, bug: bug, urgent: urgent} do
      act(view, task.id, "set_labels")

      html = unpick(view, "labels", bug.id)
      assert %{value: [key], chosen: ["Urgent"]} = field(html)
      assert key == urgent.id
      assert labels_of(task) == ["Bug", "Urgent"]

      # the last one too: focus is sent to the field's "Choose"
      html = unpick(view, "labels", urgent.id)
      assert_push_event view, "ash_data_table:focus", %{cell: "task-panel-f-labels-choose"}
      assert %{value: [], chosen: []} = field(html)
    end

    test "says where focus goes when a label is taken out: to what stands where it stood",
         %{view: view, task: task} do
      html = act(view, task.id, "set_labels")
      [first, second] = field(html).value

      unpick(view, "labels", first)

      assert_push_event view, "ash_data_table:focus", %{
        table: "task",
        cell: "task-panel-f-labels-r-0"
      }

      unpick(view, "labels", second)

      assert_push_event view, "ash_data_table:focus", %{
        table: "task",
        cell: "task-panel-f-labels-choose"
      }
    end

    test "changes nothing for a key the field does not hold, and for another field",
         %{view: view, task: task, docs: docs} do
      before = field(act(view, task.id, "set_labels"))

      for {input, key} <- [{"labels", docs.id}, {"labels", "nothing"}, {"title", docs.id}] do
        html = unpick(view, input, key)
        refute_push_event view, "ash_data_table:focus", %{}
        assert field(html) == before
      end
    end
  end

  describe "the picker of the labels" do
    setup :labelled

    setup %{conn: conn, world: world, bug: bug, urgent: urgent} do
      task = carry(task(world, "Write the report"), [urgent, bug])
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      act(view, task.id, "set_labels")

      %{task: task, view: view}
    end

    test "opens on top of the panel, with the table of the labels, in which any number of rows is selected",
         %{view: view} do
      html = pick_input(view, "labels")

      assert %{
               heading: "Labels: choose label",
               table: @labels,
               # no "None": no row selected is the choice of no label
               buttons: ["Cancel", "Choose"],
               question: nil,
               error: nil
             } = picker(html)

      # the panel is still there underneath, with what it held
      assert %{heading: "Set labels: Write the report"} = panel(html)

      html = render_async(view)
      assert column(html, @labels, "name") == ["Bug", "Docs", "Urgent"]

      # a box per row, and one for the rows of the page
      assert attribute(html, "##{@labels}-table", "aria-multiselectable") == []
      assert attribute(html, "##{@labels}-grid", "data-select") == ["multi"]
      assert attribute(html, "##{@labels}-grid", "data-choose") == [""]

      assert length(
               attribute(html, "##{@labels}-table [role=rowgroup] input[type=checkbox]", "type")
             ) == 3

      assert attribute(html, "##{@labels}-select-head input", "aria-label") ==
               ["Select all rows of this page"]

      # "Choose" is to be used whatever is selected
      assert attribute(html, "#task-picker-choose", "aria-disabled") == ["false"]
      assert attribute(html, "#task-picker", "data-several") == [""]
    end

    test "says which rows are selected as it opens: those of the labels the field holds",
         %{view: view, bug: bug, urgent: urgent} do
      html = pick_input(view, "labels")

      assert Enum.sort(chosen_rows(html, @labels)) == Enum.sort([bug.id, urgent.id])
    end

    test "is a table to choose from: nothing in it is edited, run or created, and never every record that matches",
         %{view: view} do
      pick_input(view, "labels")
      html = render_async(view)

      assert editors(html, @labels) == []
      assert text(html, "##{@labels}-create") == nil
      assert text(html, "##{@labels}-actions-head") == nil

      # the line above its grid counts what is selected, and offers to clear it
      assert %{buttons: ["Select all 3 that match", "Clear selection"]} =
               selection(html, @labels)

      # all of the page selected, there is nothing more to offer: the page
      # is all there is
      refute selection(select_page(view, @labels), @labels).offered?
    end

    test "a choice puts the selected labels into the field, after those it held, and runs nothing",
         %{view: view, task: task, bug: bug, docs: docs, urgent: urgent} do
      pick_input(view, "labels")

      html = picked_rows(view, [urgent.id, docs.id])
      assert_reply view, %{ok: true}

      # the picker is gone, the panel is open
      assert picker(html) == nil
      assert %{value: value, chosen: ["Urgent", "Docs"]} = field(html)
      assert value == [urgent.id, docs.id]
      refute bug.id in value

      # nothing was saved
      assert labels_of(task) == ["Bug", "Urgent"]
    end

    test "no row selected is the choice of no label", %{view: view, task: task} do
      pick_input(view, "labels")

      html = picked_rows(view, [])
      assert_reply view, %{ok: true}
      assert %{value: [], chosen: []} = field(html)
      assert labels_of(task) == ["Bug", "Urgent"]
    end

    test "opens again with what the field holds now", %{view: view, docs: docs, urgent: urgent} do
      pick_input(view, "labels")
      picked_rows(view, [urgent.id, docs.id])

      html = pick_input(view, "labels")
      assert chosen_rows(html, @labels) == [urgent.id, docs.id]
    end

    test "Cancel closes it and leaves the field as it was", %{view: view} do
      before = field(render(view))
      pick_input(view, "labels")

      html = cancel_picker(view)
      assert picker(html) == nil
      assert field(html) == before
    end

    test "a row that names no label this person may read chooses nothing, and the picker says so",
         %{view: view, world: world, docs: docs} do
      abroad = label(world, "Abroad", world.other_organization)
      before = field(render(view))
      pick_input(view, "labels")

      for rows <- [[abroad.id], [docs.id, abroad.id], [Ash.UUID.generate()], ["nothing"], [nil]] do
        html = picked_rows(view, rows)
        assert_reply view, %{ok: false}
        assert %{error: "This record is no longer available."} = picker(html)
        assert field(html) == before
      end

      # what the event names is nothing: the rows selected in the picker's
      # table are what is chosen, read again as the person
      select(view, chooser_table(view), [abroad.id])
      html = forge(view, "task", "picked", %{"rows" => [docs.id], "row" => docs.id})

      assert_reply view, %{ok: false}
      assert %{error: "This record is no longer available."} = picker(html)
      assert field(html) == before
    end
  end

  describe "running the action" do
    setup :labelled

    setup %{conn: conn, world: world, bug: bug, urgent: urgent} do
      task = carry(task(world, "Write the report"), [urgent, bug])
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      act(view, task.id, "set_labels")

      %{task: task, view: view}
    end

    test "gives the task the labels the field holds, and takes the others off", %{
      view: view,
      task: task,
      docs: docs,
      urgent: urgent
    } do
      pick_input(view, "labels")
      picked_rows(view, [urgent.id, docs.id])

      html = run_panel(view, %{})

      assert panel(html) == nil
      assert labels_of(task) == ["Docs", "Urgent"]
      assert announcement(html) == "Set labels: done"
    end

    test "with nothing changed leaves the task's labels as they are", %{view: view, task: task} do
      html = run_panel(view, %{})

      assert panel(html) == nil
      assert labels_of(task) == ["Bug", "Urgent"]
    end

    test "with an empty field takes every label off", %{
      view: view,
      task: task,
      bug: bug,
      urgent: urgent
    } do
      unpick(view, "labels", bug.id)
      unpick(view, "labels", urgent.id)

      html = run_panel(view, %{})

      assert panel(html) == nil
      assert labels_of(task) == []
      # the labels themselves are still there
      assert Label |> Ash.read!(authorize?: false) |> length() == 3
    end

    test "a key the form sends that names no label this person may read runs nothing, and the panel says so",
         %{view: view, task: task, world: world, bug: bug} do
      abroad = label(world, "Abroad", world.other_organization)

      for key <- [abroad.id, Ash.UUID.generate()] do
        html = send_panel(view, %{"panel" => %{"labels" => ["", bug.id, key]}})

        assert %{errors: ["Labels: This record is no longer available."]} = panel(html)
        assert labels_of(task) == ["Bug", "Urgent"]

        assert announcement(html) ==
                 "Set labels failed: Labels: This record is no longer available."
      end
    end

    test "a key the form sends of a label they may read is taken, chosen in the picker or not",
         %{view: view, task: task, docs: docs} do
      html = send_panel(view, %{"panel" => %{"labels" => ["", docs.id]}})

      assert panel(html) == nil
      assert labels_of(task) == ["Docs"]
    end

    test "what is no key is the action's to refuse: at the field, with the panel left open",
         %{view: view, task: task} do
      html = send_panel(view, %{"panel" => %{"labels" => ["", "not a key"]}})

      assert %{errors: [_ | _]} = field(html)
      assert labels_of(task) == ["Bug", "Urgent"]
    end
  end

  describe "what the action's policies say" do
    setup :labelled

    test "a member sets the labels of a task that is theirs", %{
      conn: conn,
      world: world,
      docs: docs
    } do
      own = task(world, "Mine", assignee_id: world.member.id)
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      act(view, own.id, "set_labels")
      pick_input(view, "labels")
      picked_rows(view, [docs.id])
      html = run_panel(view, %{})

      assert panel(html) == nil
      assert labels_of(own) == ["Docs"]
    end

    test "and is refused on a task that is not: the panel says so, and nothing changes",
         %{conn: conn, world: world, bug: bug, docs: docs} do
      foreign = carry(task(world, "Not mine"), [bug])
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      # the field shows the label: reading is not refused
      html = act(view, foreign.id, "set_labels")
      assert %{chosen: ["Bug"]} = field(html)

      pick_input(view, "labels")
      picked_rows(view, [docs.id])
      html = run_panel(view, %{})

      assert %{errors: ["You are not allowed to do this."]} = panel(html)
      assert labels_of(foreign) == ["Bug"]
      assert Ash.count!(TaskLabel, authorize?: false) == 1
    end

    test "a person of another organization neither sees nor chooses this one's labels",
         %{conn: conn, world: world, bug: bug} do
      project =
        Generator.generate(Generator.project(organization_id: world.other_organization.id))

      theirs =
        Generator.generate(
          Generator.task(
            organization_id: world.other_organization.id,
            project_id: project.id,
            reporter_id: world.outsider.id,
            title: "Abroad"
          )
        )

      {:ok, view, _html} = conn |> log_in(world.outsider) |> live("/tasks")
      act(view, theirs.id, "set_labels")
      pick_input(view, "labels")
      html = render_async(view)

      assert column(html, @labels, "name") == []

      html = picked_rows(view, [bug.id])
      assert_reply view, %{ok: false}
      assert %{error: "This record is no longer available."} = picker(html)

      html = send_panel(view, %{"panel" => %{"labels" => ["", bug.id]}})
      assert %{errors: ["Labels: This record is no longer available."]} = panel(html)
      assert labels_of(theirs) == []
    end
  end

  describe "on the selected rows" do
    setup :labelled

    setup %{conn: conn, world: world, bug: bug, urgent: urgent} do
      first = carry(task(world, "First"), [bug])
      second = carry(task(world, "Second"), [urgent])
      third = task(world, "Third")

      %{conn: conn, first: first, second: second, third: third}
    end

    test "the action is offered, and its field starts empty: there is no one task to take labels from",
         %{conn: conn, world: world, first: first, second: second} do
      {:ok, view, html} = conn |> log_in(world.admin) |> live("/tasks")

      assert "Set labels" in selection(html).buttons

      html = bulk(view, "set_labels", [first.id, second.id])
      assert_reply view, %{panel: true}

      assert %{heading: "Set labels: 2 records", fields: [%{value: [], chosen: []}]} = panel(html)
    end

    test "gives every selected task the labels that were chosen, and no others", %{
      conn: conn,
      world: world,
      first: first,
      second: second,
      third: third,
      docs: docs,
      urgent: urgent
    } do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      bulk(view, "set_labels", [first.id, second.id])
      pick_input(view, "labels")
      html = picked_rows(view, [docs.id, urgent.id])
      assert %{chosen: ["Docs", "Urgent"]} = field(html)

      run_panel(view, %{})
      html = ran(view)

      assert bulk_result(html) == %{summary: "Set labels: 2 done.", failures: []}
      assert labels_of(first) == ["Docs", "Urgent"]
      assert labels_of(second) == ["Docs", "Urgent"]
      assert labels_of(third) == []
    end

    test "runs on the tasks a member may change, and says how many it was refused on",
         %{conn: conn, world: world, first: first, docs: docs} do
      own = task(world, "Mine", assignee_id: world.member.id)
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      bulk(view, "set_labels", [first.id, own.id])
      pick_input(view, "labels")
      picked_rows(view, [docs.id])
      run_panel(view, %{})
      html = ran(view)

      assert bulk_result(html) == %{
               summary: "Set labels: 1 done, 1 not done.",
               failures: ["You are not allowed to do this. (1)"]
             }

      assert labels_of(own) == ["Docs"]
      assert labels_of(first) == ["Bug"]
    end

    test "runs on none where a key names no label this person may read", %{
      conn: conn,
      world: world,
      first: first,
      second: second
    } do
      abroad = label(world, "Abroad", world.other_organization)
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      bulk(view, "set_labels", [first.id, second.id])
      html = send_panel(view, %{"panel" => %{"labels" => ["", abroad.id]}})

      assert %{errors: ["Labels: This record is no longer available."]} = panel(html)
      assert labels_of(first) == ["Bug"]
      assert labels_of(second) == ["Urgent"]
    end
  end

  describe "in a nested table, and in German" do
    setup :labelled

    test "the tasks under a project set their labels the same way", %{
      conn: conn,
      world: world,
      bug: bug,
      docs: docs
    } do
      task = carry(task(world, "Under a project"), [bug])
      [project | _] = world.projects
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/projects")

      expand(view, "project", project.id)
      toggle(view, "project", project.id, "tasks")
      render_async(view)

      tasks = nested("project", project.id, "tasks")
      html = act(view, tasks, task.id, "set_labels")
      assert %{chosen: ["Bug"]} = field_in(html, tasks)

      html = pick_input(view, tasks, "labels")
      assert %{heading: "Labels: choose label", table: table} = picker(html, tasks)
      assert table == "#{tasks}-pick-labels"

      picked_rows(view, tasks, [bug.id, docs.id])
      run_panel(view, tasks, %{})

      assert labels_of(task) == ["Bug", "Docs"]
    end

    test "the panel and the picker speak German", %{conn: conn, world: world, bug: bug} do
      task = carry(task(world, "Bericht schreiben"), [bug])

      {:ok, view, html} =
        conn |> log_in(world.admin) |> in_locale("de") |> live("/tasks")

      assert "Labels setzen" in actions(html, task.id)

      html = act(view, task.id, "set_labels")
      assert %{heading: "Labels setzen: Bericht schreiben", submit: "Ausführen"} = panel(html)
      assert text(html, "#task-panel-f-labels-choose") == "Auswählen"
      assert attribute(html, "#task-panel-f-labels-r-0", "aria-label") == ["Bug entfernen"]

      html = pick_input(view, "labels")

      assert %{heading: "Labels: Label auswählen", buttons: ["Abbrechen", "Auswählen"]} =
               picker(html)
    end
  end

  defp field_in(html, id), do: Enum.find(panel(html, id).fields, &(&1.name == "labels"))
end
