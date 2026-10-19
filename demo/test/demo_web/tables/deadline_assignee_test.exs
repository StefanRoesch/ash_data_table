defmodule DemoWeb.Tables.DeadlineAssigneeTest do
  @moduledoc """
  A reference cell that is edited through an argument, as a person meets it
  at `/deadlines`: "Assignee" is saved by `hand_over`, which does not accept
  `assignee_id`. It takes the person as an argument and hands it to the
  relationship (`manage_relationship`, `:append_and_remove`). The cell opens
  the picker as any reference cell does, and a choice gives the action that
  one argument.

  The table reads through an action that requires the day, so every test
  gives it first.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Task

  @people "deadline-pick-assignee"

  defp person(world, name, organization \\ nil) do
    Generator.generate(
      Generator.user(organization_id: (organization || world.organization).id, name: name)
    )
  end

  defp task(world, title, overrides) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          assignee_id: nil,
          title: title,
          status: :todo,
          due_on: Date.add(Date.utc_today(), 2)
        ] ++ overrides
      )
    )
  end

  defp stored!(task), do: Ash.get!(Task, task.id, authorize?: false)

  # the page of the deadlines, with the day given
  defp deadlines(conn, actor) do
    {:ok, view, _html} = conn |> log_in(actor) |> live("/deadlines")
    html = argue(view, "deadline", a: %{"by" => Date.to_iso8601(Date.add(Date.utc_today(), 30))})
    {view, html}
  end

  setup do
    world = world(tasks: 0, other_tasks: 0)
    ada = person(world, "Ada Lovelace")
    grace = person(world, "Grace Hopper")
    task = task(world, "Write the report", assignee_id: ada.id)

    %{world: world, ada: ada, grace: grace, task: task}
  end

  describe "the cell" do
    test "is edited, though no update action accepts its key: by choosing, as any reference cell",
         %{conn: conn, world: world, task: task} do
      {_view, html} = deadlines(conn, world.admin)

      assert text(html, cell("deadline", task.id, "assignee")) == "Ada Lovelace"
      assert "assignee" in editors(html, "deadline")
      assert %{control: "reference", confirm: nil} = editor(html, "deadline", "assignee")
      assert attribute(html, cell("deadline", task.id, "assignee"), "tabindex") == ["0"]

      refute :assignee_id in Ash.Resource.Info.action(Demo.Tracker.Deadline, :hand_over).accept
      refute :assignee_id in Ash.Resource.Info.action(Demo.Tracker.Deadline, :reschedule).accept
    end

    test "opens the picker on the person the task is assigned to, with \"None\": the argument can be empty",
         %{conn: conn, world: world, task: task, ada: ada} do
      {view, _html} = deadlines(conn, world.admin)

      html = pick(view, "deadline", task.id, "assignee")
      assert_reply view, %{ok: true}

      assert %{
               heading: "Assignee: choose user",
               table: @people,
               buttons: ["Cancel", "None", "Choose"],
               question: nil
             } = picker(html, "deadline")

      # one row at a time
      assert attribute(html, "##{@people}-grid", "data-select") == ["single"]
      assert current(html, @people) == [ada.id]
    end
  end

  describe "a choice" do
    test "runs the column's action with the argument, and shows the new name in the cell",
         %{conn: conn, world: world, task: task, grace: grace} do
      {view, _html} = deadlines(conn, world.admin)
      pick(view, "deadline", task.id, "assignee")

      html = picked(view, "deadline", grace.id)
      assert_reply view, %{ok: true}

      assert picker(html, "deadline") == nil
      assert text(html, cell("deadline", task.id, "assignee")) == "Grace Hopper"
      assert failure(html, "deadline", task.id, "assignee") == nil
      assert stored!(task).assignee_id == grace.id
    end

    test "of the person the task is assigned to already runs nothing", %{
      conn: conn,
      world: world,
      task: task,
      ada: ada
    } do
      before = stored!(task).updated_at
      {view, _html} = deadlines(conn, world.admin)
      pick(view, "deadline", task.id, "assignee")

      html = picked(view, "deadline", ada.id)
      assert_reply view, %{ok: true}

      assert picker(html, "deadline") == nil
      assert stored!(task).updated_at == before
    end

    test "of nobody takes the assignee away: the argument is everything the relationship is to hold",
         %{conn: conn, world: world, task: task} do
      {view, _html} = deadlines(conn, world.admin)
      pick(view, "deadline", task.id, "assignee")

      html = picked(view, "deadline", nil)
      assert_reply view, %{ok: true}

      assert text(html, cell("deadline", task.id, "assignee")) == ""
      assert stored!(task).assignee_id == nil
    end

    test "of a row that names nobody this person may read saves nothing: it is no row of the picker's table",
         %{conn: conn, world: world, task: task, ada: ada} do
      abroad = person(world, "Abroad", world.other_organization)
      {view, _html} = deadlines(conn, world.admin)
      pick(view, "deadline", task.id, "assignee")

      for row <- [abroad.id, Ash.UUID.generate(), "nothing"] do
        html = picked(view, "deadline", row)
        assert_reply view, %{ok: false}
        assert %{error: nil} = picker(html, "deadline")
      end

      assert stored!(task).assignee_id == ada.id
    end
  end

  describe "what the action's policies say" do
    test "a member hands over a task that is theirs", %{conn: conn, world: world, grace: grace} do
      own = task(world, "Mine", assignee_id: world.member.id)
      {view, _html} = deadlines(conn, world.member)
      pick(view, "deadline", own.id, "assignee")

      html = picked(view, "deadline", grace.id)
      assert_reply view, %{ok: true}
      assert text(html, cell("deadline", own.id, "assignee")) == "Grace Hopper"
      assert stored!(own).assignee_id == grace.id
    end

    test "and is refused on a task that is not: the cell is marked, shows who was chosen, and nothing is saved",
         %{conn: conn, world: world, task: task, ada: ada, grace: grace} do
      {view, _html} = deadlines(conn, world.member)
      pick(view, "deadline", task.id, "assignee")

      html = picked(view, "deadline", grace.id)
      assert_reply view, %{ok: false}

      assert picker(html, "deadline") == nil

      assert failure(html, "deadline", task.id, "assignee") == %{
               shown: "Grace Hopper",
               message: "You are not allowed to change this."
             }

      assert announcement(html, "deadline") ==
               "Assignee was not saved: You are not allowed to change this."

      assert stored!(task).assignee_id == ada.id
    end

    test "a viewer, who reads no people and runs no update, has neither the column nor an editor",
         %{conn: conn, world: world, task: task} do
      {view, html} = deadlines(conn, world.viewer)

      refute "Assignee" in headers(html, "deadline")
      assert editors(html, "deadline") == []

      # and an event that asks for the picker is refused
      html = pick(view, "deadline", task.id, "assignee")
      assert_reply view, %{ok: false}
      assert picker(html, "deadline") == nil
    end
  end
end
