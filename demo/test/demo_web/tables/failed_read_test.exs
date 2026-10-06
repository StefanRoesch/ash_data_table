defmodule DemoWeb.Tables.FailedReadTest do
  @moduledoc """
  What a table shows when its read fails without being refused: the message
  of an error the read action returned on purpose, and no more than "could
  not be loaded" for a failure underneath, which goes to the log.

  The table is of a resource that exists for the tests only
  (`test/support/plain_tables.ex`), mounted at `/support/reports`. Its read
  does what the test tells it through `Demo.Support.Switch`.
  """
  use DemoWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Plain.Report
  alias Demo.Support.Switch

  setup do
    Switch.set(:ok)

    Report
    |> Ash.Changeset.for_create(:create, %{title: "Quarterly", secret: "s3cret"})
    |> Ash.create!()

    on_exit(fn ->
      Switch.set(:ok)
      Ash.DataLayer.Ets.stop(Report)
    end)
  end

  test "a read that succeeds shows the rows and no error", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/support/reports")

    assert column(html, "report", "title") == ["Quarterly"]
    assert text(html, "#report-error") == nil
  end

  test "an error the action returned is shown in place of the rows, its variables filled in",
       %{conn: conn} do
    Switch.set(:invalid)
    {:ok, _view, html} = live(conn, "/support/reports")

    assert text(html, "#report-error") == "is closed until Monday"
    assert attribute(html, "#report-error", "role") == ["alert"]
    assert column(html, "report", "title") == []
    # not the empty state: nothing was found out about the records
    assert text(html, "#report-empty") == nil
  end

  test "an error about a field the table has a column for names the column", %{conn: conn} do
    Switch.set({:invalid_field, :title})
    {:ok, _view, html} = live(conn, "/support/reports")

    assert text(html, "#report-error") == "Title: must be before 3"
  end

  test "an error about a field the table has no column for does not name the field",
       %{conn: conn} do
    Switch.set({:invalid_field, :secret})
    {:ok, _view, html} = live(conn, "/support/reports")

    assert text(html, "#report-error") == "must be before 3"
    refute html =~ "Secret"
    refute html =~ "secret"
  end

  test "an error the action returned is translated by the host like one of a save",
       %{conn: conn} do
    # the demo's `errors` domain has this entry for its own number columns
    Switch.set(:invalid_max)
    {:ok, _view, html} = conn |> in_locale("de") |> live("/support/reports")

    assert text(html, "#report-error") == "Titel: darf höchstens 3 sein"
  end

  test "an error that is not of the action's making says only that the records could not be " <>
         "loaded, and is logged",
       %{conn: conn} do
    Switch.set(:unknown)

    {html, log} =
      with_log(fn ->
        {:ok, _view, html} = live(conn, "/support/reports")
        html
      end)

    assert text(html, "#report-error") == "The records could not be loaded."
    assert text(html, "#report-empty") == nil
    refute html =~ "vault"
    refute html =~ "10.0.0.7"
    assert log =~ "[error]"
    assert log =~ "the vault at 10.0.0.7 did not answer"
    assert log =~ "Demo.Support.Plain.Report"
  end

  test "of several errors, only those of the action's making are shown", %{conn: conn} do
    Switch.set(:mixed)
    {:ok, _view, html} = live(conn, "/support/reports")

    assert text(html, "#report-error") == "is closed"
    refute html =~ "vault"
  end

  test "a read that crashes while the page is open says the same, and is logged", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/support/reports")
    Switch.set(:crash)

    {html, log} =
      with_log(fn ->
        view |> element("#report-head-title") |> render_click()
        render_async(view)
      end)

    assert text(html, "#report-error") == "The records could not be loaded."
    assert column(html, "report", "title") == []
    refute html =~ "vault"
    assert log =~ "the vault at 10.0.0.7 did not answer"
  end

  # The table rescues nothing: a page whose first read crashes fails as any
  # LiveView does that crashes while it is mounted.
  test "a read that crashes when the page is opened fails the page", %{conn: conn} do
    Switch.set(:crash)

    assert_raise Ash.Error.Unknown, ~r/the vault at 10.0.0.7 did not answer/, fn ->
      live(conn, "/support/reports")
    end
  end

  test "a read that fails while the page is open takes the rows away and shows the error",
       %{conn: conn} do
    {:ok, view, html} = live(conn, "/support/reports")
    assert column(html, "report", "title") == ["Quarterly"]

    Switch.set(:invalid)
    view |> element("#report-head-title") |> render_click()
    html = render_async(view)

    assert text(html, "#report-error") == "is closed until Monday"
    assert column(html, "report", "title") == []

    Switch.set(:ok)
    view |> element("#report-head-title") |> render_click()
    html = render_async(view)

    assert text(html, "#report-error") == nil
    assert column(html, "report", "title") == ["Quarterly"]
  end

  test "the grid is busy while a read runs, with the previous rows left in view", %{conn: conn} do
    {:ok, view, html} = live(conn, "/support/reports")
    assert attribute(html, "#report-table", "aria-busy") == []

    html = view |> element("#report-head-title") |> render_click()

    assert attribute(html, "#report-table", "aria-busy") == ["true"]
    assert column(html, "report", "title") == ["Quarterly"]

    html = render_async(view)
    assert attribute(html, "#report-table", "aria-busy") == []
    assert column(html, "report", "title") == ["Quarterly"]
  end
end
