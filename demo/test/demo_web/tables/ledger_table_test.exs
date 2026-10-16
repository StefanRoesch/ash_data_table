defmodule DemoWeb.Tables.LedgerTableTest do
  @moduledoc """
  Aggregate and calculation columns on Postgres, read by Ash's SQL layer
  for people from whom policies hide records and fields.

  The tables are of resources that exist for the tests only
  (`test/support/ledger_tables.ex`): the demo's tasks, comments, labels and
  people under other names and other policies. A job shows the number of its
  remarks, which a member sees on their own jobs only, and its assignee's
  name as a `first` aggregate beside a calculation over the same
  relationship; a member reads the people of their own organization only.

  Three things are pinned here (the library's internal tickets):

    * #32: such a `first` aggregate, read in one statement with that
      calculation, shows nothing of a person the reader may not read
      (fixed in ash_sql 0.8.2).
    * #35: a statement with an aggregate beside a field that a field policy
      hides on some records is read, also where it is wrapped in a subquery
      (fixed in ash_sql 0.8.2).
    * #34: Ash cannot sort by an aggregate that a field policy hides on some
      records. The table does not offer that sort.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  # Four jobs, in the order of their titles: the member's own, the admin's,
  # one assigned to a person of another organization, and one assigned to
  # nobody. They have 2, 4, 1 and 0 remarks, and 2, 1, 1 and 0 tags.
  setup %{conn: conn} do
    world = world(tasks: 0, other_tasks: 0)
    [project | _] = world.projects

    [own, other, abroad, free] =
      for {title, assignee} <- [
            {"A own", world.member},
            {"B other", world.admin},
            {"C abroad", world.outsider},
            {"D free", nil}
          ] do
        Generator.generate(
          Generator.task(
            organization_id: world.organization.id,
            project_id: project.id,
            reporter_id: world.admin.id,
            assignee_id: assignee && assignee.id,
            title: title,
            estimate_hours: Decimal.new("5")
          )
        )
      end

    for {job, count} <- [{own, 2}, {other, 4}, {abroad, 1}], n <- 1..count do
      Generator.generate(
        Generator.comment(
          organization_id: world.organization.id,
          task_id: job.id,
          # the member's own are the even ones
          author_id: if(rem(n, 2) == 0, do: world.member.id, else: world.admin.id),
          body: "Remark #{n}",
          inserted_at: DateTime.add(~U[2026-01-01 12:00:00.000000Z], n, :minute)
        )
      )
    end

    tags =
      for {name, jobs} <- [{"open", [own, other]}, {"shut", [own, abroad]}], into: %{} do
        label =
          Generator.generate(
            Generator.label(organization_id: world.organization.id, name: name, colour: "#123456")
          )

        for job <- jobs do
          Generator.generate(
            Generator.task_label(
              organization_id: world.organization.id,
              task_id: job.id,
              label_id: label.id
            )
          )
        end

        {name, label}
      end

    %{world: world, own: own, other: other, abroad: abroad, free: free, tags: tags, conn: conn}
  end

  defp as(conn, reader),
    do: Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: reader}})

  defp jobs(conn, reader, query \\ "") do
    {:ok, view, html} = conn |> as(reader) |> live("/support/jobs" <> query)
    {view, html}
  end

  defp titles(html, id \\ "job"), do: column(html, id, "title")

  describe "a `first` aggregate over one related record, beside a calculation over the same relationship (#32)" do
    test "shows nothing of a related record the person may not read", %{conn: conn, world: world} do
      for actor <- [world.member, world.admin] do
        {_view, html} = jobs(conn, actor)

        assert titles(html) == ["A own", "B other", "C abroad", "D free"]

        assert column(html, "job", "assignee_name") ==
                 [world.member.name, world.admin.name, "", ""]

        # the reference cell beside it says the same
        assert column(html, "job", "assignee") == [world.member.name, world.admin.name, "", ""]

        # The calculation is what reaches the person of the other
        # organization: Ash applies no policy to what a calculation
        # references. It is the other join in the statement.
        assert column(html, "job", "assignee_role") == ["member", "admin", "member", ""]

        refute html =~ world.outsider.name
      end
    end

    test "nor when the page is sorted by the calculation", %{conn: conn, world: world} do
      {view, _html} = jobs(conn, world.member)

      view |> element("#job-head-assignee_role") |> render_click()
      html = render_async(view)

      assert titles(html) == ["B other", "A own", "C abroad", "D free"]
      assert column(html, "job", "assignee_name") == [world.admin.name, world.member.name, "", ""]
      refute html =~ world.outsider.name
    end

    test "nor after a cell of the row is saved", %{conn: conn, world: world, abroad: abroad} do
      {view, _html} = jobs(conn, world.member)

      html = save(view, "job", abroad.id, "title", "C still abroad")

      assert text(html, cell("job", abroad.id, "title")) == "C still abroad"
      assert text(html, cell("job", abroad.id, "assignee_name")) == ""
      refute html =~ world.outsider.name
    end

    test "nor in a nested table", %{
      conn: conn,
      world: world,
      tags: tags,
      abroad: abroad,
      own: own
    } do
      {:ok, view, _html} = conn |> as(world.member) |> live("/support/tags")
      expand(view, "tag", tags["shut"].id)
      html = toggle(view, "tag", tags["shut"].id, "jobs")
      id = nested("tag", tags["shut"].id, "jobs")

      assert titles(html, id) == ["A own", "C abroad"]
      assert text(html, cell(id, own.id, "assignee_name")) == world.member.name
      assert text(html, cell(id, abroad.id, "assignee_name")) == ""
      assert text(html, cell(id, abroad.id, "assignee_role")) == "member"
      refute html =~ world.outsider.name
    end
  end

  describe "a `first` aggregate over one related record, beside a reference cell of the same relationship" do
    # The reference cell loads the relationship in a statement of its own,
    # which is no other join in the statement of the aggregate.
    test "is read with the row, sorted and filtered by, and shows nothing of a record the person may not read",
         %{conn: conn, world: world} do
      conn = as(conn, world.member)
      {:ok, view, html} = live(conn, "/support/errands")

      assert column(html, "errand", "title") == ["A own", "B other", "C abroad", "D free"]

      assert column(html, "errand", "assignee_name") ==
               [world.member.name, world.admin.name, "", ""]

      assert column(html, "errand", "assignee") == [world.member.name, world.admin.name, "", ""]
      assert attribute(html, "#errand-head-assignee_name", "data-sort") == [""]
      refute html =~ world.outsider.name

      # sorted by the aggregate: the name of the person of the other
      # organization, which comes first in the alphabet, moves nothing
      view |> element("#errand-head-assignee_name") |> render_click()
      html = render_async(view)

      assert column(html, "errand", "assignee_name") ==
               [world.member.name, world.admin.name, "", ""]

      assert column(html, "errand", "title") == ["A own", "B other", "C abroad", "D free"]

      {:ok, _view, html} =
        live(
          conn,
          "/support/errands?errand[f][assignee_name][starts_with]=#{String.first(world.outsider.name)}"
        )

      assert column(html, "errand", "title") == []
      refute html =~ world.outsider.name
    end

    test "nor when the page is sorted or filtered by the aggregate", %{conn: conn, world: world} do
      {view, _html} = jobs(conn, world.member)

      view |> element("#job-head-assignee_name") |> render_click()
      html = render_async(view)

      assert text(html, "#job-error") == nil
      assert attribute(html, "#job-head-assignee_name", "aria-sort") == ["ascending"]
      assert Enum.sort(titles(html)) == ["A own", "B other", "C abroad", "D free"]
      refute html =~ world.outsider.name

      # the name of the person the member may not read matches nothing
      html = filter(view, "job", "assignee_name", v: world.outsider.name)
      assert text(html, "#job-error") == nil
      assert titles(html) == []
    end
  end

  describe "aggregate columns, for a person from whom a field policy hides a field on some records (#35)" do
    test "are shown on a page of a table of its own, with a calculation over one of them", %{
      conn: conn,
      world: world
    } do
      {_view, html} = jobs(conn, world.member)

      assert text(html, "#job-error") == nil
      assert titles(html) == ["A own", "B other", "C abroad", "D free"]
      assert text(html, "#job-range") == "1–4 of 4"
      # the number of remarks is the member's to see on their own job only
      assert column(html, "job", "remark_count") ==
               ["2", "Not available", "Not available", "Not available"]

      assert column(html, "job", "tag_count") == ["2", "1", "1", "0"]
      assert column(html, "job", "remarked?") == ["✓Yes", "✓Yes", "✓Yes", "–No"]

      assert column(html, "job", "estimate_hours") == [
               "5",
               "Not available",
               "Not available",
               "Not available"
             ]

      {_view, html} = jobs(conn, world.admin)
      assert column(html, "job", "remark_count") == ["2", "4", "1", "0"]
    end

    test "are shown on every page, in the order and with the total the read gives", %{
      conn: conn,
      world: world,
      own: own
    } do
      [project | _] = world.projects

      for n <- 1..3 do
        Generator.generate(
          Generator.task(
            organization_id: world.organization.id,
            project_id: project.id,
            reporter_id: world.admin.id,
            assignee_id: world.member.id,
            title: "E more #{n}"
          )
        )
      end

      {view, html} = jobs(conn, world.member)
      assert text(html, "#job-range") == "1–5 of 7"
      assert titles(html) == ["A own", "B other", "C abroad", "D free", "E more 1"]

      view |> element("#job-next") |> render_click()
      html = render_async(view)

      assert text(html, "#job-range") == "6–7 of 7"
      assert titles(html) == ["E more 2", "E more 3"]
      assert column(html, "job", "remark_count") == ["0", "0"]
      assert column(html, "job", "tag_count") == ["0", "0"]

      # a row that is saved has them again
      html = save(view, "job", own.id, "title", "A own")
      assert text(html, "#job-error") == nil
    end

    test "can be sorted and filtered by on a table of its own, where they are seen on every record",
         %{conn: conn, world: world} do
      {view, html} = jobs(conn, world.member)
      assert attribute(html, "#job-head-tag_count", "data-sort") == [""]

      view |> element("#job-head-tag_count") |> render_click()
      view |> element("#job-head-tag_count") |> render_click()
      html = render_async(view)

      assert attribute(html, "#job-head-tag_count", "aria-sort") == ["descending"]
      assert column(html, "job", "tag_count") == ["2", "1", "1", "0"]
      assert hd(titles(html)) == "A own"
      assert text(html, "#job-error") == nil

      html = filter(view, "job", "tag_count", o: "less_than", v: "2")
      assert column(html, "job", "tag_count") == ["1", "1", "0"]
      assert text(html, "#job-range") == "1–3 of 3"
    end

    test "are shown in a nested table that is read in full: through a join keyed on the pair, and of one of many",
         %{conn: conn, world: world, own: own} do
      {view, _html} = jobs(conn, world.member)
      expand(view, "job", own.id)

      html = toggle(view, "job", own.id, "tags")
      id = nested("job", own.id, "tags")

      assert text(html, "[id='#{id}-error']") == nil
      assert column(html, id, "name") == ["open", "shut"]
      assert column(html, id, "job_count") == ["2", "2"]
      # the colour is the member's to see on the tag called "open" only
      assert column(html, id, "colour") == ["#123456", "Not available"]

      html = toggle(view, "job", own.id, "latest_remark")
      id = nested("job", own.id, "latest_remark")

      assert text(html, "[id='#{id}-error']") == nil
      assert column(html, id, "body") == ["Remark 2"]
      assert column(html, id, "tagging_count") == ["2"]
      assert column(html, id, "tagged?") == ["✓Yes"]
    end

    test "are shown in a nested table that is read in pages, by offset and by keyset", %{
      conn: conn,
      world: world,
      other: other
    } do
      {view, _html} = jobs(conn, world.member)
      expand(view, "job", other.id)

      for relationship <- ["remarks", "remarks_by_keyset"] do
        html = toggle(view, "job", other.id, relationship)
        id = nested("job", other.id, relationship)

        assert text(html, "[id='#{id}-error']") == nil
        # the member wrote the even ones, and sees the body of those
        assert column(html, id, "body") == ["Not available", "Remark 2", "Not available"]
        assert column(html, id, "tagging_count") == ["1", "1", "1"]
        assert text(html, "[id='#{id}-range']") =~ "4"

        # and the next page is found from the last of these records: its
        # place in the order, or its cursor, is as the read gave it
        click(view, "[id='#{id}-next']")
        html = render_async(view)

        assert column(html, id, "body") == ["Remark 4"]
        assert column(html, id, "tagging_count") == ["1"]
      end
    end

    test "can be sorted by in a nested table that is read in pages",
         %{conn: conn, world: world, other: other} do
      {view, _html} = jobs(conn, world.member)
      expand(view, "job", other.id)

      html = toggle(view, "job", other.id, "remarks")
      id = nested("job", other.id, "remarks")

      assert attribute(html, "[id='#{id}-head-tagging_count']", "data-sort") == [""]
      assert attribute(html, "[id='#{id}-head-tagged?']", "data-sort") == [""]

      click(view, "[id='#{id}-head-tagging_count']")
      html = render_async(view)
      assert text(html, "[id='#{id}-error']") == nil
      assert attribute(html, "[id='#{id}-head-tagging_count']", "aria-sort") == ["ascending"]
      assert column(html, id, "body") == ["Not available", "Remark 2", "Not available"]

      click(view, "[id='#{id}-head-tagged?']")
      html = render_async(view)
      assert text(html, "[id='#{id}-error']") == nil
      assert attribute(html, "[id='#{id}-head-tagged?']", "aria-sort") == ["ascending"]
      assert length(column(html, id, "body")) == 3
    end

    test "and by a person who sees every field on every record", %{
      conn: conn,
      world: world,
      other: other
    } do
      {view, _html} = jobs(conn, world.admin)
      expand(view, "job", other.id)
      toggle(view, "job", other.id, "remarks")
      id = nested("job", other.id, "remarks")

      click(view, "[id='#{id}-head-tagging_count']")
      html = render_async(view)

      assert attribute(html, "[id='#{id}-head-tagging_count']", "aria-sort") == ["ascending"]
      assert text(html, "[id='#{id}-error']") == nil
      assert column(html, id, "body") == ["Remark 1", "Remark 2", "Remark 3"]
    end

    # as on a table of its own: the resource does not sort by an aggregate
    # or a calculation under keyset pagination
    test "are sorted by for nobody in a nested table that is read in pages by keyset", %{
      conn: conn,
      world: world,
      other: other
    } do
      for actor <- [world.member, world.admin] do
        {view, _html} = jobs(conn, actor)
        expand(view, "job", other.id)
        html = toggle(view, "job", other.id, "remarks_by_keyset")
        id = nested("job", other.id, "remarks_by_keyset")

        assert attribute(html, "[id='#{id}-head-tagging_count']", "data-sort") == []
        assert attribute(html, "[id='#{id}-head-tagged?']", "data-sort") == []
        assert attribute(html, "[id='#{id}-head-inserted_at']", "data-sort") == [""]
      end
    end
  end

  describe "an aggregate column that a field policy hides from the person on some records (#34)" do
    test "cannot be sorted by: Ash raises where it would have to", %{conn: conn, world: world} do
      {view, html} = jobs(conn, world.member)

      assert attribute(html, "#job-head-remark_count", "data-sort") == []
      assert attribute(html, "#job-head-remark_count", "aria-sort") == []

      forge(view, "job", "sort", %{"column" => "remark_count"})
      html = render_async(view)
      assert text(html, "#job-error") == nil
      assert titles(html) == ["A own", "B other", "C abroad", "D free"]

      {_view, html} = jobs(conn, world.member, "?job[sort]=-remark_count")
      assert text(html, "#job-error") == nil
      assert titles(html) == ["A own", "B other", "C abroad", "D free"]
      assert attribute(html, "#job-head-remark_count", "aria-sort") == []
    end

    test "can be sorted by a person who sees it on every record", %{conn: conn, world: world} do
      {_view, html} = jobs(conn, world.admin, "?job[sort]=-remark_count")

      assert titles(html) == ["B other", "A own", "C abroad", "D free"]
      assert attribute(html, "#job-head-remark_count", "aria-sort") == ["descending"]
    end

    test "can be filtered by, and tells nothing of the records it is hidden on", %{
      conn: conn,
      world: world
    } do
      {view, _html} = jobs(conn, world.member)

      # the admin's job has four remarks, which the member may not know
      html = filter(view, "job", "remark_count", o: "at_least", v: "2")

      assert titles(html) == ["A own"]
      assert text(html, "#job-range") == "1–1 of 1"
      assert text(html, "#job-status") == "1 result"

      {_view, html} = jobs(conn, world.admin, "?job[f][remark_count][at_least]=2")
      assert titles(html) == ["A own", "B other"]
    end
  end
end
