defmodule DemoWeb.Tables.LiveUpdatesTest do
  @moduledoc """
  Live updates, as people meet them in the demo: the tasks (`/tasks`) and
  the comments announce their changes, and their tables follow them. Two
  people have the same page open, and one sees what the other changes; and
  two tables of the comments stand on one page (`/named`), where a change
  in one shows in the other.

  Nothing of an announcement is shown: it holds a primary key, and the
  record is read again as the person who is looking. What that must never
  show is tested here on Postgres, and in `live_updates_elsewhere_test.exs`
  for the cases the demo's own tables do not have.

  The tests run beside others, which announce tasks of their own through
  the same server. Each test's organization is its own (the generator's
  ids are the test's), and so is its topic.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias AshDataTable.Resource.Notifier
  alias Demo.Generator
  alias Demo.Tracker.Comment
  alias Demo.Tracker.Project
  alias Demo.Tracker.Task

  @moment ~U[2026-01-01 12:00:00.000000Z]
  @notice "There are new or changed records."

  # One task of the world's first organization, reported by the admin and
  # assigned to nobody; the later a task is made, the higher it stands.
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
          description: nil,
          status: :in_progress,
          progress: 40,
          estimate_hours: Decimal.new("12.5"),
          external_ref: nil,
          inserted_at:
            DateTime.add(@moment, System.unique_integer([:positive, :monotonic]), :millisecond)
        ] ++ overrides
      )
    )
  end

  defp comment(world, task, body) do
    Generator.generate(
      Generator.comment(
        organization_id: world.organization.id,
        task_id: task.id,
        author_id: world.admin.id,
        body: body,
        inserted_at:
          DateTime.add(@moment, System.unique_integer([:positive, :monotonic]), :millisecond)
      )
    )
  end

  # The page once what was announced has reached it. A listener gathers for
  # 100 ms; `AshDataTable.Test.flush/1` has it hand over at once, and the table
  # may read again for what it heard. A row that is to go is asked about
  # first (`ash_data_table:leaving`): `gone` are the keys of the rows the
  # test expects to go, and for each the hook, which these tests do not
  # have, answers that no cell of it is being edited.
  defp heard(view, gone \\ []) do
    AshDataTable.Test.flush(view)
    render_async(view, 10_000)
    Enum.each(gone, &left(view, &1))
    render(view)
  end

  defp left(view, row) do
    assert_push_event(view, "ash_data_table:leaving", %{table: table, row: ^row})
    forge(view, table, "left", %{"row" => row})
  end

  defp titles(html), do: column(html, "task", "title")
  defp notice(html, id \\ "task"), do: text(html, "[id='#{id}-notice'] > span") || ""

  # How many tables listen to the changes of a resource for a tenant.
  defp listeners({resource, tenant}), do: AshDataTable.Test.listening(resource, tenant)

  defp announcements(sofar \\ []) do
    receive do
      {:ash_data_table_changed, _resource, _type, _key, _tenant} = message ->
        announcements([message | sofar])
    after
      0 -> Enum.reverse(sofar)
    end
  end

  setup do
    %{world: world(tasks: 0, other_tasks: 0)}
  end

  describe "what is announced" do
    setup %{world: world} do
      Phoenix.PubSub.subscribe(Demo.PubSub, Notifier.topic(Task, world.organization.id))
      :ok
    end

    test "is the resource, the kind of action, the primary key and the tenant, and no more",
         %{world: world} do
      [project | _] = world.projects

      created =
        Ash.create!(
          Task,
          %{title: "Announce me", project_id: project.id, external_ref: "EXT-SECRET"},
          as(world.admin)
        )

      assert_receive message

      assert message ==
               {:ash_data_table_changed, Task, :create, %{id: created.id}, world.organization.id}

      Ash.update!(created, %{title: "Announced"}, as(world.admin))
      assert_receive message

      assert message ==
               {:ash_data_table_changed, Task, :update, %{id: created.id}, world.organization.id}

      Ash.destroy!(created, as(world.admin))
      assert_receive message

      assert message ==
               {:ash_data_table_changed, Task, :destroy, %{id: created.id}, world.organization.id}

      assert announcements() == []
    end

    test "goes to the record's own tenant, also for a write without one, and to no other",
         %{world: world} do
      other = Notifier.topic(Task, world.other_organization.id)
      assert other != Notifier.topic(Task, world.organization.id)
      assert other =~ world.other_organization.id

      task = task(world, "Global write")

      # one who listens for the other organization
      test = self()

      listener =
        Elixir.Task.async(fn ->
          Phoenix.PubSub.subscribe(Demo.PubSub, other)
          send(test, :listening)

          receive do
            :say -> announcements()
          end
        end)

      assert_receive :listening
      # written without a tenant: the resource is `global? true`
      Ash.update!(task, %{title: "Globally written"}, authorize?: false)
      # announced by the time the action returns: in the process that ran it
      send(listener.pid, :say)

      assert_receive {:ash_data_table_changed, Task, :update, %{id: id}, tenant}
      assert {id, tenant} == {task.id, world.organization.id}
      assert Elixir.Task.await(listener) == []
    end

    test "is every record of a bulk action that is run with `notify?`", %{world: world} do
      tasks = for n <- 1..3, do: task(world, "Bulk #{n}")

      %Ash.BulkResult{status: :success} =
        Ash.bulk_update(
          tasks,
          :update,
          %{title: "In bulk"},
          [notify?: true, strategy: [:atomic, :stream]] ++ as(world.admin)
        )

      keys =
        for {:ash_data_table_changed, Task, :update, key, _tenant} <- announcements(), do: key.id

      assert Enum.sort(keys) == Enum.sort(Enum.map(tasks, & &1.id))

      %Ash.BulkResult{status: :success} =
        Ash.bulk_update(
          tasks,
          :update,
          %{title: "Quietly"},
          [strategy: [:atomic, :stream]] ++ as(world.admin)
        )

      assert announcements() == []
    end

    test "is nothing for an action that is rolled back, and comes after the commit",
         %{world: world} do
      task = task(world, "Stays as it is")

      # a transaction around several actions, rolled back
      assert {:error, _undone} =
               Ash.transaction(Task, fn ->
                 Ash.update!(task, %{title: "Never either"}, as(world.admin))
                 Ash.DataLayer.rollback(Task, :undone)
               end)

      assert announcements() == []
      assert Ash.get!(Task, task.id, authorize?: false).title == "Stays as it is"

      # and committed: announced once the transaction is, not inside it
      assert {:ok, []} =
               Ash.transaction(Task, fn ->
                 Ash.update!(task, %{title: "Committed"}, as(world.admin))
                 announcements()
               end)

      assert_receive {:ash_data_table_changed, Task, :update, %{id: id}, _tenant}
      assert id == task.id
    end
  end

  describe "a row that another person changes" do
    setup %{conn: conn, world: world} do
      mine = task(world, "Mine", assignee_id: world.member.id, estimate_hours: Decimal.new("7"))
      theirs = task(world, "Theirs", external_ref: "EXT-SECRET-7")

      {:ok, admin, _html} = conn |> log_in(world.admin) |> live("/tasks")
      {:ok, member, html} = conn |> log_in(world.member) |> live("/tasks")

      assert titles(html) == ["Theirs", "Mine"]
      %{admin: admin, member: member, mine: mine, theirs: theirs}
    end

    test "is updated in place for a person who may read it, without a notice",
         %{admin: admin, member: member, theirs: theirs} do
      save(admin, theirs.id, "title", "Theirs, renamed")

      html = heard(member)
      assert titles(html) == ["Theirs, renamed", "Mine"]
      assert notice(html) == ""
      assert text(html, "#task-range") == "1–2 of 2"

      # and the one who changed it is told nothing about their own change
      html = heard(admin)
      assert titles(html) == ["Theirs, renamed", "Mine"]
      assert notice(html) == ""
    end

    test "keeps a field hidden that a field policy hides from the person",
         %{admin: admin, member: member, mine: mine, theirs: theirs} do
      # The estimate is an admin's, and the assignee's on their own task.
      # Everything the member's page is sent from the first change on: the
      # table may hear of the first before the second is saved.
      sent =
        wire(member, fn ->
          save(admin, theirs.id, "title", "Theirs, renamed")
          save(admin, mine.id, "title", "Mine, renamed")
          AshDataTable.Test.flush(member)
        end)

      html = render(member)

      assert titles(html) == ["Theirs, renamed", "Mine, renamed"]

      assert Enum.zip(titles(html), column(html, "task", "estimate_hours")) == [
               {"Theirs, renamed", "Not available"},
               {"Mine, renamed", "7 h"}
             ]

      refute html =~ "12.5"
      refute sent =~ "12.5"
      # an admin's alone: no column for a member, and nothing of it sent
      refute html =~ "EXT-SECRET-7"
      refute sent =~ "EXT-SECRET-7"
      assert sent =~ "Theirs, renamed"
    end

    test "stays when it no longer matches the person's filter, as after their own edit",
         %{admin: admin, member: member, theirs: theirs} do
      html = filter(member, "task", "title", v: "Theirs")
      assert titles(html) == ["Theirs"]

      save(admin, theirs.id, "title", "Renamed away")

      html = heard(member)
      assert titles(html) == ["Renamed away"]
      assert notice(html) == ""
    end

    test "goes when its record is destroyed, and the count follows",
         %{world: world, member: member, theirs: theirs} do
      Ash.destroy!(theirs, as(world.admin))

      html = heard(member, [theirs.id])
      assert titles(html) == ["Mine"]
      assert text(html, "#task-range") == "1–1 of 1"
      assert notice(html) == ""
    end

    test "is no longer selected when it goes",
         %{world: world, member: member, mine: mine, theirs: theirs} do
      select(member, "task", [theirs.id, mine.id])
      Ash.destroy!(theirs, as(world.admin))
      heard(member, [theirs.id])

      assert_push_event(member, "ash_data_table:select", %{table: "task", rows: rows})
      assert rows == [[mine.id, nil]]
    end

    test "is updated in one go when many change at once",
         %{world: world, member: member, mine: mine, theirs: theirs} do
      %Ash.BulkResult{status: :success} =
        Ash.bulk_update(
          [mine, theirs],
          :update,
          %{description: "Changed together"},
          [notify?: true, strategy: [:atomic, :stream]] ++ as(world.admin)
        )

      html = heard(member)
      assert column(html, "task", "description") == ["Changed together", "Changed together"]
    end
  end

  describe "a row the person is working on" do
    setup %{conn: conn, world: world} do
      task = task(world, "Being edited", assignee_id: world.member.id)
      other = task(world, "Left alone")
      {:ok, member, _html} = conn |> log_in(world.member) |> live("/tasks")
      %{member: member, task: task, other: other}
    end

    test "is held while the action panel is open for it", %{
      world: world,
      member: member,
      task: task
    } do
      act(member, task.id, "reassign")
      assert panel(render(member)).heading =~ "Reassign"

      Ash.update!(task, %{title: "Changed under the panel"}, as(world.admin))

      html = heard(member)
      assert titles(html) == ["Left alone", "Being edited"]
      assert panel(html).heading =~ "Reassign"

      html = cancel_panel(member)
      assert titles(html) == ["Left alone", "Changed under the panel"]
    end

    test "is held while the picker is open for a cell of it", %{
      world: world,
      member: member,
      task: task
    } do
      pick(member, task.id, "assignee")
      assert picker(render(member))

      Ash.update!(task, %{title: "Changed under the picker"}, as(world.admin))

      html = heard(member)
      assert titles(html) == ["Left alone", "Being edited"]

      html = cancel_picker(member)
      assert titles(html) == ["Left alone", "Changed under the picker"]
    end

    test "is put back at once where the server knows of nothing open: a cell's editor is the hook's",
         %{world: world, member: member, task: task} do
      # the hook leaves the cell that is being edited alone (the browser tests)
      Ash.update!(task, %{title: "Not held"}, as(world.admin))
      assert titles(heard(member)) == ["Left alone", "Not held"]
    end
  end

  describe "a record that is no row of the page" do
    setup %{conn: conn, world: world} do
      task(world, "Already there")
      {:ok, member, _html} = conn |> log_in(world.member) |> live("/tasks")
      %{member: member}
    end

    test "is never put into it: the table says that there are new or changed records",
         %{world: world, member: member} do
      task(world, "Not announced: written behind the table's back")
      assert notice(heard(member)) == ""

      [project | _] = world.projects
      Ash.create!(Task, %{title: "Brand new", project_id: project.id}, as(world.admin))

      html = heard(member)
      assert titles(html) == ["Already there"]
      assert notice(html) == @notice
      assert announcement(html) == @notice
      assert text(html, "#task-read-again") == "Read again"
      assert attribute(html, "#task-status", "aria-live") == ["polite"]

      html = member |> element("#task-read-again") |> render_click()
      html = if titles(html) == ["Already there"], do: render_async(member, 10_000), else: html

      assert "Brand new" in titles(html)
      assert notice(html) == ""
      assert html |> attribute("#task-read-again", "id") == []
    end

    test "is not spoken of when it does not match the person's filters",
         %{world: world, member: member} do
      filter(member, "task", "title", v: "Already")

      [project | _] = world.projects
      Ash.create!(Task, %{title: "Something else", project_id: project.id}, as(world.admin))
      assert notice(heard(member)) == ""

      Ash.create!(Task, %{title: "Already twice", project_id: project.id}, as(world.admin))
      assert notice(heard(member)) == @notice
    end

    test "is not spoken of when it was destroyed", %{world: world, member: member} do
      # on the second page of nobody: no row here
      gone = task(world, "Gone again")
      heard(member)
      Ash.destroy!(gone, as(world.admin))

      assert notice(heard(member)) == ""
    end

    test "has its notice taken away by the next read", %{world: world, member: member} do
      [project | _] = world.projects
      Ash.create!(Task, %{title: "Brand new", project_id: project.id}, as(world.admin))
      assert notice(heard(member)) == @notice

      html = filter(member, "task", "title", v: "Brand")
      assert titles(html) == ["Brand new"]
      assert notice(html) == ""
    end

    test "is said in the person's language", %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.member) |> in_locale("de") |> live("/tasks")

      [project | _] = world.projects
      Ash.create!(Task, %{title: "Neu", project_id: project.id}, as(world.admin))

      html = heard(view)
      assert notice(html) == "Es gibt neue oder geänderte Einträge."
      assert text(html, "#task-read-again") == "Neu lesen"
    end
  end

  describe "what a person may not read" do
    test "another tenant's change shows nothing, neither a row nor a notice",
         %{conn: conn, world: world} do
      theirs = task(world, "Of the first organization")
      {:ok, outsider, html} = conn |> log_in(world.outsider) |> live("/tasks")
      assert titles(html) == []

      [project | _] = world.projects
      Ash.update!(theirs, %{title: "Changed over there"}, as(world.admin))
      Ash.create!(Task, %{title: "New over there", project_id: project.id}, as(world.admin))

      html = heard(outsider)
      assert titles(html) == []
      assert notice(html) == ""
      refute html =~ "over there"
    end

    test "a key of another tenant that reaches the table all the same shows nothing",
         %{conn: conn, world: world} do
      theirs = task(world, "Of the first organization")
      {:ok, outsider, _html} = conn |> log_in(world.outsider) |> live("/tasks")

      # as if it had been announced to the outsider's organization
      for type <- [:create, :update] do
        Phoenix.PubSub.broadcast(
          Demo.PubSub,
          Notifier.topic(Task, world.other_organization.id),
          {:ash_data_table_changed, Task, type, %{id: theirs.id}, world.other_organization.id}
        )
      end

      sent = wire(outsider, fn -> AshDataTable.Test.flush(outsider) end)
      html = render(outsider)

      assert titles(html) == []
      assert notice(html) == ""
      refute sent =~ "Of the first organization"
      refute sent =~ "new or changed"
    end

    test "nobody is told of nothing", %{conn: conn, world: world} do
      {:ok, nobody, html} = conn |> log_in(nil) |> live("/tasks")
      assert titles(html) == []

      [project | _] = world.projects
      Ash.create!(Task, %{title: "Not for nobody", project_id: project.id}, as(world.admin))

      html = heard(nobody)
      assert titles(html) == []
      assert notice(html) == ""
    end
  end

  describe "the person's own changes" do
    setup %{conn: conn, world: world} do
      task = task(world, "My own")
      {:ok, admin, _html} = conn |> log_in(world.admin) |> live("/tasks")
      %{admin: admin, task: task}
    end

    test "a record they create in the table brings no notice", %{world: world, admin: admin} do
      [project | _] = world.projects
      open_create(admin)
      run_panel(admin, title: "Created here", project_id: project.id)

      html = heard(admin)
      assert titles(html) == ["Created here", "My own"]
      assert notice(html) == ""
    end

    test "are not announced to the table that made them", %{admin: admin, task: task} do
      assert handed(admin, fn -> save(admin, task.id, "title", "Saved here") end) == nothing()
      assert titles(render(admin)) == ["Saved here"]
    end

    # What the table does once what was announced while `fun` ran has
    # been handed to it: the records it reads through Ash, by resource, and
    # the diffs it sends to the browser. Nothing, where the table made the
    # change itself. What `fun` started itself (a read after a create, the
    # footer summaries) is done before it is looked at.
    defp handed(view, fun) do
      fun.()
      render_async(view, 10_000)

      test = self()
      handler = "handed-#{System.unique_integer()}"
      pid = view.pid

      # the reads of the page's process and of what it runs beside it
      :telemetry.attach(
        handler,
        [:ash, :tracker, :read, :stop],
        fn _event, _measurements, metadata, _config ->
          if self() == pid or pid in (Process.get(:"$callers") || []),
            do: send(test, {:handed_read, metadata.resource_short_name})
        end,
        nil
      )

      sent =
        try do
          wire(view, fn ->
            AshDataTable.Test.flush(view)
            render_async(view, 10_000)
          end)
        after
          :telemetry.detach(handler)
        end

      %{reads: handed_reads([]), diffs: length(Regex.scan(~r/event: "diff"/, sent))}
    end

    defp handed_reads(sofar) do
      receive do
        {:handed_read, resource} -> handed_reads([resource | sofar])
      after
        0 -> Enum.reverse(sofar)
      end
    end

    defp nothing, do: %{reads: [], diffs: 0}

    test "are not announced to it, whichever way it writes", %{
      world: world,
      admin: admin,
      task: task
    } do
      [project | _] = world.projects

      # a record another person changes is, for comparison
      assert %{reads: [_ | _], diffs: diffs} =
               handed(admin, fn ->
                 Ash.update!(task, %{title: "By another"}, authorize?: false)
               end)

      assert diffs > 0

      # a cell
      assert handed(admin, fn -> save(admin, task.id, "title", "Saved here") end) == nothing()
      # a cell with an action of its own
      assert handed(admin, fn -> save(admin, task.id, "priority", "urgent") end) == nothing()
      # a row action that runs at once
      assert handed(admin, fn -> act(admin, task.id, "archive") end) == nothing()
      # a row action from its panel
      assert handed(admin, fn ->
               act(admin, task.id, "set_progress")
               run_panel(admin, progress: "55")
             end) == nothing()

      # a reference cell, through the picker
      assert handed(admin, fn ->
               pick(admin, task.id, "assignee")
               picked(admin, world.member.id)
             end) == nothing()

      # a create
      assert handed(admin, fn ->
               open_create(admin)
               run_panel(admin, title: "Created here", project_id: project.id)
             end) == nothing()

      # a destroy
      assert handed(admin, fn -> act(admin, task.id, "destroy") end) == nothing()

      stored = Ash.read!(Task, as(world.admin))
      assert Enum.sort(Enum.map(stored, & &1.title)) == ["Created here"]
    end

    test "an action on the selected rows brings no notice", %{world: world, admin: admin} do
      for n <- 1..30, do: task(world, "Many #{n}")
      html = filter(admin, "task", "title", v: "Many")
      assert text(html, "#task-range") == "1–25 of 30"

      run_bulk(admin, "archive", :all)
      ran(admin)

      html = heard(admin)
      assert notice(html) == ""
    end
  end

  describe "a nested table" do
    setup %{conn: conn, world: world} do
      task = task(world, "With comments")
      other = task(world, "Another task")
      first = comment(world, task, "First comment")
      {:ok, member, _html} = conn |> log_in(world.member) |> live("/tasks")

      expand(member, task.id)
      html = toggle(member, task.id, "comments")
      nested = nested(task.id, "comments")
      assert column(html, nested, "body") == ["First comment"]

      %{member: member, task: task, other: other, first: first, nested: nested}
    end

    test "follows the changes of its own resource, limited to its row",
         %{world: world, member: member, task: task, other: other, first: first, nested: nested} do
      Ash.update!(first, %{body: "First comment, edited"}, as(world.admin))

      html = heard(member)
      assert column(html, nested, "body") == ["First comment, edited"]
      assert notice(html, nested) == ""

      # a comment on another task is none of this table's
      Ash.create!(Comment, %{body: "Elsewhere", task_id: other.id}, as(world.admin))
      assert notice(heard(member), nested) == ""

      Ash.create!(Comment, %{body: "Second comment", task_id: task.id}, as(world.admin))
      html = heard(member)
      assert column(html, nested, "body") == ["First comment, edited"]
      assert notice(html, nested) == @notice
      # the table around it shows tasks, and says nothing
      assert notice(html) == ""

      click(member, "[id='#{nested}-read-again']")
      html = render_async(member, 10_000)
      assert column(html, nested, "body") == ["Second comment", "First comment, edited"]
    end

    test "stays open when its row is changed by another person",
         %{world: world, member: member, task: task, nested: nested} do
      Ash.update!(task, %{title: "With comments, renamed"}, as(world.admin))

      html = heard(member)
      assert titles(html) == ["Another task", "With comments, renamed"]
      assert column(html, nested, "body") == ["First comment"]
    end

    test "goes with its row", %{world: world, member: member, task: task, nested: nested} do
      comments = {Comment, world.organization.id}
      assert listeners(comments) == 1

      Ash.destroy!(task, as(world.admin))

      html = heard(member, [task.id])
      assert titles(html) == ["Another task"]
      assert column(html, nested, "body") == []
      assert listeners(comments) == 0
    end
  end

  describe "tables under a row" do
    setup %{conn: conn, world: world} do
      task = task(world, "With comments", assignee_id: world.member.id)
      task(world, "Another task")
      first = comment(world, task, "First comment")
      {:ok, member, _html} = conn |> log_in(world.member) |> live("/tasks")

      expand(member, task.id)
      toggle(member, task.id, "comments")
      comments = nested(task.id, "comments")

      # and under the comment, the task it is of: a table of tasks at depth 2
      expand(member, comments, first.id)
      html = toggle(member, comments, first.id, "task")
      deep = nested(comments, first.id, "task")
      assert column(html, deep, "title") == ["With comments"]

      %{member: member, task: task, first: first, comments: comments, deep: deep}
    end

    test "stay open, loaded and alive when the row is changed by another person, at depth 2 as well",
         %{world: world, member: member, task: task, first: first, comments: comments, deep: deep} do
      Ash.update!(task, %{title: "With comments, renamed"}, as(world.admin))

      html = heard(member)
      assert titles(html) == ["Another task", "With comments, renamed"]
      assert column(html, comments, "body") == ["First comment"]
      # the task is a row of the table at depth 2 too, which follows for itself
      assert column(html, deep, "title") == ["With comments, renamed"]

      # they go on following: a change of the comment, of the task, and a new comment
      Ash.update!(first, %{body: "First comment, edited"}, as(world.admin))
      html = heard(member)
      assert column(html, comments, "body") == ["First comment, edited"]
      assert column(html, deep, "title") == ["With comments, renamed"]

      Ash.update!(task, %{title: "Renamed once more"}, as(world.admin))
      html = heard(member)
      assert titles(html) == ["Another task", "Renamed once more"]
      assert column(html, comments, "body") == ["First comment, edited"]
      assert column(html, deep, "title") == ["Renamed once more"]

      Ash.create!(Comment, %{body: "Second comment", task_id: task.id}, as(world.admin))
      assert notice(heard(member), comments) == @notice

      # and they can still be used
      html = filter(member, comments, "body", v: "no such comment")
      assert column(html, comments, "body") == []
    end

    test "hold the row while a panel is open in one of them, and let it go when the panel closes",
         %{world: world, member: member, task: task, comments: comments} do
      click(member, "[id='task-row-#{task.id}-l-comments-create']")
      assert panel(render(member), comments).heading == "New comment"

      Ash.update!(task, %{title: "Changed under an open panel"}, as(world.admin))

      html = heard(member)
      assert titles(html) == ["Another task", "With comments"]
      assert panel(html, comments).heading == "New comment"

      cancel_panel(member, comments)
      assert titles(render(member)) == ["Another task", "Changed under an open panel"]
      assert column(render(member), comments, "body") == ["First comment"]
    end

    test "hold every row above a panel, however deep it is open",
         %{world: world, member: member, task: task, first: first, comments: comments, deep: deep} do
      # the panel of a row action of the task at depth 2
      act(member, deep, task.id, "reassign")
      assert panel(render(member), deep).heading =~ "Reassign"

      Ash.update!(task, %{title: "Changed under a deep panel"}, as(world.admin))
      Ash.update!(first, %{body: "Changed too"}, as(world.admin))

      html = heard(member)
      # the task on the page, the comment under it, and the task under that
      assert titles(html) == ["Another task", "With comments"]
      assert column(html, comments, "body") == ["First comment"]
      assert column(html, deep, "title") == ["With comments"]
      assert panel(html, deep).heading =~ "Reassign"

      cancel_panel(member, deep)
      html = render(member)
      assert titles(html) == ["Another task", "Changed under a deep panel"]
      assert column(html, comments, "body") == ["Changed too"]
      assert column(html, deep, "title") == ["Changed under a deep panel"]
    end

    test "keep a row that is gone for as long as a panel is open under it: the panel says so, and then the row goes",
         %{world: world, member: member, task: task, comments: comments} do
      click(member, "[id='task-row-#{task.id}-l-comments-create']")

      Ash.destroy!(task, as(world.admin))

      html = heard(member)
      assert titles(html) == ["Another task", "With comments"]
      assert panel(html, comments).heading == "New comment"

      # what was typed is not lost with the row: the action answers
      html = run_panel(member, comments, body: "Into the void")
      assert panel(html, comments).errors == ["This record is no longer available."]
      assert titles(html) == ["Another task", "With comments"]

      # the panel is closed: the table on the page looks again, and asks
      cancel_panel(member, comments)
      render(member)
      left(member, task.id)
      assert titles(render(member)) == ["Another task"]
    end

    test "let a row go that is closed while something was open under it",
         %{world: world, member: member, task: task, comments: comments} do
      click(member, "[id='task-row-#{task.id}-l-comments-create']")
      Ash.update!(task, %{title: "Changed under an open panel"}, as(world.admin))
      assert titles(heard(member)) == ["Another task", "With comments"]

      # the row is closed, and the panel with it
      html = expand(member, task.id)
      assert titles(html) == ["Another task", "Changed under an open panel"]
    end
  end

  describe "a row that is to go" do
    setup %{conn: conn, world: world} do
      task = task(world, "Going")
      task(world, "Staying")
      {:ok, member, _html} = conn |> log_in(world.member) |> live("/tasks")
      %{member: member, task: task}
    end

    test "is asked about first, and stays until the hook says that no cell of it is edited",
         %{world: world, member: member, task: task} do
      Ash.destroy!(task, as(world.admin))
      AshDataTable.Test.flush(member)

      assert_push_event(member, "ash_data_table:leaving", %{table: "task", row: row})
      assert row == task.id
      assert titles(render(member)) == ["Staying", "Going"]

      # a save from the editor that is open in it answers as for any record that is gone
      save(member, task.id, "title", "Typed meanwhile")
      assert_reply member, %{ok: false, error: "This record is no longer available."}

      html = forge(member, "task", "left", %{"row" => task.id})
      assert titles(html) == ["Staying"]
      assert text(html, "#task-range") == "1–1 of 1"
    end

    test "is the only row the hook can send away", %{member: member, task: task} do
      html = forge(member, "task", "left", %{"row" => task.id})
      assert titles(html) == ["Staying", "Going"]

      html = forge(member, "task", "left", %{"row" => "no-such-row"})
      assert titles(html) == ["Staying", "Going"]
      assert Ash.get!(Task, task.id, authorize?: false).title == "Going"
    end

    test "stays after all when its record is the person's to read again",
         %{world: world, member: member, task: task} do
      # as if announced, for a record the read does return in the end
      Demo.Repo.query!("UPDATE tasks SET organization_id = $1 WHERE id = $2", [
        Ecto.UUID.dump!(world.other_organization.id),
        Ecto.UUID.dump!(task.id)
      ])

      topic = Notifier.topic(Task, world.organization.id)
      message = {:ash_data_table_changed, Task, :update, %{id: task.id}, world.organization.id}
      Phoenix.PubSub.broadcast(Demo.PubSub, topic, message)
      AshDataTable.Test.flush(member)
      assert_push_event(member, "ash_data_table:leaving", %{row: _row})

      Demo.Repo.query!(
        "UPDATE tasks SET organization_id = $1, title = 'Back again' WHERE id = $2",
        [
          Ecto.UUID.dump!(world.organization.id),
          Ecto.UUID.dump!(task.id)
        ]
      )

      Phoenix.PubSub.broadcast(Demo.PubSub, topic, message)
      AshDataTable.Test.flush(member)
      assert titles(render(member)) == ["Staying", "Back again"]

      # the answer to the first question comes late, and sends nothing away
      html = forge(member, "task", "left", %{"row" => task.id})
      assert titles(html) == ["Staying", "Back again"]
    end

    test "is not sent away by a late answer once something is open for it",
         %{world: world, member: member, task: task} do
      move = fn organization ->
        Demo.Repo.query!(
          "UPDATE tasks SET organization_id = $1, assignee_id = $2 WHERE id = $3",
          [
            Ecto.UUID.dump!(organization.id),
            Ecto.UUID.dump!(world.member.id),
            Ecto.UUID.dump!(task.id)
          ]
        )
      end

      # not the member's to read for a moment, in which it is announced
      move.(world.other_organization)

      Phoenix.PubSub.broadcast(
        Demo.PubSub,
        Notifier.topic(Task, world.organization.id),
        {:ash_data_table_changed, Task, :update, %{id: task.id}, world.organization.id}
      )

      AshDataTable.Test.flush(member)
      assert_push_event(member, "ash_data_table:leaving", %{row: _row})
      move.(world.organization)

      # the person opens the action panel for the row before the hook has answered
      act(member, task.id, "reassign")
      assert panel(render(member)).heading =~ "Reassign"

      html = forge(member, "task", "left", %{"row" => task.id})
      assert titles(html) == ["Staying", "Going"]
      assert panel(html).heading =~ "Reassign"

      # and when the panel is closed, the row is read again: it is theirs
      html = cancel_panel(member)
      assert titles(html) == ["Staying", "Going"]
    end
  end

  describe "what is announced while the table is reading" do
    test "is looked at when the read is back", %{conn: conn, world: world} do
      task = task(world, "Changed while reading")
      {:ok, member, _html} = conn |> log_in(world.member) |> live("/tasks")

      # a filter is typed, which reads beside the process, and the change
      # is heard before the rows are back or after: either way the rows
      # show it in the end
      member
      |> form("#task-filters", %{"filter" => %{"title" => %{"v" => "while"}}})
      |> render_change()

      Ash.update!(task, %{title: "Changed while reading, twice"}, as(world.admin))

      assert titles(heard(member)) == ["Changed while reading, twice"]
    end
  end

  describe "listening" do
    test "is one subscription per table, and ends when the table is closed or the page left",
         %{conn: conn, world: world} do
      task = task(world, "With comments")
      comment(world, task, "A comment")

      tasks = {Task, world.organization.id}
      comments = {Comment, world.organization.id}
      projects = {Project, world.organization.id}
      assert {listeners(tasks), listeners(comments)} == {0, 0}

      {:ok, member, _html} = conn |> log_in(world.member) |> live("/tasks")
      assert {listeners(tasks), listeners(comments)} == {1, 0}

      # a sort, a filter and a page change read again, and listen no more often
      filter(member, "task", "title", v: "With")
      assert listeners(tasks) == 1

      expand(member, task.id)
      toggle(member, task.id, "comments")
      assert {listeners(tasks), listeners(comments)} == {1, 1}

      # the projects announce nothing: their nested table does not listen
      toggle(member, task.id, "project")
      assert listeners(projects) == 0
      assert listeners({Project, nil}) == 0

      # the line is closed
      toggle(member, task.id, "comments")
      assert {listeners(tasks), listeners(comments)} == {1, 0}

      # opened again, and the row is closed
      toggle(member, task.id, "comments")
      assert listeners(comments) == 1
      expand(member, task.id)
      assert listeners(comments) == 0

      # opened again, and the table reads again
      expand(member, task.id)
      toggle(member, task.id, "comments")
      assert listeners(comments) == 1
      filter(member, "task", "title", v: "")
      assert {listeners(tasks), listeners(comments)} == {1, 0}

      # the page is left
      expand(member, task.id)
      toggle(member, task.id, "comments")
      assert {listeners(tasks), listeners(comments)} == {1, 1}

      reference = Process.monitor(member.pid)
      GenServer.stop(member.pid)
      assert_receive {:DOWN, ^reference, :process, _pid, _reason}
      assert {listeners(tasks), listeners(comments)} == {0, 0}
    end

    test "is not there for a page that is not connected", %{conn: conn, world: world} do
      conn |> log_in(world.member) |> get("/tasks") |> html_response(200)

      assert listeners({Task, world.organization.id}) == 0
    end

    test "is not there for a resource that announces nothing", %{conn: conn, world: world} do
      {:ok, _view, _html} = conn |> log_in(world.member) |> live("/projects")

      assert listeners({Project, world.organization.id}) == 0
      assert listeners({Project, nil}) == 0
    end
  end

  describe "two tables of one resource on one page (/named)" do
    setup %{conn: conn, world: world} do
      task = task(world, "Commented")
      first = comment(world, task, "First comment")
      second = comment(world, task, "Second comment")

      {:ok, view, html} = conn |> log_in(world.admin) |> live("/named")
      assert column(html, "comment", "body") == ["Second comment", "First comment"]
      assert column(html, "comment_compact", "body") == ["Second comment", "First comment"]

      %{view: view, task: task, first: first, second: second}
    end

    test "an edit in one updates the same row in the other", %{view: view, first: first} do
      save(view, "comment", first.id, "body", "First comment, edited")

      html = heard(view)
      assert column(html, "comment", "body") == ["Second comment", "First comment, edited"]

      assert column(html, "comment_compact", "body") == [
               "Second comment",
               "First comment, edited"
             ]

      assert notice(html, "comment") == ""
      assert notice(html, "comment_compact") == ""
    end

    test "a record created in one is announced in the other, which reads it on request",
         %{view: view, task: task} do
      open_create(view, "comment")
      run_panel(view, "comment", %{"body" => "Third comment", "task_id" => task.id})

      html = heard(view)
      assert hd(column(html, "comment", "body")) == "Third comment"
      assert notice(html, "comment") == ""

      assert column(html, "comment_compact", "body") == ["Second comment", "First comment"]
      assert notice(html, "comment_compact") == @notice

      view |> element("#comment_compact-read-again") |> render_click()
      html = render_async(view, 10_000)

      assert column(html, "comment_compact", "body") ==
               ["Third comment", "Second comment", "First comment"]

      assert notice(html, "comment_compact") == ""
    end

    test "a record destroyed in one goes from the other", %{view: view, second: second} do
      act(view, "comment", second.id, "destroy")

      html = heard(view, [second.id])
      assert column(html, "comment", "body") == ["First comment"]
      assert column(html, "comment_compact", "body") == ["First comment"]
    end

    test "says what to try", %{view: view} do
      assert text(render(view), "#named-live") =~ "Change a comment"
    end
  end
end
