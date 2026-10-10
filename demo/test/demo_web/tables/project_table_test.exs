defmodule DemoWeb.Tables.ProjectTableTest do
  @moduledoc """
  The mounted table of `Demo.Tracker.Project` at `/projects`: a resource that
  lists the extension and has no `table` block.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  setup do
    world = world(tasks: 0, projects: 0)

    for name <- ["Website", "Billing", "Mobile app"] do
      Generator.generate(Generator.project(organization_id: world.organization.id, name: name))
    end

    %{world: world}
  end

  test "shows the public attributes in the resource's order, the id among them",
       %{conn: conn, world: world} do
    {:ok, _view, html} = conn |> log_in(world.admin) |> live("/projects")

    assert headers(html, "project") == [
             "ID",
             "Name",
             "Description",
             "Status",
             "Starts on",
             "Budget",
             "Client",
             "Milestones",
             "Inserted at"
           ]
  end

  test "shows no private attribute, aggregate or foreign key", %{conn: conn, world: world} do
    {:ok, _view, html} = conn |> log_in(world.admin) |> live("/projects")

    for field <- ["updated_at", "organization_id", "task_count", "open_task_count"] do
      assert attribute(html, "#project-head-#{field}", "id") == []
    end
  end

  test "shows the projects in the read action's order, by name", %{conn: conn, world: world} do
    {:ok, _view, html} = conn |> log_in(world.admin) |> live("/projects")

    assert column(html, "project", "name") == ["Billing", "Mobile app", "Website"]
    assert text(html, "#project-range") == "1–3 of 3"
  end

  test "names each row after its record's id", %{conn: conn, world: world} do
    ids = Demo.Tracker.Project |> Ash.read!(as(world.admin)) |> Enum.map(& &1.id)

    {:ok, _view, html} = conn |> log_in(world.admin) |> live("/projects")

    assert attribute(html, "#project-table tbody:not([data-detail])", "id") ==
             Enum.map(ids, &"project-row-#{&1}")

    assert column(html, "project", "id") == ids
  end

  describe "for nobody, whose read the resource refuses outright" do
    test "the page answers as if it did not exist", %{conn: conn, world: world} do
      conn = log_in(conn, world.nobody)

      {status, _headers, body} = assert_error_sent 404, fn -> get(conn, "/projects") end

      assert status == 404
      assert body == "Not Found"
    end

    test "nothing of the table is rendered: not its rows, not \"no records\", not a refusal",
         %{conn: conn, world: world} do
      conn = log_in(conn, world.nobody)

      {_status, _headers, body} = assert_error_sent 404, fn -> get(conn, "/projects") end

      refute body =~ "No records"
      refute body =~ "not allowed"
      refute body =~ "project"
      refute body =~ "Billing"
    end

    test "the same holds with a sort, a filter or a page in the URL",
         %{conn: conn, world: world} do
      conn = log_in(conn, world.nobody)

      for query <- ["project[sort]=name", "project[f][name]=Billing", "project[page]=2"] do
        assert_error_sent 404, fn -> get(conn, "/projects?" <> query) end
      end
    end

    test "the exception says \"not found\" and nothing about a refusal",
         %{conn: conn, world: world} do
      error =
        assert_raise AshTable.NotFoundError, fn ->
          conn |> log_in(world.nobody) |> live("/projects")
        end

      assert Exception.message(error) == "not found"
      assert Plug.Exception.status(error) == 404
    end

    test "navigating to the page from another one ends at the same answer",
         %{conn: conn, world: world} do
      conn = log_in(conn, world.nobody)
      {:ok, view, _html} = live(conn, "/")

      # The link is followed within the live session.
      assert {:error, {:live_redirect, %{to: "/projects"}}} =
               view |> element("#resources a[href='/projects']") |> render_click()

      # The page it leads to refuses to mount over the live connection:
      # LiveView tells the browser to ask for the page afresh, with the status
      # of the exception, and that request is answered with the 404.
      {:ok, view, _html} = live(conn, "/")

      assert {%{reason: "reload", status: 404}, _call} =
               catch_exit(live_redirect(view, to: "/projects"))

      assert_error_sent 404, fn -> get(conn, "/projects") end
    end

    test "a person who is logged in still gets the page", %{conn: conn, world: world} do
      conn = get(log_in(conn, world.viewer), "/projects")

      assert html_response(conn, 200) =~ "Billing"
    end
  end
end
