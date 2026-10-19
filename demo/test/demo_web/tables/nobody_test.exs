defmodule DemoWeb.Tables.NobodyTest do
  @moduledoc """
  Every mounted table of the demo, opened by somebody who is not logged in:
  no actor and no tenant. None of them may fail; each shows what its
  resource's policies leave to an anonymous visitor.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  setup %{conn: conn} do
    world = world(tasks: 3, other_tasks: 2)
    Demo.Generator.generate_many(Demo.Generator.specimen(), 2)
    %{conn: log_in(conn, world.nobody)}
  end

  # the resources whose policies filter: nothing matches without an actor
  for {path, id} <- [
        {"/tasks", "task"},
        {"/labels", "label"},
        {"/bare/labels", "label"},
        {"/task_labels", "task_label"}
      ] do
    test "#{path} shows no records", %{conn: conn} do
      {:ok, view, html} = live(conn, unquote(path))

      assert attribute(html, "##{unquote(id)}-table[role=table]", "role") != []
      assert attribute(html, "##{unquote(id)}-table [role=rowgroup]", "id") == []
      assert text(html, "##{unquote(id)}-empty") == "No records"
      assert text(html, "##{unquote(id)}-error") == nil
      # and offers no editing
      assert editors(html, unquote(id)) == []

      assert attribute(html, "##{unquote(id)}-table :is([role=cell],[role=rowheader])", "role") !=
               []

      assert attribute(
               html,
               "##{unquote(id)}-table :is([role=cell],[role=rowheader])",
               "tabindex"
             ) == []

      # the page is alive: it can be sorted
      [header | _] = attribute(html, "##{unquote(id)}-table [role=columnheader][data-sort]", "id")
      click(view, "##{header} > button")
      assert text(render_async(view), "##{unquote(id)}-empty") == "No records"
    end
  end

  test "/projects answers as a page that does not exist", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, "/projects") end
  end

  test "/comments says that it is not allowed", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/comments")

    assert text(html, "#comment-error") == "You are not allowed to see these records."
    assert text(html, "#comment-empty") == nil
  end

  test "/specimens, which are open to anyone, shows them and lets them be edited",
       %{conn: conn} do
    {:ok, view, html} = live(conn, "/specimens")

    assert [id, _other] = column(html, "specimen", "id")
    assert "a_string" in editors(html, "specimen")

    html = save(view, "specimen", id, "a_string", "Changed by nobody")

    assert text(html, cell("specimen", id, "a_string")) == "Changed by nobody"
  end

  test "the front page lists every resource", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "nobody"
  end
end
