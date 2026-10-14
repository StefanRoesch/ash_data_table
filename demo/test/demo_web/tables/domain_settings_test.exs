defmodule DemoWeb.Tables.DomainSettingsTest do
  @moduledoc """
  What a domain's `table` block decides for the mounted tables of its
  resources: under which socket assigns a table finds who is asking, and
  whether it authorizes. Also what a table does when its read is refused
  while its page is open.

  The demo's own domains keep the defaults, so these tables are of resources
  that exist for the tests only (`test/support/guarded_tables.ex`), mounted
  under `/support`. Their records are kept in memory, not in Postgres.
  """
  # the records and the gate are shared by every test of this module
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Gate
  alias Demo.Support.Guarded
  alias Demo.Support.Scope
  alias Demo.Support.Unguarded

  @ada %{name: "ada"}
  @bob %{name: "bob"}

  setup do
    Gate.open()

    on_exit(fn ->
      Gate.open()
      Demo.Support.Ets.stop(Guarded.Note)
      Demo.Support.Ets.stop(Unguarded.Note)
    end)
  end

  defp note(title, owner, organization) do
    Guarded.Note
    |> Ash.Changeset.for_create(:create, %{title: title, owner: owner, organization: organization})
    |> Ash.create!(authorize?: false)
  end

  # Opens a page with the given socket assigns, as a host's `on_mount` hooks
  # would have set them.
  defp with_assigns(conn, assigns) do
    Phoenix.ConnTest.init_test_session(conn, %{"assigns" => Map.new(assigns)})
  end

  defp with_assigns_too(conn, assigns) do
    with_assigns(conn, Map.merge(Plug.Conn.get_session(conn, "assigns"), Map.new(assigns)))
  end

  defp titles(html), do: column(html, "note", "title")

  describe "a domain that names its own assigns" do
    setup do
      note("Ada at Acme", "ada", "acme")
      note("Ada at Globex", "ada", "globex")
      note("Bob at Acme", "bob", "acme")
      :ok
    end

    test "reads as the actor under its `actor_assign`, in the tenant under its `tenant_assign`",
         %{conn: conn} do
      {:ok, _view, html} =
        conn
        |> with_assigns(reader: @ada, reader_organization: "acme")
        |> live("/support/guarded-notes")

      assert titles(html) == ["Ada at Acme"]

      {:ok, _view, html} =
        conn
        |> with_assigns(reader: @bob, reader_organization: "acme")
        |> live("/support/guarded-notes")

      assert titles(html) == ["Bob at Acme"]
    end

    test "reads without a tenant when there is none under its `tenant_assign`", %{conn: conn} do
      {:ok, _view, html} =
        conn |> with_assigns(reader: @ada) |> live("/support/guarded-notes")

      assert Enum.sort(titles(html)) == ["Ada at Acme", "Ada at Globex"]
    end

    test "does not look at the conventional names", %{conn: conn} do
      {:ok, _view, html} =
        conn
        # as the demo's own hook assigns them: the page header shows who it is
        |> with_assigns(current_user: Map.merge(@ada, %{id: "ada", role: :member}))
        |> with_assigns_too(current_tenant: "acme")
        |> live("/support/guarded-notes")

      # nobody is asking, as far as this domain is concerned
      assert titles(html) == []
      assert text(html, "#note-empty") == "No records"
      assert editors(html, "note") == []
    end

    test "reads as the scope under its `scope_assign`, which wins over actor and tenant",
         %{conn: conn} do
      {:ok, _view, html} =
        conn
        |> with_assigns(
          viewer_scope: %Scope{user: @ada, organization: "globex"},
          reader: @bob,
          reader_organization: "acme"
        )
        |> live("/support/guarded-notes")

      assert titles(html) == ["Ada at Globex"]
    end

    test "falls back to actor and tenant when the scope is nil", %{conn: conn} do
      {:ok, _view, html} =
        conn
        |> with_assigns(viewer_scope: nil, reader: @bob, reader_organization: "acme")
        |> live("/support/guarded-notes")

      assert titles(html) == ["Bob at Acme"]
    end

    test "does not look at a scope under the conventional name", %{conn: conn} do
      {:ok, _view, html} =
        conn
        |> with_assigns(
          current_scope: %Scope{user: @ada, organization: "globex"},
          reader: @bob,
          reader_organization: "acme"
        )
        |> live("/support/guarded-notes")

      assert titles(html) == ["Bob at Acme"]
    end

    test "saves as the same person: a scope's person may edit, nobody may not",
         %{conn: conn} do
      [%{id: id}] = Ash.read!(Guarded.Note, authorize?: false, tenant: "globex")

      {:ok, view, html} =
        conn
        |> with_assigns(viewer_scope: %Scope{user: @ada, organization: "globex"})
        |> live("/support/guarded-notes")

      assert editors(html, "note") == ["title"]

      html = save(view, "note", id, "title", "Ada was here")

      assert text(html, cell("note", id, "title")) == "Ada was here"
      assert Ash.get!(Guarded.Note, id, authorize?: false).title == "Ada was here"
    end
  end

  describe "the layout around a mounted table" do
    test "is given who is asking under the names the domain gives them", %{conn: conn} do
      {:ok, _view, html} =
        conn
        |> with_assigns(reader: @ada, reader_organization: "acme")
        |> live("/support/framed/guarded-notes")

      assert text(html, "#frame-reader") == "ada"
      assert text(html, "#frame-organization") == "acme"
      # the table is inside it
      assert attribute(html, "#frame #note-table", "id") == ["note-table"]
    end

    test "is given the scope under the name the domain gives it", %{conn: conn} do
      {:ok, _view, html} =
        conn
        |> with_assigns(viewer_scope: %Scope{user: @bob, organization: "acme"})
        |> live("/support/framed/guarded-notes")

      assert text(html, "#frame-scope") == "bob"
    end

    test "is not given an assign the socket does not have", %{conn: conn} do
      {:ok, _view, html} =
        conn |> with_assigns(reader: @ada) |> live("/support/framed/guarded-notes")

      # `current_scope` is always there, nil when the socket has none
      assert attribute(html, "#frame", "data-assigns") == ["current_scope flash reader"]
    end

    test "is given the conventional assigns too, when the socket has them", %{conn: conn} do
      {:ok, _view, html} =
        conn
        |> with_assigns(reader: @ada, current_user: %{id: "carol", name: "carol", role: :member})
        |> live("/support/framed/guarded-notes")

      assert attribute(html, "#frame", "data-assigns") == [
               "current_scope current_user flash reader"
             ]
    end

    test "of a domain with the default names is given scope, user and tenant under those",
         %{conn: conn} do
      {:ok, _view, html} =
        conn
        |> with_assigns(
          current_user: %{id: "carol", name: "carol", role: :member},
          current_tenant: "acme"
        )
        |> live("/support/framed/memos")

      assert attribute(html, "#frame", "data-assigns") == [
               "current_scope current_tenant current_user flash"
             ]

      {:ok, _view, html} = conn |> with_assigns(%{}) |> live("/support/framed/memos")

      assert attribute(html, "#frame", "data-assigns") == ["current_scope flash"]
    end
  end

  describe "a read that is refused while the page is open" do
    setup %{conn: conn} do
      note("Ada at Acme", "ada", "acme")
      %{conn: with_assigns(conn, reader: @ada, reader_organization: "acme")}
    end

    test "sends the browser to ask for the page afresh, which is answered as not found",
         %{conn: conn} do
      {:ok, view, html} = live(conn, "/support/guarded-notes")
      assert titles(html) == ["Ada at Acme"]

      Gate.close()
      view |> element("#note-head-title") |> render_click()
      assert_patch(view, "/support/guarded-notes?note[sort]=title")

      # The read runs beside the page. Once it is refused, the page ends with
      # a full page request for the URL the person is at; nothing crashes.
      assert_redirect(view, "/support/guarded-notes?note[sort]=title")

      {404, _headers, body} =
        assert_error_sent 404, fn -> get(conn, "/support/guarded-notes?note[sort]=title") end

      assert body == "Not Found"
    end

    test "is answered as not found when the page is opened while the read is refused",
         %{conn: conn} do
      Gate.close()

      assert_error_sent 404, fn -> get(conn, "/support/guarded-notes") end
      assert_raise AshDataTable.NotFoundError, fn -> live(conn, "/support/guarded-notes") end
    end
  end

  describe "a domain with `authorize? false`" do
    setup do
      Unguarded.Note
      |> Ash.Changeset.for_create(:create, %{title: "Open to all", secret: "s3cret"})
      |> Ash.create!(authorize?: false)

      :ok
    end

    test "is refused everything by the resource's policies when asked with authorization" do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Unguarded.Note, actor: @ada)
    end

    test "shows nobody every record and every field, and lets them edit", %{conn: conn} do
      {:ok, view, html} = live(conn, "/support/unguarded-notes")

      assert headers(html, "note") == ["Title", "Secret"]
      assert titles(html) == ["Open to all"]
      assert column(html, "note", "secret") == ["s3cret"]
      assert editors(html, "note") == ["title", "secret"]

      [%{id: id}] = Ash.read!(Unguarded.Note, authorize?: false)
      html = save(view, "note", id, "secret", "changed by nobody")

      assert text(html, cell("note", id, "secret")) == "changed by nobody"
      assert Ash.get!(Unguarded.Note, id, authorize?: false).secret == "changed by nobody"
    end
  end
end
