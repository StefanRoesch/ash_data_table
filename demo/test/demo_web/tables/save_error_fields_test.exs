defmodule DemoWeb.Tables.SaveErrorFieldsTest do
  @moduledoc """
  What a failed save tells a person about a field other than the one they
  edited: its name only when they have a column for it. An error about a
  field whose column was left out for them, or which is no column of the
  table, is shown without the field's name.

  The table is of a resource that exists for the tests only
  (`test/support/plain_tables.ex`), mounted at `/support/memos`; its records
  are kept in memory.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Plain.Memo

  @admin %{id: "ada", name: "ada", role: :admin}
  @member %{id: "max", name: "max", role: :member}

  setup do
    on_exit(fn -> Ash.DataLayer.Ets.stop(Memo) end)
  end

  defp memo(attributes) do
    Memo
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(%{title: "A memo", body: "Long enough", code: "C-100", grade: 1}, attributes)
    )
    |> Ash.create!(authorize?: false)
  end

  defp open(conn, actor) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{"assigns" => %{current_user: actor}})
    |> live("/support/memos")
  end

  test "an error about a field the person has a column for names it", %{conn: conn} do
    memo = memo(%{body: "ab"})
    {:ok, view, html} = open(conn, @admin)
    assert headers(html, "memo") == ["Title", "Body", "Code"]

    html = save(view, "memo", memo.id, "title", "Another title")

    assert failure(html, "memo", memo.id, "title") == %{
             shown: "Another title",
             message: "Body: must have length of at least 3"
           }
  end

  # The member is not shown `code`, so the action's validation of it fails
  # for them whatever it holds: the record they save has the field hidden.
  test "an error about a field whose column was left out for the person does not name it",
       %{conn: conn} do
    memo = memo(%{})
    {:ok, view, html} = open(conn, @member)
    assert headers(html, "memo") == ["Title", "Body"]

    html = save(view, "memo", memo.id, "title", "Another title")

    assert failure(html, "memo", memo.id, "title") == %{
             shown: "Another title",
             message: "could not be parsed"
           }

    assert text(html, "#memo-status") == "Title was not saved: could not be parsed"
    refute html =~ "Code"
    refute html =~ "code"
    assert Ash.get!(Memo, memo.id, authorize?: false).title == "A memo"
  end

  test "an error about that field names it for a person who has its column", %{conn: conn} do
    memo = memo(%{code: "x"})
    {:ok, view, html} = open(conn, @admin)
    assert headers(html, "memo") == ["Title", "Body", "Code"]

    html = save(view, "memo", memo.id, "title", "Another title")

    assert failure(html, "memo", memo.id, "title").message ==
             "Code: must have length of at least 3"
  end

  test "an error about a field that is no column of the table does not name it", %{conn: conn} do
    memo = memo(%{grade: nil})
    {:ok, view, _html} = open(conn, @admin)

    html = save(view, "memo", memo.id, "title", "Another title")

    assert failure(html, "memo", memo.id, "title") == %{
             shown: "Another title",
             message: "must be present"
           }

    assert text(html, "#memo-status") == "Title was not saved: must be present"
    refute html =~ "Grade"
    refute html =~ "grade"
  end

  test "several such errors are shown side by side, each named or not on its own",
       %{conn: conn} do
    memo = memo(%{body: "ab", grade: nil})
    {:ok, view, _html} = open(conn, @member)

    html = save(view, "memo", memo.id, "title", "Another title")

    assert failure(html, "memo", memo.id, "title").message ==
             "must be present; could not be parsed; Body: must have length of at least 3"

    refute html =~ "Code"
    refute html =~ "Grade"
  end

  test "a failure underneath says only that it could not be saved, whatever its message",
       %{conn: conn} do
    memo = memo(%{})
    {:ok, view, _html} = open(conn, @admin)

    html = save(view, "memo", memo.id, "code", "C-200")

    assert failure(html, "memo", memo.id, "code") == %{
             shown: "C-200",
             message: "This could not be saved."
           }

    refute html =~ "vault"
    refute html =~ "10.0.0.7"
    assert Ash.get!(Memo, memo.id, authorize?: false).code == "C-100"
  end
end
