defmodule DemoWeb.Tables.LedgerDefaultConfigTest do
  @moduledoc """
  The tables of `DemoWeb.Tables.LedgerTableTest` once more, under Ash's own
  default for `config :ash, show_keysets_for_all_actions?:`, which the demo
  switches off. With it on, Ash computes a keyset for every record of every
  page, and a page of related records that is sorted by an aggregate fails
  for a person from whom a field policy hides a field on some records (the
  library's internal ticket #35), also when it is read by offset.

  The setting is the application's, read whenever a page is read: these
  tests do not run beside others.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  setup %{conn: conn} do
    Application.put_env(:ash, :show_keysets_for_all_actions?, true)
    on_exit(fn -> Application.put_env(:ash, :show_keysets_for_all_actions?, false) end)

    world = world(tasks: 0, other_tasks: 0)
    [project | _] = world.projects

    [own, other] =
      for {title, assignee} <- [{"A own", world.member}, {"B other", world.admin}] do
        Generator.generate(
          Generator.task(
            organization_id: world.organization.id,
            project_id: project.id,
            reporter_id: world.admin.id,
            assignee_id: assignee.id,
            title: title
          )
        )
      end

    for n <- 1..4 do
      Generator.generate(
        Generator.comment(
          organization_id: world.organization.id,
          task_id: other.id,
          author_id: if(rem(n, 2) == 0, do: world.member.id, else: world.admin.id),
          body: "Remark #{n}",
          inserted_at: DateTime.add(~U[2026-01-01 12:00:00.000000Z], n, :minute)
        )
      )
    end

    label = Generator.generate(Generator.label(organization_id: world.organization.id))

    Generator.generate(
      Generator.task_label(
        organization_id: world.organization.id,
        task_id: own.id,
        label_id: label.id
      )
    )

    conn = Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: world.member}})
    {:ok, view, html} = live(conn, "/support/jobs")

    %{view: view, html: html, other: other}
  end

  test "a table of its own shows its aggregate columns and sorts by one", %{
    view: view,
    html: html
  } do
    assert text(html, "#job-error") == nil
    assert column(html, "job", "tag_count") == ["1", "0"]

    view |> element("#job-head-tag_count") |> render_click()
    html = render_async(view, 2000)

    assert text(html, "#job-error") == nil
    assert column(html, "job", "title") == ["B other", "A own"]
  end

  test "a nested table read in pages shows its aggregate column, and does not sort by it, which would fail",
       %{view: view, other: other} do
    expand(view, "job", other.id)
    html = toggle(view, "job", other.id, "remarks")
    id = nested("job", other.id, "remarks")

    assert text(html, "[id='#{id}-error']") == nil
    assert column(html, id, "tagging_count") == ["0", "0", "0"]
    assert attribute(html, "[id='#{id}-head-tagging_count']", "data-sort") == []

    view |> element("[id='#{id}-grid']") |> render_hook("sort", %{"column" => "tagging_count"})
    html = render_async(view, 2000)

    assert text(html, "[id='#{id}-error']") == nil
    assert column(html, id, "body") == ["Not available", "Remark 2", "Not available"]
  end
end
