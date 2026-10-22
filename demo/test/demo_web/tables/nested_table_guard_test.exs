defmodule DemoWeb.Tables.NestedTableGuardTest do
  @moduledoc """
  What must never get from a person into the query of a table, nested or
  not, and what a nested table must never tell.

  A filter on a column the person never sees never reaches the query, and
  the count of a page of related records counts only what the person's rows
  show.

  A sort is only ever by one of the table's own sortable columns, never by
  a path through a relationship ("assignee.name").

  Driven by the events the hook and the filter row's form send, with names
  and shapes the table never offers.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  @moment ~U[2026-01-01 12:00:00.000000Z]

  defp task(world, project, title, overrides) do
    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          title: title,
          inserted_at: @moment
        ] ++ overrides
      )
    )
  end

  # A project with 30 tasks whose estimate the member sees (their own) and 30
  # whose estimate is hidden from them. Every estimate is 20, every external
  # reference starts with "EXT-": a count that ignored the field policies
  # would say 60 where the member's rows say 30.
  defp world_of_estimates(_context) do
    world = world(tasks: 0)

    project =
      Generator.generate(
        Generator.project(organization_id: world.organization.id, name: "Aardvark")
      )

    for {owner, kind} <- [{world.member, "Own"}, {world.admin, "Hidden"}], n <- 1..30 do
      task(world, project, "#{kind} #{String.pad_leading("#{n}", 2, "0")}",
        assignee_id: owner.id,
        estimate_hours: Decimal.new("20"),
        external_ref: "EXT-#{n}",
        inserted_at: DateTime.add(@moment, n, :minute)
      )
    end

    %{world: world, project: project, id: nested("project", project.id, "tasks")}
  end

  defp open_tasks(conn, actor, project) do
    {:ok, view, _html} = conn |> log_in(actor) |> live("/projects")
    expand(view, "project", project.id)
    {view, toggle(view, "project", project.id, "tasks")}
  end

  # A `filter` event as the filter row's form sends it, with whatever in it.
  defp send_filter(view, id, filter) do
    forge(view, id, "filter", %{"filter" => filter})
    render_async(view)
  end

  defp send_sort(view, id, column) do
    forge(view, id, "sort", %{"column" => column})
    render_async(view)
  end

  describe "a filter on a column the person never sees, in a nested table" do
    setup :world_of_estimates

    test "is not offered", %{conn: conn, world: world, project: project, id: id} do
      {_view, html} = open_tasks(conn, world.member, project)

      refute "External ref" in headers(html, id)
      assert attribute(html, "[id='#{id}-filter-external_ref']", "id") == []
      assert text(html, "[id='#{id}-range']") == "1–25 of 60"
    end

    test "sent all the same, with any operator, is ignored: the rows and the total are those without it",
         %{conn: conn, world: world, project: project, id: id} do
      {view, before} = open_tasks(conn, world.member, project)

      for entry <- [
            %{"v" => "EXT-1"},
            %{"o" => "contains", "v" => "EXT"},
            %{"o" => "equals", "v" => "EXT-1"},
            %{"o" => "starts_with", "v" => "EXT-1"},
            %{"o" => "is_empty"},
            %{"o" => "is_nil", "v" => "true"},
            "EXT"
          ] do
        html = send_filter(view, id, %{"external_ref" => entry})

        # 2 of the 60 start with "EXT-1" exactly, 22 contain it: neither is told
        assert column(html, id, "title") == column(before, id, "title")
        assert text(html, "[id='#{id}-range']") == "1–25 of 60"
        assert text(html, "[id='#{id}-status']") == ""
        assert attribute(html, "[id='#{id}-clear-filters']", "id") == []
        refute html =~ "EXT"
      end
    end

    test "sent beside a filter that is offered leaves that one alone to apply",
         %{conn: conn, world: world, project: project, id: id} do
      {view, _html} = open_tasks(conn, world.member, project)

      html =
        send_filter(view, id, %{
          "title" => %{"v" => "Own 0"},
          "external_ref" => %{"o" => "equals", "v" => "EXT-1"}
        })

      # the nine of "Own 01" to "Own 09", whatever their reference
      assert length(column(html, id, "title")) == 9
      assert text(html, "[id='#{id}-range']") == "1–9 of 9"
    end
  end

  describe "a filter on a column the person sees on some records only, in a nested table with offset pages" do
    setup :world_of_estimates

    for {name, entry} <- [
          {"the default operator", %{"v" => "20"}},
          {"equals", %{"o" => "equals", "v" => "20"}},
          {"greater than", %{"o" => "greater_than", "v" => "10"}},
          {"at least", %{"o" => "at_least", "v" => "20"}},
          {"less than", %{"o" => "less_than", "v" => "30"}},
          {"at most", %{"o" => "at_most", "v" => "20"}},
          # the hidden ones look empty to the member: all 30 of them
          {"is empty", %{"o" => "is_empty"}}
        ] do
      test "with #{name}: the total counts the rows the person is shown, 30 and not 60",
           %{conn: conn, world: world, project: project, id: id} do
        {view, _html} = open_tasks(conn, world.member, project)

        html = send_filter(view, id, %{"estimate_hours" => unquote(Macro.escape(entry))})

        assert length(column(html, id, "title")) == 25
        assert text(html, "[id='#{id}-range']") == "1–25 of 30"
        assert text(html, "[id='#{id}-status']") == "30 results"
        assert attribute(html, "[id='#{id}-table']", "aria-rowcount") == ["33"]

        assert attribute(html, "[id='#{id}-pagination'] button[id*='-page-']", "id") == [
                 "#{id}-page-1",
                 "#{id}-page-2"
               ]

        click(view, "[id='#{id}-next']")
        html = render_async(view)

        assert length(column(html, id, "title")) == 5
        assert text(html, "[id='#{id}-range']") == "26–30 of 30"
        assert attribute(html, "[id='#{id}-next']", "disabled") == [""]
      end
    end

    test "beside a filter on an ordinary column, and when it alone is taken away",
         %{conn: conn, world: world, project: project, id: id} do
      {view, _html} = open_tasks(conn, world.member, project)

      html =
        send_filter(view, id, %{
          "title" => %{"v" => "0"},
          "estimate_hours" => %{"o" => "greater_than", "v" => "10"}
        })

      # "Own 01" to "Own 09", 10, 20 and 30: 12 of the member's; 24 with the hidden ones
      assert length(column(html, id, "title")) == 12
      assert text(html, "[id='#{id}-range']") == "1–12 of 12"

      html = send_filter(view, id, %{"title" => %{"v" => "0"}})

      assert text(html, "[id='#{id}-range']") == "1–24 of 24"
      assert text(html, "[id='#{id}-status']") == "24 results"
    end

    test "for the admin, who sees every estimate, the total stays",
         %{conn: conn, world: world, project: project, id: id} do
      {view, _html} = open_tasks(conn, world.admin, project)

      html = send_filter(view, id, %{"estimate_hours" => %{"o" => "greater_than", "v" => "10"}})

      assert text(html, "[id='#{id}-range']") == "1–25 of 60"
      assert text(html, "[id='#{id}-status']") == "60 results"
    end

    test "two levels down, under a task's project", %{conn: conn, world: world, project: project} do
      {:ok, view, html} = conn |> log_in(world.member) |> live("/tasks")
      [row | _] = attribute(html, "#task-table > [role=rowgroup]:not([data-detail])", "id")
      key = String.replace_prefix(row, "task-row-", "")

      expand(view, key)
      toggle(view, key, "project")
      first = nested(key, "project")
      expand(view, first, project.id)
      html = toggle(view, first, project.id, "tasks")
      id = nested(first, project.id, "tasks")
      assert text(html, "[id='#{id}-range']") == "1–25 of 60"

      html = send_filter(view, id, %{"estimate_hours" => %{"o" => "greater_than", "v" => "10"}})

      assert text(html, "[id='#{id}-range']") == "1–25 of 30"
    end

    test "under a table placed in a page of the host's", %{
      conn: conn,
      world: world,
      project: project
    } do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/dashboard")
      expand(view, "dashboard-projects", project.id)
      html = toggle(view, "dashboard-projects", project.id, "tasks")
      id = nested("dashboard-projects", project.id, "tasks")
      assert text(html, "[id='#{id}-range']") == "1–25 of 60"

      html = send_filter(view, id, %{"estimate_hours" => %{"o" => "is_empty"}})

      assert text(html, "[id='#{id}-range']") == "1–25 of 30"
    end

    test "a sort by such a column keeps the total",
         %{conn: conn, world: world, project: project, id: id} do
      {view, _html} = open_tasks(conn, world.member, project)

      html = send_sort(view, id, "estimate_hours")

      assert attribute(html, "[id='#{id}-head-estimate_hours']", "aria-sort") == ["ascending"]
      assert text(html, "[id='#{id}-range']") == "1–25 of 60"
    end
  end

  describe "a table that keeps its state while the person asking changes" do
    setup :world_of_estimates

    test "drops the sort and the filter by a column the next person does not have, and what was open",
         %{conn: conn, world: world, project: project} do
      conn = Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{actor_id: world.admin.id}})
      {:ok, view, _html} = live(conn, "/support/switch")

      # the admin filters and sorts the tasks by the column only an admin has
      send_sort(view, "tasks", "external_ref")
      html = send_filter(view, "tasks", %{"external_ref" => %{"v" => "EXT-1"}})
      # "EXT-1" and "EXT-10" to "EXT-19", of both kinds
      assert text(html, "#tasks-range") == "1–22 of 22"

      # and the tasks of a project by it
      expand(view, "projects", project.id)
      toggle(view, "projects", project.id, "tasks")
      id = nested("projects", project.id, "tasks")
      html = send_filter(view, id, %{"external_ref" => %{"v" => "EXT-1"}})
      assert text(html, "[id='#{id}-range']") == "1–22 of 22"

      view |> element("#become") |> render_click(%{"id" => world.member.id})
      html = render_async(view)

      # the member's table: every task, in the action's order, nothing filtered
      refute "External ref" in headers(html, "tasks")
      assert text(html, "#tasks-range") == "1–25 of 60"
      assert attribute(html, "#tasks-clear-filters", "id") == []

      assert attribute(html, "#tasks-table [role=columnheader][aria-sort]", "role") != []

      assert attribute(
               html,
               "#tasks-table [role=columnheader][aria-sort]:not([aria-sort=none])",
               "id"
             ) == []

      refute html =~ "EXT"
      # and nothing is open under the projects any more
      assert attribute(html, "[id='#{id}']", "id") == []
      assert lines(html, "projects", project.id) == []
    end
  end

  describe "a sort by something that is no column of the table" do
    setup do
      world = world(tasks: 0)
      [project | _] = world.projects

      # in the order the action sorts them: by `inserted_at`, newest first
      for {title, assignee, minute} <- [
            {"Zebra", world.admin, 3},
            {"Apple", world.viewer, 2},
            {"Mango", world.member, 1}
          ] do
        task(world, project, title,
          assignee_id: assignee.id,
          inserted_at: DateTime.add(@moment, minute, :minute)
        )
      end

      %{world: world, project: project}
    end

    @unsorted ["Zebra", "Apple", "Mango"]

    for sort <- [
          "assignee.name",
          "-assignee.name",
          "project.name",
          "comments.body",
          "reporter.email"
        ] do
      test "in the URL, through a relationship: #{sort}", %{conn: conn, world: world} do
        {:ok, _view, html} =
          conn
          |> log_in(world.admin)
          |> live("/tasks?" <> URI.encode_query(%{"task[sort]" => unquote(sort)}))

        assert column(html, "task", "title") == @unsorted

        assert attribute(html, "#task-table [role=columnheader][aria-sort]", "role") != []

        assert attribute(
                 html,
                 "#task-table [role=columnheader][aria-sort]:not([aria-sort=none])",
                 "id"
               ) == []

        assert text(html, "#task-error") == nil
      end
    end

    test "in an event: a path through a relationship, a column of a destination, a private field, an unknown name",
         %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      for column <- [
            "assignee.name",
            "-assignee.name",
            "assignee",
            # a column of the people's table
            "name",
            "email",
            # private
            "internal_note",
            "organization_id",
            "no_such_field",
            "",
            nil,
            ["title"],
            %{"assignee" => "name"}
          ] do
        html = send_sort(view, "task", column)

        assert column(html, "task", "title") == @unsorted

        assert attribute(html, "#task-table [role=columnheader][aria-sort]", "role") != []

        assert attribute(
                 html,
                 "#task-table [role=columnheader][aria-sort]:not([aria-sort=none])",
                 "id"
               ) == []

        assert text(html, "#task-error") == nil
      end

      refute_receive {_ref, {:patch, _topic, _to}}, 20

      # the table is alive, and sorts by a column of its own
      html = send_sort(view, "task", "title")
      assert column(html, "task", "title") == ["Apple", "Mango", "Zebra"]
    end

    test "in an event to a nested table", %{conn: conn, world: world, project: project} do
      {view, html} = open_tasks(conn, world.admin, project)
      id = nested("project", project.id, "tasks")
      assert column(html, id, "title") == @unsorted

      for column <- [
            "assignee.name",
            "project.name",
            "name",
            "internal_note",
            "no_such_field",
            nil
          ] do
        html = send_sort(view, id, column)

        assert column(html, id, "title") == @unsorted

        assert attribute(html, "[id='#{id}-table'] [role=columnheader][aria-sort]", "role") != []

        assert attribute(
                 html,
                 "[id='#{id}-table'] [role=columnheader][aria-sort]:not([aria-sort=none])",
                 "id"
               ) ==
                 []

        assert text(html, "[id='#{id}-error']") == nil
      end

      html = send_sort(view, id, "title")
      assert column(html, id, "title") == ["Apple", "Mango", "Zebra"]
    end

    test "in an event to a nested table of one record, which has no sort at all",
         %{conn: conn, world: world} do
      {:ok, view, html} = conn |> log_in(world.admin) |> live("/tasks")
      [row | _] = attribute(html, "#task-table > [role=rowgroup]:not([data-detail])", "id")
      key = String.replace_prefix(row, "task-row-", "")
      expand(view, key)
      toggle(view, key, "project")
      id = nested(key, "project")

      for column <- ["name", "tasks.title", "inserted_at"] do
        html = send_sort(view, id, column)
        assert attribute(html, "[id='#{id}-table'] [role=columnheader]", "role") != []
        assert attribute(html, "[id='#{id}-table'] [role=columnheader][aria-sort]", "id") == []
        assert length(column(html, id, "name")) == 1
      end

      # nor a filter
      html = send_filter(view, id, %{"name" => %{"v" => "no such project"}})
      assert length(column(html, id, "name")) == 1
    end
  end

  describe "a filter on something that is no column of the table" do
    setup do
      world = world(tasks: 0)
      [project | _] = world.projects

      for {title, assignee} <- [{"Zebra", world.admin}, {"Apple", world.member}] do
        task(world, project, title, assignee_id: assignee.id)
      end

      %{world: world, project: project}
    end

    @filters [
      %{"assignee.name" => %{"v" => "Member"}},
      %{"assignee.name" => %{"o" => "contains", "v" => "Member"}},
      %{"assignee" => %{"name" => %{"contains" => "Member"}}},
      %{"assignee" => %{"v" => "Member"}},
      %{"internal_note" => %{"o" => "is_empty"}},
      %{"no_such_field" => %{"v" => "x"}},
      %{"title" => %{"o" => "assignee.name", "v" => "Member"}}
    ]

    test "in an event is ignored, at the top and in a nested table",
         %{conn: conn, world: world, project: project} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      for filter <- @filters do
        html = send_filter(view, "task", filter)

        assert Enum.sort(column(html, "task", "title")) == ["Apple", "Zebra"]
        assert attribute(html, "#task-clear-filters", "id") == []
        assert text(html, "#task-error") == nil
      end

      {view, _html} = open_tasks(conn, world.admin, project)
      id = nested("project", project.id, "tasks")

      for filter <- @filters do
        html = send_filter(view, id, filter)

        assert Enum.sort(column(html, id, "title")) == ["Apple", "Zebra"]
        assert attribute(html, "[id='#{id}-clear-filters']", "id") == []
        assert text(html, "[id='#{id}-range']") == "1–2 of 2"
      end
    end

    test "in the URL is ignored", %{conn: conn, world: world} do
      for query <- [
            "task[f][assignee.name]=Member",
            "task[f][assignee][name][contains]=Member",
            "task[f][assignee.name][contains]=Member",
            "task[f][internal_note][is_empty]="
          ] do
        {:ok, _view, html} = conn |> log_in(world.admin) |> live("/tasks?" <> query)

        assert Enum.sort(column(html, "task", "title")) == ["Apple", "Zebra"]
        assert attribute(html, "#task-clear-filters", "id") == []
        assert text(html, "#task-error") == nil
      end
    end
  end
end
