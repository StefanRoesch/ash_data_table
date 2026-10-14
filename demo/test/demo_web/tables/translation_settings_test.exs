defmodule DemoWeb.Tables.TranslationSettingsTest do
  @moduledoc """
  What the two settings of `ash_data_table` for languages do when a host leaves
  one out. The demo sets both, so these tests take one away for their
  duration; that is application-wide, hence they run on their own.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  setup %{conn: conn} do
    world = world(tasks: 0)
    [project | _] = world.projects

    task =
      Generator.generate(
        Generator.task(
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          title: "Paint the fence",
          status: :in_progress,
          progress: 40
        )
      )

    %{conn: conn |> log_in(world.admin) |> in_locale("de"), task: task}
  end

  defp without(key) do
    value = Application.fetch_env!(:ash_data_table, key)
    Application.delete_env(:ash_data_table, key)
    on_exit(fn -> Application.put_env(:ash_data_table, key, value) end)
  end

  test "without `translate_error`, an action's message is shown as the resource wrote it, " <>
         "variables filled in, among the table's translated texts",
       %{conn: conn, task: task} do
    without(:translate_error)
    {:ok, view, html} = live(conn, "/tasks")

    assert text(html, "#task-next") == "Weiter"

    html = save(view, task.id, "title", "ab")

    assert failure(html, task.id, "title").message == "length must be greater than or equal to 3"

    assert text(html, "#task-status") ==
             "Titel wurde nicht gespeichert: length must be greater than or equal to 3"

    html = save(view, task.id, "status", "done")

    assert failure(html, task.id, "status").message ==
             "Fortschritt: must be 100 when the task is done"
  end

  test "without `gettext_backend`, the table's texts and the resource's wording are English " <>
         "whatever the locale",
       %{conn: conn, task: task} do
    without(:gettext_backend)
    {:ok, view, html} = live(conn, "/tasks")

    assert text(html, "#task-page h1") == "Tasks"
    assert text(html, "#task-next") == "Next"
    assert text(html, "#task-range") == "1–1 of 1"
    assert Enum.take(headers(html, "task"), 2) == ["Title", "State"]
    assert text(html, cell(task.id, "status")) == "In progress"
    assert text(filter(view, "task", "title", v: "Paint"), "#task-status") == "1 result"

    # the action's messages are still the host's to translate
    html = save(view, task.id, "title", "ab")
    assert failure(html, task.id, "title").message == "muss mindestens 3 Zeichen lang sein"
  end
end
