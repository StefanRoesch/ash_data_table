defmodule DemoWeb.Tables.DeadlineTableTest do
  @moduledoc """
  The mounted table of `Demo.Tracker.Deadline` at `/deadlines`, on Postgres:
  a table whose read action requires an argument, the day, which a person
  gives in the argument line. Its records are the tasks'.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  defp in_days(days), do: Date.add(Date.utc_today(), days)
  defp iso(days), do: Date.to_iso8601(in_days(days))

  setup %{conn: conn} do
    world = world(tasks: 0)
    [project | _] = world.projects

    tasks =
      for {title, days, status} <- [
            {"Soon", 2, :todo},
            {"Later", 10, :in_progress},
            {"Much later", 100, :todo},
            {"Done already", 1, :done}
          ] do
        Generator.generate(
          Generator.task(
            organization_id: world.organization.id,
            project_id: project.id,
            reporter_id: world.admin.id,
            assignee_id: world.member.id,
            title: title,
            due_on: in_days(days),
            status: status,
            tags: if(title == "Later", do: ["api", "mobile"], else: ["docs"])
          )
        )
      end

    [soon | _] = tasks

    Generator.generate_many(
      Generator.comment(
        task_id: soon.id,
        organization_id: world.organization.id,
        author_id: world.admin.id
      ),
      3
    )

    %{world: world, tasks: tasks, soon: soon, conn: log_in(conn, world.admin)}
  end

  defp titles(html), do: column(html, "deadline", "title")

  describe "until the day is given" do
    test "the table asks for it in place of its rows", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/deadlines")

      assert text(html, "#deadline-fill") == "Fill in Due by to see records."
      assert text(html, "#deadline-empty") == nil
      assert text(html, "#deadline-error") == nil
      assert titles(html) == []
      assert announcement(html, "deadline") == "Fill in Due by to see records."
    end

    test "the line has the day, under the label the block gives it, the argument with a default, and the list",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, "/deadlines")

      assert Enum.map(
               arguments(html, "deadline"),
               &{&1.name, &1.label, &1.control, &1.value, &1.required?}
             ) == [
               {"by", "Due by", "date", "", true},
               {"include_done?", "Include done?", "checkbox", "false", false},
               {"tags", "Tags", "list", [], false}
             ]
    end

    test "in German", %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.admin) |> in_locale("de") |> live("/deadlines")

      assert text(html, "#deadline-fill") == "Fällig bis ausfüllen, um Datensätze zu sehen."
    end
  end

  describe "once the day is given" do
    test "the rows are what the action returns for it, and the day is in the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/deadlines")

      html = argue(view, "deadline", a: %{"by" => iso(30)})

      assert titles(html) == ["Soon", "Later"]
      assert text(html, "#deadline-fill") == nil
      assert text(html, "#deadline-range") == "1–2 of 2"
      assert announcement(html, "deadline") == "2 results"
      assert assert_patch(view) == "/deadlines?deadline[a][by]=#{iso(30)}"
    end

    test "the page can be opened by its URL", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/deadlines?deadline[a][by]=#{iso(200)}")

      assert titles(html) == ["Soon", "Later", "Much later"]
      assert [%{value: value} | _] = arguments(html, "deadline")
      assert value == iso(200)
    end

    test "the argument with a default is given when its box is ticked", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/deadlines?deadline[a][by]=#{iso(30)}")

      html = argue(view, "deadline", a: %{"include_done?" => "true"})

      assert titles(html) == ["Done already", "Soon", "Later"]

      assert assert_patch(view) ==
               "/deadlines?deadline[a][by]=#{iso(30)}&deadline[a][include_done%3F]=true"
    end

    test "a list is given value by value, on Postgres too", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/deadlines?deadline[a][by]=#{iso(30)}")

      view |> element("#deadline-arg-tags-add") |> render_click()
      html = argue(view, "deadline", a: %{"tags" => ["", "mobile"]})

      assert titles(html) == ["Later"]

      view |> element("#deadline-arg-tags-add") |> render_click()
      html = argue(view, "deadline", a: %{"tags" => ["", "mobile", "docs"]})

      assert titles(html) == ["Soon", "Later"]

      assert assert_patch(view) ==
               "/deadlines?deadline[a][by]=#{iso(30)}&deadline[a][tags][]=mobile"
    end

    test "what is loaded onto the rows is loaded through the action with the day: an aggregate, a reference cell",
         %{conn: conn, world: world} do
      {:ok, _view, html} = live(conn, "/deadlines?deadline[a][by]=#{iso(30)}")

      assert column(html, "deadline", "comment_count") == ["3", "0"]
      assert column(html, "deadline", "assignee") == [world.member.name, world.member.name]
    end

    test "a text that is no day is shown at the input, and the rows stay", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/deadlines?deadline[a][by]=#{iso(30)}")

      html = argue(view, "deadline", a: %{"by" => "someday"})

      assert [%{value: "someday", errors: ["is invalid"]} | _] = arguments(html, "deadline")
      assert titles(html) == ["Soon", "Later"]
      assert text(html, "#deadline-error") == nil
    end

    test "a row expands into its comments: the row is read again with the day", %{
      conn: conn,
      soon: soon
    } do
      {:ok, view, _html} = live(conn, "/deadlines?deadline[a][by]=#{iso(30)}")

      expand(view, "deadline", soon.id)
      html = toggle(view, "deadline", soon.id, "comments")
      id = nested("deadline", soon.id, "comments")

      assert length(column(html, id, "body")) == 3
      assert text(html, "[id='#{id}-error']") == nil
    end

    test "a task that is put off beyond the day stays in its row until the table reads again", %{
      conn: conn,
      soon: soon
    } do
      {:ok, view, _html} = live(conn, "/deadlines?deadline[a][by]=#{iso(30)}")

      html = save(view, "deadline", soon.id, "due_on", iso(60))

      assert text(html, cell("deadline", soon.id, "due_on")) == iso(60)
      assert titles(html) == ["Soon", "Later"]
      # with what its columns show besides
      assert text(html, cell("deadline", soon.id, "comment_count")) == "3"

      # for the table it is no longer there
      save(view, "deadline", soon.id, "due_on", iso(1))
      assert_reply view, %{ok: false, error: "This record is no longer available."}

      view |> element("#deadline-head-title") |> render_click()
      assert titles(render_async(view)) == ["Later"]
    end
  end
end
