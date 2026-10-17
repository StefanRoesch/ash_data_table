defmodule DemoWeb.Tables.BulkElsewhereTest do
  @moduledoc """
  Row selection and the actions on the selected rows in the other tables:
  an action that the block keeps to one row (`/projects`), a primary key of
  two attributes (`/task_labels`), keyset pages (`/comments`), a nested
  table and its full view, and tables of resources that exist for the tests
  only (`test/support/bulk_tables.ex`, `test/support/plain_tables.ex`):
  read actions that do not count or cannot be read without a page, inputs a
  person may not see, an action that fails underneath, and tables that are
  told to let their rows be selected.

  `/tasks` is in `task_bulk_test.exs`.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Support.Bulk.{Crate, Letter, Parcel, Pouch, Slot, Tally}
  alias Demo.Support.Plain.Order
  alias Demo.Tracker.{Comment, Project, TaskLabel}

  @moment ~U[2026-01-01 12:00:00.000000Z]

  defp number(n), do: String.pad_leading("#{n}", 2, "0")

  defp task(world, title) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        organization_id: world.organization.id,
        project_id: project.id,
        reporter_id: world.admin.id,
        title: title,
        inserted_at: @moment
      )
    )
  end

  defp comment(task, author, body, minutes \\ 0) do
    Generator.generate(
      Generator.comment(
        organization_id: task.organization_id,
        task_id: task.id,
        author_id: author.id,
        body: body,
        inserted_at: DateTime.add(@moment, minutes, :minute)
      )
    )
  end

  defp bodies, do: Comment |> Ash.read!(authorize?: false) |> Enum.map(& &1.body) |> Enum.sort()

  describe "an action the block keeps to one row" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      conn = log_in(conn, world.admin)
      {:ok, view, html} = live(conn, "/projects")

      %{view: view, html: html, world: world}
    end

    test "has its button in the row, and none on the line", %{html: html, world: world} do
      [project | _] = world.projects

      assert actions(html, "project", project.id) == [
               "Set status",
               "Set budget",
               "Destroy",
               "Assign open tasks"
             ]

      assert [
               "Select all " <> _,
               "Clear selection",
               "Set status",
               "Set budget",
               "Assign open tasks"
             ] =
               selection(html, "project").buttons
    end

    test "is not run for selected rows by an event that names it", %{view: view, world: world} do
      [project | _] = world.projects

      for selection <- [[project.id], :all] do
        bulk(view, "project", "destroy", selection)
        assert_reply view, %{ok: false}
        html = run_bulk(view, "project", "destroy", selection)
        assert bulk_result(html, "project") == nil
      end

      assert length(Ash.read!(Project, authorize?: false, tenant: world.organization.id)) ==
               length(world.projects)
    end

    test "the other runs on the selected rows, with the choice its panel asks for once",
         %{view: view, world: world} do
      [first, second | _] = world.projects

      html = bulk(view, "project", "set_status", [first.id, second.id])

      assert %{
               heading: "Set status: 2 records",
               # a choice that is empty until the person makes it: not the
               # state a new project would have
               fields: [%{name: "status", control: "select", value: "", required?: true}]
             } = panel(html, "project")

      # left empty, the action refuses it at the field, and nothing runs
      html = run_panel(view, "project", status: "")
      assert [%{errors: ["is required"]}] = panel(html, "project").fields

      run_panel(view, "project", status: "on_hold")
      html = ran(view)

      assert bulk_result(html, "project") == %{summary: "Set status: 2 done.", failures: []}
      assert Ash.get!(Project, first.id, authorize?: false).status == :on_hold
      assert Ash.get!(Project, second.id, authorize?: false).status == :on_hold
    end
  end

  describe "rows with a primary key of two attributes" do
    setup %{conn: conn} do
      world = world(tasks: 1, labels: 3)
      [task] = world.tasks
      labels = Enum.sort_by(world.labels, & &1.id)

      Demo.Repo.delete_all(TaskLabel)

      for label <- labels do
        Generator.generate(
          Generator.task_label(
            organization_id: world.organization.id,
            task_id: task.id,
            label_id: label.id
          )
        )
      end

      conn = log_in(conn, world.admin)
      {:ok, view, html} = live(conn, "/task_labels")

      %{view: view, html: html, world: world, task: task, labels: labels}
    end

    defp left(world) do
      TaskLabel
      |> Ash.read!(authorize?: false, tenant: world.organization.id, page: [limit: 100])
      |> Map.fetch!(:results)
      |> Enum.map(& &1.label_id)
      |> Enum.sort()
    end

    test "say what the hook names them by: the values of the key, in its order",
         %{html: html, task: task, labels: [first | _]} do
      assert [named] = attribute(html, "[id='task_label-row-#{task.id}-#{first.id}']", "data-key")
      assert Phoenix.json_library().decode!(named) == [task.id, first.id]
    end

    test "are run on by those values, and a row on which it did not run comes back with them",
         %{view: view, world: world, task: task, labels: [first, second, third]} do
      gone = Ash.UUID.generate()

      # "Remove" asks nothing by itself (`confirm false`); for several rows it asks
      bulk(view, "task_label", "destroy", [[task.id, first.id], [task.id, third.id]])
      assert_reply view, %{ask: "Run “Remove” on 2 records?"}

      html =
        run_bulk(view, "task_label", "destroy", [
          [task.id, first.id],
          [task.id, third.id],
          [task.id, gone],
          # one value is no key of two
          task.id
        ])

      assert left(world) == [second.id]

      assert bulk_result(html, "task_label") == %{
               summary: "Remove: 2 done, 2 not done.",
               failures: ["This record is no longer available. (2)"]
             }

      assert_push_event view, "ash_data_table:select", %{table: "task_label", rows: failed}
      assert failed == [["#{task.id}-#{gone}", [task.id, gone]]]
    end
  end

  describe "a table that pages by keyset" do
    setup %{conn: conn} do
      world = world(tasks: 0, comments: 0)
      task = task(world, "Write the report")

      for n <- 1..45 do
        author = if rem(n, 3) == 0, do: world.member, else: world.admin
        comment(task, author, "Comment #{number(n)}", n)
      end

      %{conn: conn, world: world, task: task}
    end

    test "runs on all that match, through all of its pages", %{conn: conn, world: world} do
      {:ok, view, html} = conn |> log_in(world.admin) |> live("/comments")

      assert length(column(html, "comment", "body")) == 20

      assert %{more?: true, buttons: ["Select all 45 that match" | _]} =
               selection(html, "comment")

      bulk(view, "comment", "destroy", :all)
      assert_reply view, %{ask: "Delete this comment? 45 records are selected."}

      html = run_bulk(view, "comment", "destroy", :all)

      assert bulk_result(html, "comment") == %{summary: "Destroy: 45 done.", failures: []}
      assert bodies() == []
    end

    test "and on those of them only that the person may run it on", %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/comments")

      html = run_bulk(view, "comment", "destroy", :all)

      # every third comment is the member's own
      assert bulk_result(html, "comment") == %{
               summary: "Destroy: 15 done, 30 not done.",
               failures: ["You are not allowed to do this. (30)"]
             }

      assert length(bodies()) == 30
      refute "Comment 03" in bodies()
      assert_push_event view, "ash_data_table:select", %{table: "comment", rows: failed}
      assert length(failed) == 30
    end
  end

  describe "a nested table" do
    setup %{conn: conn} do
      world = world(tasks: 0, comments: 0)
      task = task(world, "Write the report")
      other = task(world, "File the report")

      for n <- 1..3, do: comment(task, world.admin, "On the report #{n}", n)
      elsewhere = comment(other, world.admin, "On the filing")

      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      html = toggle(view, task.id, "comments")

      %{
        view: view,
        html: html,
        world: world,
        task: task,
        other: other,
        elsewhere: elsewhere,
        comments: nested("task", task.id, "comments")
      }
    end

    test "has its own boxes and its own line, as the table of its resource has",
         %{html: html, comments: comments} do
      assert attribute(html, "[id='#{comments}-table']", "aria-multiselectable") == ["true"]

      assert attribute(html, "[id='#{comments}-select-head'] > input", "aria-label") ==
               ["Select all rows of this page"]

      assert %{buttons: ["Select all 3 that match", "Clear selection", "Destroy"], more?: false} =
               selection(html, comments)

      # and the table around it has its own
      assert attribute(html, "[id='task-selection']", "id") == ["task-selection"]
    end

    test "runs on its own selected rows, and leaves the table around it alone",
         %{view: view, comments: comments} do
      first = Enum.find(Ash.read!(Comment, authorize?: false), &(&1.body == "On the report 1"))

      html = run_bulk(view, comments, "destroy", [first.id])

      assert bulk_result(html, comments) == %{summary: "Destroy: 1 done.", failures: []}
      assert bulk_result(html, "task") == nil
      assert bodies() == ["On the filing", "On the report 2", "On the report 3"]
      assert_push_event view, "ash_data_table:select", %{table: ^comments, rows: []}
      # the row is still expanded, with what is left under it
      assert column(html, comments, "body") == ["On the report 3", "On the report 2"]
    end

    test "does not run on a record that is not one of its rows, though the person may read and change it elsewhere",
         %{view: view, comments: comments, elsewhere: elsewhere} do
      html = run_bulk(view, comments, "destroy", [elsewhere.id])

      assert "On the filing" in bodies()

      assert bulk_result(html, comments) == %{
               summary: "Destroy: 0 done, 1 not done.",
               failures: ["This record is no longer available. (1)"]
             }
    end

    test "all that match are the records under its row, and no others",
         %{view: view, comments: comments} do
      bulk(view, comments, "destroy", :all)
      assert_reply view, %{ask: "Delete this comment? 3 records are selected."}

      html = run_bulk(view, comments, "destroy", :all)

      assert bulk_result(html, comments) == %{summary: "Destroy: 3 done.", failures: []}
      assert bodies() == ["On the filing"]
    end

    test "all that match are what its own filters match", %{view: view, comments: comments} do
      filter(view, comments, "body", v: "report 2")
      html = run_bulk(view, comments, "destroy", :all)

      assert bulk_result(html, comments) == %{summary: "Destroy: 1 done.", failures: []}
      assert bodies() == ["On the filing", "On the report 1", "On the report 3"]
    end

    test "runs nothing once the row it belongs to is gone", context do
      %{view: view, comments: comments, task: task, elsewhere: elsewhere} = context
      first = Enum.find(Ash.read!(Comment, authorize?: false), &(&1.body == "On the report 1"))

      # its comments go with it; the one under the other task stays
      Demo.Repo.query!("DELETE FROM tasks WHERE id = $1", [Ecto.UUID.dump!(task.id)])

      html = run_bulk(view, comments, "destroy", [first.id, elsewhere.id])

      assert bodies() == ["On the filing"]

      assert bulk_result(html, comments) == %{
               summary: "Destroy: 0 done, 2 not done.",
               failures: ["This record is no longer available. (2)"]
             }

      # the table has read again, and says so itself
      assert text(html, "[id='#{comments}-error']") == "This record is no longer available."
    end
  end

  describe "the full view of a nested table" do
    test "all that match are the records of its row", %{conn: conn} do
      world = world(tasks: 0, comments: 0)
      task = task(world, "Write the report")
      other = task(world, "File the report")
      for n <- 1..3, do: comment(task, world.admin, "On the report #{n}", n)
      comment(other, world.admin, "On the filing")

      {:ok, view, html} =
        conn |> log_in(world.admin) |> live("/comments?comment[of][task][comments]=#{task.id}")

      assert text(html, "#comment-related-heading") == "Write the report: Comments"

      html = run_bulk(view, "comment", "destroy", :all)

      assert bulk_result(html, "comment") == %{summary: "Destroy: 3 done.", failures: []}
      assert bodies() == ["On the filing"]

      # without the limit it is another table to select in: what was
      # selected is given up
      select(view, "comment", :all)
      render_patch(view, "/comments")
      assert_push_event view, "ash_data_table:select", %{table: "comment", all: false, rows: []}
    end
  end

  describe "a table whose read action does not count" do
    setup do
      for n <- 1..8 do
        Parcel
        |> Ash.Changeset.for_create(:create, %{
          title: "Parcel #{number(n)}",
          fragile: n in [2, 7]
        })
        |> Ash.create!()
      end

      on_exit(fn -> Demo.Support.Ets.stop(Parcel) end)
    end

    defp shipped do
      for %{shipped: true, title: title} <- Ash.stream!(Parcel), do: title
    end

    test "offers all that match without a number, and asks without one", %{conn: conn} do
      {:ok, view, html} = live(conn, "/support/parcels")

      assert column(html, "parcel", "title") == ["Parcel 01", "Parcel 02", "Parcel 03"]

      assert selection(html, "parcel") == %{
               buttons: ["Select all that match", "Clear selection", "Ship"],
               more?: true,
               selected: "{n} selected",
               all: "All that match are selected"
             }

      bulk(view, "parcel", "ship", :all)
      assert_reply view, %{ask: "Run “Ship” on all records that match?"}
    end

    test "has no more to offer on a page that is all there is", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/support/parcels")

      html = filter(view, "parcel", "title", v: "Parcel 08")
      refute selection(html, "parcel").more?
    end

    test "runs on all that match through all of its pages, a page of the action at a time",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/support/parcels")

      html = run_bulk(view, "parcel", "ship", :all)

      # the action reads three at a time and no more; the fragile ones are refused
      assert bulk_result(html, "parcel") == %{
               summary: "Ship: 6 done, 2 not done.",
               failures: ["is fragile (2)"]
             }

      assert Enum.sort(shipped()) ==
               for(n <- [1, 3, 4, 5, 6, 8], do: "Parcel #{number(n)}")
    end

    test "tells the resource's notifiers of every record it ran on, as the action does from a row",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/support/parcels")
      Process.register(self(), Demo.Support.Bulk.Heard)

      run_bulk(view, "parcel", "ship", :all)

      heard =
        for _n <- 1..6 do
          assert_receive {:heard, :ship, title}
          title
        end

      assert Enum.sort(heard) == for(n <- [1, 3, 4, 5, 6, 8], do: "Parcel #{number(n)}")
      # and of none it was refused on
      refute_receive {:heard, :ship, _title}, 50
    end

    test "runs on rows that are named, more of them than a page of the action holds",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/support/parcels")
      ids = for parcel <- Ash.stream!(Parcel), not parcel.fragile, do: parcel.id

      html = run_bulk(view, "parcel", "ship", ids)

      assert bulk_result(html, "parcel") == %{summary: "Ship: 6 done.", failures: []}
    end
  end

  describe "a table whose read action cannot be read without a page" do
    setup do
      for n <- 1..7 do
        Crate
        |> Ash.Changeset.for_create(:create, %{title: "Crate #{number(n)}"})
        |> Ash.create!()
      end

      on_exit(fn -> Demo.Support.Ets.stop(Crate) end)
    end

    test "runs on all that match, and on rows that are named", %{conn: conn} do
      {:ok, view, html} = live(conn, "/support/crates")

      assert %{more?: true, buttons: ["Select all 7 that match" | _]} = selection(html, "crate")

      html = filter(view, "crate", "title", v: "Crate 0")
      assert column(html, "crate", "sealed") == ["–No", "–No", "–No"]

      html = run_bulk(view, "crate", "seal", :all)
      assert bulk_result(html, "crate") == %{summary: "Seal: 7 done.", failures: []}
      assert column(html, "crate", "sealed") == ["✓Yes", "✓Yes", "✓Yes"]
    end
  end

  describe "while an action runs on the selected rows" do
    setup %{conn: conn} do
      crates =
        for n <- 1..2 do
          Crate
          |> Ash.Changeset.for_create(:create, %{title: "Crate #{number(n)}"})
          |> Ash.create!()
        end

      on_exit(fn -> Demo.Support.Ets.stop(Crate) end)

      {:ok, view, _html} = live(conn, "/support/crates")
      %{view: view, crates: crates}
    end

    test "the grid is busy, the buttons of the line say that they are not to be used, and the page answers",
         %{view: view, crates: [first, _second]} do
      select(view, "crate", [first.id])
      html = confirm_bulk(view, "crate", "weigh")

      assert attribute(html, "#crate-table", "aria-busy") == ["true"]
      assert attribute(html, "#crate-bulk-seal", "aria-disabled") == ["true"]
      assert attribute(html, "#crate-bulk-weigh", "aria-disabled") == ["true"]
      # not `disabled`: a button that is disabled drops the focus
      assert attribute(html, "#crate-bulk-seal", "disabled") == []
      assert bulk_result(html, "crate") == nil

      # the page is in use meanwhile
      html = view |> element("#crate-head-title") |> render_click()
      assert column(html, "crate", "title") == ["Crate 01", "Crate 02"]

      html = ran(view)
      assert bulk_result(html, "crate") == %{summary: "Weigh: 1 done.", failures: []}
      assert attribute(html, "#crate-table", "aria-busy") == []
      assert attribute(html, "#crate-bulk-seal", "aria-disabled") == []
    end

    test "a run that goes down says that it could not be done, leaves the selection alone, and the table works on",
         %{view: view, crates: [first, second]} do
      {html, log} =
        ExUnit.CaptureLog.with_log(fn -> run_bulk(view, "crate", "topple", [first.id]) end)

      assert bulk_result(html, "crate") == %{
               summary: "Topple failed: This could not be done.",
               failures: []
             }

      assert announcement(html, "crate") == "Topple failed: This could not be done."
      assert log =~ "running `topple` on the selected rows of Demo.Support.Bulk.Crate failed"
      assert log =~ "toppled"
      refute html =~ "toppled"

      # the hook is told nothing of the rows: what was selected stays so
      refute_push_event view, "ash_data_table:select", %{table: "crate"}

      assert attribute(html, "#crate-table", "aria-busy") == []
      html = run_bulk(view, "crate", "seal", [second.id])
      assert bulk_result(html, "crate") == %{summary: "Seal: 1 done.", failures: []}
    end

    test "no other runs on that table: one is neither asked for nor run",
         %{view: view, crates: [first, second]} do
      # the token of the second selection, asked for before the first runs
      select(view, "crate", [second.id])
      token = bulk_token(view, "crate", "seal")

      select(view, "crate", [first.id])
      confirm_bulk(view, "crate", "weigh")

      bulk(view, "crate", "seal", [second.id])
      assert_reply view, %{ok: false}

      select(view, "crate", [second.id])
      forge(view, "crate", "bulk_run", %{"action" => "seal", "selection" => token})

      html = ran(view)

      # what it says is what the first one came to, and nothing was sealed
      assert bulk_result(html, "crate") == %{summary: "Weigh: 1 done.", failures: []}
      assert column(html, "crate", "sealed") == ["–No", "–No"]

      # afterwards the table runs again
      html = run_bulk(view, "crate", "seal", [second.id])
      assert bulk_result(html, "crate") == %{summary: "Seal: 1 done.", failures: []}
    end
  end

  describe "a record that the table does not show a person, and that they could change" do
    setup %{conn: conn} do
      pouch = Pouch |> Ash.Changeset.for_create(:create, %{title: "A pouch"}) |> Ash.create!()

      letters =
        for {title, attributes} <- [
              {"Open", %{}},
              {"Sealed", %{sealed: true}},
              {"Filed", %{filed: true}}
            ],
            into: %{} do
          letter =
            Letter
            |> Ash.Changeset.for_create(
              :create,
              Map.merge(attributes, %{title: title, pouch_id: pouch.id})
            )
            |> Ash.create!(authorize?: false)

          {title, letter}
        end

      on_exit(fn ->
        Demo.Support.Ets.stop(Letter)
        Demo.Support.Ets.stop(Pouch)
      end)

      {:ok, view, html} = live(conn, "/support/letters")
      %{conn: conn, view: view, html: html, letters: letters, pouch: pouch}
    end

    defp stamps do
      Letter |> Ash.read!(authorize?: false) |> Map.new(&{&1.title, &1.stamps})
    end

    test "is no row of the table, though nothing but the reading keeps the person from it",
         %{html: html, letters: letters} do
      assert column(html, "letter", "title") == ["Open"]

      # everybody may stamp every letter
      for {_title, letter} <- letters do
        assert Ash.can?({letter, :stamp}, nil)
      end
    end

    test "is not run on by its key: neither one a policy keeps from being read, nor one the table's read action leaves out",
         %{view: view, letters: letters} do
      ids = for title <- ["Sealed", "Filed", "Open"], do: letters[title].id

      html = run_bulk(view, "letter", "stamp", ids)

      assert stamps() == %{"Open" => 1, "Sealed" => 0, "Filed" => 0}

      assert bulk_result(html, "letter") == %{
               summary: "Stamp: 1 done, 2 not done.",
               failures: ["This record is no longer available. (2)"]
             }
    end

    test "is not among all that match", %{view: view} do
      html = run_bulk(view, "letter", "stamp", :all)

      assert stamps() == %{"Open" => 1, "Sealed" => 0, "Filed" => 0}
      assert bulk_result(html, "letter") == %{summary: "Stamp: 1 done.", failures: []}
    end

    test "nor in a nested table, by its key or among all that match",
         %{conn: conn, letters: letters, pouch: pouch} do
      {:ok, view, _html} = live(conn, "/support/pouches")
      expand(view, "pouch", pouch.id)
      html = toggle(view, "pouch", pouch.id, "letters")
      nested = nested("pouch", pouch.id, "letters")
      assert column(html, nested, "title") == ["Open"]

      ids = for title <- ["Sealed", "Filed", "Open"], do: letters[title].id
      html = run_bulk(view, nested, "stamp", ids)

      assert stamps() == %{"Open" => 1, "Sealed" => 0, "Filed" => 0}

      assert bulk_result(html, nested) == %{
               summary: "Stamp: 1 done, 2 not done.",
               failures: ["This record is no longer available. (2)"]
             }

      run_bulk(view, nested, "stamp", :all)
      assert stamps() == %{"Open" => 2, "Sealed" => 0, "Filed" => 0}
    end
  end

  describe "the inputs of an action on the selected rows, and fields a person may not see" do
    @admin %{id: "ada", name: "ada", role: :admin}
    @member %{id: "max", name: "max", role: :member}

    setup do
      on_exit(fn -> Demo.Support.Ets.stop(Order) end)
    end

    defp order(attributes) do
      Order
      |> Ash.Changeset.for_create(
        :create,
        Map.merge(
          %{title: "An order", note: "Long enough", amount: 100, code: "C-100", owner: "max"},
          attributes
        )
      )
      |> Ash.create!(authorize?: false)
    end

    defp stored(order), do: Ash.get!(Order, order.id, authorize?: false)

    defp open(conn, actor) do
      conn
      |> Phoenix.ConnTest.init_test_session(%{"assigns" => %{current_user: actor}})
      |> live("/support/orders")
    end

    defp fields(html), do: Enum.map(panel(html, "order").fields, &{&1.name, &1.value})

    test "are all of the action's for a person who sees every field on every record",
         %{conn: conn} do
      one = order(%{title: "One"})
      two = order(%{title: "Two", owner: "ada"})
      {:ok, view, _html} = open(conn, @admin)

      # empty: there is no one record to take a value from
      assert fields(bulk(view, "order", "revise", [one.id, two.id])) ==
               [{"title", ""}, {"note", ""}, {"amount", ""}, {"code", ""}]
    end

    test "are without a field the person never sees, and without one they see on some records only",
         %{conn: conn} do
      own = order(%{title: "Mine", owner: "max"})
      foreign = order(%{title: "Hers", owner: "ada", amount: 777, code: "C-777"})
      {:ok, view, _html} = open(conn, @member)

      # `code` is an admin's; `amount` is seen on a person's own orders, and
      # a selection may hold any order: on one row it is a field (see
      # `action_fields_test.exs`), on several it is none
      html = bulk(view, "order", "revise", [own.id, foreign.id])
      assert fields(html) == [{"title", ""}, {"note", ""}]

      # the same when every selected order is their own: the table does not
      # read the records to open a panel
      cancel_panel(view, "order")
      assert fields(bulk(view, "order", "revise", [own.id])) == [{"title", ""}, {"note", ""}]
    end

    test "are taken by their names: a hidden field is not written, whatever is sent for it",
         %{conn: conn} do
      own = order(%{title: "Mine", owner: "max"})
      foreign = order(%{title: "Hers", owner: "ada", amount: 777, code: "C-777"})
      {:ok, view, _html} = open(conn, @member)

      bulk(view, "order", "revise", [own.id, foreign.id])

      send_panel(view, "order", %{
        "panel" => %{
          "title" => "Revised",
          "note" => "By the member",
          "amount" => "1",
          "code" => "C-1"
        }
      })

      html = ran(view)
      assert bulk_result(html, "order") == %{summary: "Revise: 2 done.", failures: []}

      assert %Order{title: "Revised", note: "By the member", amount: 100, code: "C-100"} =
               stored(own)

      assert %Order{title: "Revised", note: "By the member", amount: 777, code: "C-777"} =
               stored(foreign)
    end

    test "a required field that is left empty is the action's to refuse, at the field and before anything runs",
         %{conn: conn} do
      one = order(%{title: "One"})
      two = order(%{title: "Two"})
      {:ok, view, _html} = open(conn, @admin)

      bulk(view, "order", "revise", [one.id, two.id])
      html = run_panel(view, "order", title: "", note: "", amount: "", code: "")

      assert %{errors: [], fields: [%{name: "title", errors: ["is required"]} | _]} =
               panel(html, "order")

      assert bulk_result(html, "order") == nil
      assert %Order{title: "One", note: "Long enough"} = stored(one)

      # the fields that may be empty are given empty, on every record
      run_panel(view, "order", title: "Revised", note: "", amount: "", code: "")
      html = ran(view)

      assert bulk_result(html, "order") == %{summary: "Revise: 2 done.", failures: []}
      assert %Order{title: "Revised", note: nil, amount: nil, code: nil} = stored(one)
      assert %Order{title: "Revised", note: nil, amount: nil, code: nil} = stored(two)
    end
  end

  describe "an action that fails on the selected rows" do
    setup %{conn: conn} do
      on_exit(fn -> Demo.Support.Ets.stop(Order) end)

      orders =
        for {title, note} <- [{"One", "Long enough"}, {"Two", "No"}, {"Three", "Long enough"}] do
          Order
          |> Ash.Changeset.for_create(:create, %{title: title, note: note, owner: "max"})
          |> Ash.create!(authorize?: false)
        end

      {:ok, view, _html} =
        conn
        |> Phoenix.ConnTest.init_test_session(%{
          "assigns" => %{current_user: %{id: "ada", name: "ada", role: :admin}}
        })
        |> live("/support/orders")

      %{view: view, ids: Enum.map(orders, & &1.id)}
    end

    test "about a field, on one of them: the field is named as its column is",
         %{view: view, ids: ids} do
      html = run_bulk(view, "order", "stamp", ids)

      assert bulk_result(html, "order") == %{
               summary: "Stamp: 2 done, 1 not done.",
               failures: ["Note: must have length of at least 3 (1)"]
             }
    end

    test "about no field, on all of them: the action's message, once, with their number",
         %{view: view, ids: ids} do
      html = run_bulk(view, "order", "check", ids)

      assert bulk_result(html, "order") == %{
               summary: "Check: 0 done, 3 not done.",
               failures: ["the books are closed (3)"]
             }

      assert_push_event view, "ash_data_table:select", %{rows: failed}
      assert Enum.sort(failed) == Enum.sort(Enum.map(ids, &[&1, nil]))
    end

    test "underneath: the table says that it could not be done, and the rest is for the log",
         %{view: view, ids: ids} do
      {html, log} = ExUnit.CaptureLog.with_log(fn -> run_bulk(view, "order", "jam", ids) end)

      assert bulk_result(html, "order") == %{
               summary: "Jam: 0 done, 3 not done.",
               failures: ["This could not be done. (3)"]
             }

      refute html =~ "10.0.0.7"
      assert log =~ "the vault at 10.0.0.7 did not answer"
    end
  end

  describe "a table that is told to let its rows be selected" do
    setup %{conn: conn} do
      for title <- ["Slot A", "Slot B"] do
        Slot |> Ash.Changeset.for_create(:create, %{title: title}) |> Ash.create!()
      end

      Tally |> Ash.Changeset.for_create(:create, %{title: "A tally"}) |> Ash.create!()

      on_exit(fn ->
        Demo.Support.Ets.stop(Slot)
        Demo.Support.Ets.stop(Tally)
      end)

      {:ok, view, html} = live(conn, "/support/select")
      %{view: view, html: html}
    end

    test "one at a time: a radio button in every row, of one group, none for the page, no line, and a grid that says it is not multi-selectable",
         %{html: html} do
      assert attribute(html, "#pick-grid", "data-select") == ["single"]
      assert attribute(html, "#pick-table", "aria-multiselectable") == ["false"]

      assert attribute(html, "#pick-table [role=gridcell][data-selector] > input", "type") ==
               ["radio", "radio"]

      assert attribute(html, "#pick-table [role=gridcell][data-selector] > input", "name") ==
               ["pick-select", "pick-select"]

      assert attribute(html, "#pick-table [role=gridcell][data-selector] > input", "aria-label") ==
               ["Select row", "Select row"]

      # told to let rows be selected, and not that it is one to choose from
      assert attribute(html, "#pick-grid", "data-choose") == []

      # the column has a header, which names it and stands for nothing
      assert text(html, "#pick-select-head") == "Select row"
      assert attribute(html, "#pick-select-head", "data-select-page") == []
      assert attribute(html, "#pick-select-head input", "type") == []
      assert selection(html, "pick") == nil
      assert attribute(html, "#pick-table", "aria-colcount") == ["2"]
    end

    test "several at a time, without an action to run on them: the boxes and the line, with no action on it",
         %{html: html} do
      assert attribute(html, "#pile-grid", "data-select") == ["multi"]
      assert attribute(html, "#pile-table", "aria-multiselectable") == ["true"]
      assert attribute(html, "#pile-select-head", "data-select-page") == [""]
      assert selection(html, "pile").buttons == ["Select all 2 that match", "Clear selection"]
    end

    test "and runs nothing for it", %{view: view} do
      [slot | _] = Ash.read!(Slot)

      bulk(view, "pile", "destroy", [slot.id])
      assert_reply view, %{ok: false}
      run_bulk(view, "pile", "read", :all)

      assert length(Ash.read!(Slot)) == 2
    end

    test "is not, where it is told nothing and has no action to run on several rows",
         %{html: html} do
      assert attribute(html, "#plain-grid", "data-select") == []
      assert attribute(html, "#plain-table [role=gridcell]", "role") != []
      assert attribute(html, "#plain-table [role=gridcell][data-selector]", "id") == []
      assert selection(html, "plain") == nil
      assert attribute(html, "#plain-table", "aria-colcount") == ["1"]
    end

    test "nor where its records have no primary key, whatever it is told", %{html: html} do
      assert column(html, "tally", "title") == ["A tally"]
      assert attribute(html, "#tally-grid", "data-select") == []
      assert attribute(html, "#tally-table [role=gridcell]", "role") != []
      assert attribute(html, "#tally-table [role=gridcell][data-selector]", "id") == []
      assert selection(html, "tally") == nil
    end
  end
end
