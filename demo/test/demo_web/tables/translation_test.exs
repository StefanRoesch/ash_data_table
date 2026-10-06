defmodule DemoWeb.Tables.TranslationTest do
  @moduledoc """
  The languages of the mounted table of `Demo.Tracker.Task` at `/tasks`.

  The demo names its Gettext backend and its error translator to `ash_table`
  (`config :ash_table, gettext_backend: …, translate_error: …`) and has German
  texts for both: the table's own strings and the tasks' wording in the
  domain `ash_table`, the messages of the tasks' actions in the domain
  `errors`. The locale comes from the session, as the language switcher sets
  it.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  defp task(world, overrides) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          title: "Paint the fence",
          status: :in_progress,
          priority: :medium,
          progress: 40,
          billable?: true,
          estimate_hours: nil
        ] ++ overrides
      )
    )
  end

  defp open(conn, world, locale) do
    conn |> log_in(world.admin) |> in_locale(locale) |> live("/tasks")
  end

  setup do
    world = world(tasks: 0)
    first = task(world, title: "Paint the fence")
    task(world, title: "Paint the gate", billable?: false)
    task(world, title: "Mow the lawn")
    %{world: world, task: first}
  end

  describe "in German" do
    test "the table's own texts are German", %{conn: conn, world: world} do
      {:ok, view, html} = open(conn, world, "de")

      assert text(html, "#task-range") == "1–3 von 3"
      assert text(html, "#task-previous") == "Zurück"
      assert text(html, "#task-next") == "Weiter"
      assert attribute(html, "#task-pagination", "aria-label") == ["Seiten: Aufgaben"]
      assert attribute(html, "#task-page-1", "aria-label") == ["Zu Seite 1"]

      assert filter_controls(html, "task", "title").operators ==
               ["enthält", "ist gleich", "beginnt mit"]

      assert filter_controls(html, "task", "billable?").choices == ["Alle", "Ja", "Nein"]
      assert Enum.sort(column(html, "task", "billable?")) == ["–Nein", "✓Ja", "✓Ja"]
      assert text(html, "#task-dialog button[value=cancel]") == "Abbrechen"
      assert text(html, "#task-dialog button[value=confirm]") == "Bestätigen"

      html = filter(view, "task", "title", v: "Paint")
      assert text(html, "#task-clear-filters") == "Filter zurücksetzen"

      assert attribute(html, "#task-filter-title-clear", "aria-label") == [
               "Filter Titel zurücksetzen"
             ]

      html = filter(view, "task", "title", v: "nothing like it")
      assert text(html, "#task-empty") == "Keine Einträge"
    end

    test "a count is announced in the plural form of its number", %{conn: conn, world: world} do
      {:ok, view, _html} = open(conn, world, "de")

      assert text(filter(view, "task", "title", v: "Paint"), "#task-status") == "2 Ergebnisse"
      assert text(filter(view, "task", "title", v: "fence"), "#task-status") == "1 Ergebnis"
      assert text(filter(view, "task", "title", v: "roof"), "#task-status") == "0 Ergebnisse"
    end

    test "the tasks' own wording is German where the host has translated it",
         %{conn: conn, world: world, task: task} do
      {:ok, _view, html} = open(conn, world, "de")

      assert text(html, "#task-page h1") == "Aufgaben"
      assert attribute(html, "#task-table", "aria-label") == ["Aufgaben"]

      assert Enum.take(headers(html, "task"), 4) == [
               "Titel",
               "Status",
               "Priorität",
               "Fortschritt"
             ]

      assert attribute(html, "#task-filter-title input", "aria-label") == ["Titel filtern"]
      assert text(html, cell(task.id, "status")) == "In Arbeit"
      assert "Zu erledigen" in filter_controls(html, "task", "status").choices
      assert editor(html, "task", "priority").choices == ["Niedrig", "Mittel", "Hoch", "Dringend"]
      assert editor(html, "task", "status").confirm == "Den Status dieser Aufgabe ändern?"
    end

    test "a message of an action is German, with its variable filled in",
         %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = open(conn, world, "de")

      html = save(view, task.id, "title", "ab")

      assert failure(html, task.id, "title") == %{
               shown: "ab",
               message: "muss mindestens 3 Zeichen lang sein"
             }

      assert text(html, "#task-status") ==
               "Titel wurde nicht gespeichert: muss mindestens 3 Zeichen lang sein"

      html = save(view, task.id, "progress", "150")
      assert failure(html, task.id, "progress").message == "darf höchstens 100 sein"

      html = save(view, task.id, "title", "")
      assert failure(html, task.id, "title").message == "muss ausgefüllt werden"
    end

    test "a message about another field has that field's German name in front",
         %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = open(conn, world, "de")

      html = save(view, task.id, "status", "done")

      assert failure(html, task.id, "status") == %{
               shown: "Erledigt",
               message: "Fortschritt: muss 100 sein, wenn die Aufgabe erledigt ist"
             }
    end

    test "the table's own refusal is German", %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = conn |> log_in(world.member) |> in_locale("de") |> live("/tasks")

      html = save(view, task.id, "progress", "90")

      assert failure(html, task.id, "progress").message == "Sie dürfen das nicht ändern."
    end

    test "a read that is refused says so in German", %{conn: conn} do
      {:ok, _view, html} = conn |> log_in(nil) |> in_locale("de") |> live("/comments")

      assert text(html, "#comment-error") == "Sie dürfen diese Einträge nicht sehen."
    end
  end

  describe "in English, and in a locale the host has no texts for" do
    test "everything is as the library and the resource wrote it",
         %{conn: conn, world: world, task: task} do
      for locale <- ["en", "fr"] do
        {:ok, view, html} = open(conn, world, locale)

        assert text(html, "#task-page h1") == "Tasks"
        assert text(html, "#task-range") == "1–3 of 3"
        assert text(html, "#task-next") == "Next"
        assert attribute(html, "#task-pagination", "aria-label") == ["Pagination: Tasks"]
        assert Enum.take(headers(html, "task"), 2) == ["Title", "State"]
        assert filter_controls(html, "task", "billable?").choices == ["Any", "Yes", "No"]
        assert text(html, cell(task.id, "status")) == "In progress"

        assert text(filter(view, "task", "title", v: "Paint"), "#task-status") == "2 results"
        assert text(filter(view, "task", "title", v: "fence"), "#task-status") == "1 result"

        html = save(view, task.id, "title", "ab")

        assert failure(html, task.id, "title").message ==
                 "length must be greater than or equal to 3"

        assert text(html, "#task-status") ==
                 "Title was not saved: length must be greater than or equal to 3"

        html = save(view, task.id, "status", "done")

        assert failure(html, task.id, "status") == %{
                 shown: "Done",
                 message: "Progress: must be 100 when the task is done"
               }
      end
    end
  end

  test "the language switcher stores the chosen locale in the session", %{conn: conn} do
    conn = post(conn, ~p"/locale", %{"locale" => "de", "return_to" => "/tasks"})

    assert redirected_to(conn) == "/tasks"
    assert get_session(conn, DemoWeb.Locale.session_key()) == "de"

    conn = post(conn, ~p"/locale", %{"locale" => "xx"})
    assert get_session(conn, DemoWeb.Locale.session_key()) == "de"
  end
end
