defmodule DemoWeb.HomeLiveTest do
  # A smoke test of the test setup itself: the sandbox, the fixtures and the
  # actor in the session. The table's behaviour is tested elsewhere.
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    %{world: world(tasks: 7, other_tasks: 2)}
  end

  test "a logged-in actor sees their organization's records", %{conn: conn, world: world} do
    {:ok, view, html} = conn |> log_in(world.member) |> live(~p"/")

    assert html =~ world.member.name
    assert view |> element("#resource-demo-tracker-task [data-role=visible]") |> render() =~ ">7<"
  end

  test "the outsider sees the other organization's records", %{conn: conn, world: world} do
    {:ok, view, _html} = conn |> log_in(world.outsider) |> live(~p"/")

    assert view |> element("#resource-demo-tracker-task [data-role=visible]") |> render() =~ ">2<"
  end

  test "nobody sees nothing", %{conn: conn, world: world} do
    {:ok, view, html} = conn |> log_in(world.nobody) |> live(~p"/")

    assert html =~ "nobody"
    assert view |> element("#resource-demo-tracker-task [data-role=visible]") |> render() =~ ">0<"
  end

  test "the page and the header link to every mounted table", %{conn: conn, world: world} do
    {:ok, view, _html} = conn |> log_in(world.member) |> live(~p"/")

    for path <- ~w(/tasks /deadlines /projects /comments /labels /specimens) do
      assert has_element?(view, "#resources a[href='#{path}']")
    end

    assert has_element?(view, "#resources a[href='/bare/labels']")
    # and to the page with tables placed in a LiveView of the demo's own
    assert has_element?(view, "#embedded a[href='/dashboard']")

    {:ok, _view, html} = live(conn, "/tasks")
    assert html =~ ~r{<a href="/projects"[^>]*>Projects</a>}
    # that the header's links navigate live, which a full page load would
    # not, the browser shows (`dashboard.spec.ts`)
  end

  test "the actor switcher stores the chosen actor in the session", %{conn: conn, world: world} do
    conn = post(conn, ~p"/actor", %{"actor" => world.viewer.id, "return_to" => "/"})

    assert redirected_to(conn) == "/"
    assert get_session(conn, Demo.Actors.session_key()) == world.viewer.id

    conn = post(conn, ~p"/actor", %{"actor" => ""})
    assert get_session(conn, Demo.Actors.session_key()) == nil
  end
end
