defmodule DemoWeb.MarkupSnapshotTest do
  @moduledoc """
  The markup of the table in the states the refactor moves code under:
  rendered by
  LiveViewTest, normalised, and compared with the files in
  `test/snapshots/`. A stage of the refactor that changes none of the
  table's behaviour changes none of them.

  `MIX_SNAPSHOT_UPDATE=1 mix test test/demo_web/markup_snapshot_test.exs`
  writes them anew. A file that is not there is an error, not written.

  Normalised before they are compared: the module part of `phx-hook` names,
  the table's id in the name of an event (`ash_data_table:ID:`),
  `phx-target` and the target of a `JS.push` (an attached table has none), every `data-phx-*` attribute, LiveView's own
  ids, CSRF tokens, record keys (each uuid becomes `uuid-N` by its first
  place in the page) and what the per-test ids put into an email.
  """
  # the support pages keep their records in ETS tables of their own
  use DemoWeb.ModeCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Support.Asked.{Lot, Shelf, Stock}
  alias Demo.Support.Maps.{Contact, Part, Place, Site}
  alias Demo.Tracker.Task

  @dir Path.expand("../snapshots", __DIR__)
  @moment ~U[2026-01-01 12:00:00.000000Z]

  # ---- data ---------------------------------------------------------------

  defp task(world, n, overrides \\ []) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          assignee_id: nil,
          title: "Task #{String.pad_leading(to_string(n), 2, "0")}",
          description: nil,
          status: :in_progress,
          priority: :medium,
          progress: 10 * rem(n, 10),
          estimate_hours: Decimal.new("12.5"),
          billable?: rem(n, 2) == 0,
          due_on: Date.add(~D[2026-02-01], n),
          completed_at: nil,
          external_ref: nil,
          internal_note: nil,
          tags: [],
          checks: [],
          recurrence: nil,
          inserted_at: DateTime.add(@moment, n, :hour),
          updated_at: DateTime.add(@moment, n, :hour)
        ] ++ overrides
      )
    )
  end

  defp comment(world, task, n, author) do
    Generator.generate(
      Generator.comment(
        organization_id: world.organization.id,
        task_id: task.id,
        author_id: author.id,
        body: "Comment #{n}",
        inserted_at: DateTime.add(@moment, n, :minute),
        updated_at: DateTime.add(@moment, n, :minute)
      )
    )
  end

  defp tracker(_context) do
    world = world(tasks: 0, other_tasks: 0)

    # what the generator derives from a project's id, or from today, is
    # fixed here: the ids are the test's own
    projects =
      for {project, n} <- Enum.with_index(world.projects, 1) do
        Ash.Seed.update!(project, %{
          client: nil,
          milestones: [],
          budget: Decimal.new(n * 1000),
          starts_on: Date.add(~D[2025-06-01], n),
          inserted_at: DateTime.add(@moment, -n, :day),
          updated_at: DateTime.add(@moment, -n, :day)
        })
      end

    world = %{world | projects: projects}
    tasks = for n <- 1..30, do: task(world, n)
    first = List.last(tasks)
    comments = for n <- 1..12, do: comment(world, first, n, world.member)
    %{world: world, tasks: tasks, first: first, comments: comments}
  end

  # ---- comparing ----------------------------------------------------------

  defp snapshot(name, html) do
    path = Path.join(@dir, name <> ".html")
    markup = normalise(html)

    # no `style` attribute: the demo's Content-Security-Policy refuses them
    # (`style-src 'self'`, DemoWeb.Router)
    refute markup =~ ~r/<[^>]*\sstyle=/, "#{name}: a `style` attribute in the markup"

    if System.get_env("MIX_SNAPSHOT_UPDATE") == "1" do
      File.mkdir_p!(@dir)
      File.write!(path, markup)
    else
      assert File.exists?(path),
             "no snapshot #{path}: write it with MIX_SNAPSHOT_UPDATE=1"

      stored = File.read!(path)

      if stored != markup do
        {line, at} = first_difference(stored, markup)

        flunk("""
        the markup of #{name} is not its snapshot (#{path}), from line #{at}:
          snapshot: #{line |> elem(0) |> String.slice(0, 400)}
          now:      #{line |> elem(1) |> String.slice(0, 400)}
        """)
      end
    end
  end

  defp first_difference(stored, markup) do
    stored = String.split(stored, "\n")
    markup = String.split(markup, "\n")
    count = max(length(stored), length(markup))

    Enum.find_value(0..(count - 1), fn at ->
      {old, new} = {Enum.at(stored, at, ""), Enum.at(markup, at, "")}
      if old != new, do: {{old, new}, at + 1}
    end)
  end

  @doc false
  def normalise(html) do
    html =
      html
      |> without_tag_wrapper()
      |> portals()
      |> String.replace(~r/ phx-hook="[^"]*?(\.[A-Za-z]+)"/, ~s( phx-hook="\\1"))
      |> String.replace(
        ~r/((?: phx-(?:click|change|submit)="|&quot;event&quot;:&quot;))ash_data_table:[^:"&]+:/,
        "\\1"
      )
      |> String.replace(~r/ phx-target="[^"]*"/, "")
      |> String.replace(~r/&quot;target&quot;:\d+,/, "")
      |> String.replace(~r/ data-phx-[a-z-]+(="[^"]*")?/, "")
      |> String.replace(~r/\bphx-[A-Za-z0-9_-]{16,}\b/, "phx-ID")
      |> String.replace(~r/(name="_csrf_token" value=")[^"]*"/, ~s(\\1CSRF"))
      |> String.replace(~r/(<meta name="csrf-token" content=")[^"]*"/, ~s(\\1CSRF"))
      |> String.replace(~r/-[0-9a-f]{12}@example\.test/, "-ID@example.test")

    uuids =
      ~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
      |> Regex.scan(html)
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.with_index(1)
      |> Map.new()

    html
    |> String.replace(
      Regex.compile!("[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}"),
      &"uuid-#{uuids[&1]}"
    )
    |> sort_attributes()
    |> String.replace("><", ">\n<")
    |> Kernel.<>("\n")
  end

  # The tag's live component draws a plain element around the table's root
  # (a live component's root must be static: the kit's class of an element
  # that takes no part in the layout, `class(:portal, …)`); the table is
  # drawn the same in every mode inside it, and that element is no part of
  # the table's markup (one per tag: a page may have two). It is the root
  # of a live component, which LiveView marks (`data-phx-component`).
  defp without_tag_wrapper(html) do
    case Regex.run(
           ~r/<div(?=[^>]*\sdata-phx-component=)(?=[^>]*\sclass="contents")[^>]*>/,
           html,
           return: :index
         ) do
      nil ->
        html

      [{at, length}] ->
        stop = closing(html, at + length, "div", 1)
        inner = binary_part(html, at + length, stop - 6 - (at + length))

        without_tag_wrapper(
          binary_part(html, 0, at) <> inner <> binary_part(html, stop, byte_size(html) - stop)
        )
    end
  end

  # The page as the browser makes it of a nested table's portal. The
  # table marks what goes into a cell with the cell's id
  # (`data-ash-data-table-portal`); `<.portal>` renders it inside a
  # `<template>` with the portal's id (`ID-portal`), and the browser moves
  # it to the end of the cell. Here, in the order of the page (a parent's
  # portal comes before its children's): the marked element goes to the
  # end of its cell, and the template it was in, empty, is dropped.
  defp portals(html),
    do: html |> moved() |> String.replace(" data-moved-portal=", " data-ash-data-table-portal=")

  # Each moved element's mark is set aside until all are (` data-moved-portal`).
  defp moved(html) do
    case Regex.run(~r/ data-ash-data-table-portal="([^"]+)"/, html, return: :index) do
      nil ->
        html

      [{marker, _length}, {target_at, target_length}] ->
        target = binary_part(html, target_at, target_length)
        element_start = last_before(html, marker, "<")
        element_stop = closing(html, open_end(html, element_start), "div", 1)

        element =
          html
          |> binary_part(element_start, element_stop - element_start)
          |> String.replace(" data-ash-data-table-portal=", " data-moved-portal=", global: false)

        template_start = last_before(html, element_start, "<template")
        template_stop = closing(html, open_end(html, template_start), "template", 1)

        html =
          binary_part(html, 0, template_start) <>
            binary_part(html, template_stop, byte_size(html) - template_stop)

        html |> put_into(target, element) |> moved()
    end
  end

  defp last_before(html, at, text),
    do: html |> binary_part(0, at) |> :binary.matches(text) |> List.last() |> elem(0)

  defp open_end(html, at),
    do: at + (html |> binary_part(at, byte_size(html) - at) |> :binary.match(">") |> elem(0)) + 1

  # The end of the element whose start tag ends at `from`, by counting the
  # tags of its name.
  defp closing(html, from, tag, depth) do
    rest = binary_part(html, from, byte_size(html) - from)

    {open_at, _} =
      :binary.match(rest, "<#{tag}") |> then(&if &1 == :nomatch, do: {:infinity, 0}, else: &1)

    {close_at, close_length} = :binary.match(rest, "</#{tag}>")

    cond do
      open_at < close_at -> closing(html, from + open_at + 1, tag, depth + 1)
      depth == 1 -> from + close_at + close_length
      true -> closing(html, from + close_at + close_length, tag, depth - 1)
    end
  end

  # Puts `inner` at the end of the element with the id `id`.
  defp put_into(html, id, inner) do
    {at, _} = :binary.match(html, ~s(id="#{id}"))
    tag_start = html |> binary_part(0, at) |> :binary.matches("<") |> List.last() |> elem(0)
    [_, tag] = Regex.run(~r/\A<([a-zA-Z0-9-]+)/, binary_part(html, tag_start, at - tag_start))

    open_end =
      at + (html |> binary_part(at, byte_size(html) - at) |> :binary.match(">") |> elem(0)) + 1

    stop = closing(html, open_end, tag, 1) - byte_size("</#{tag}>")
    before = html |> binary_part(0, stop) |> String.trim_trailing()

    before <> inner <> binary_part(html, stop, byte_size(html) - stop)
  end

  # The order in which a tag's attributes come out is not part of the markup:
  # some are rendered from a map, whose order follows the atom table, and so
  # which modules happened to be loaded first. Each tag's attributes are put
  # in the order of their names.
  defp sort_attributes(html) do
    Regex.replace(
      ~r/<([a-zA-Z][a-zA-Z0-9.-]*)((?:\s+[^\s=>\/]+(?:="[^"]*")?)+)(\s*\/?)>/,
      html,
      fn
        _all, tag, attributes, close ->
          sorted =
            ~r/\s+([^\s=>\/]+(?:="[^"]*")?)/
            |> Regex.scan(attributes, capture: :all_but_first)
            |> List.flatten()
            |> Enum.sort()

          "<" <> tag <> Enum.map_join(sorted, &(" " <> &1)) <> close <> ">"
      end
    )
  end

  # ---- the states ---------------------------------------------------------

  describe "the task table" do
    setup :tracker

    test "1 the first page, as the member", %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")
      snapshot("01-tasks-first-page", render_async(view, 10_000))
    end

    test "2 sorted, filtered with an operator still to fill in, on page 2 at a size from the URL",
         %{conn: conn, world: world} do
      {:ok, view, _html} =
        conn
        |> log_in(world.member)
        |> live("/tasks?task[sort]=-title&task[per]=10&task[page]=2&task[f][title]=Task")

      render_async(view, 10_000)
      html = filter(view, "task", "progress", o: "at_least")
      snapshot("02-tasks-sorted-filtered-page-2", html)
    end

    test "3 a task expanded, its comments open in a nested table with pages and the full view",
         %{conn: conn, world: world, first: first} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")
      expand(view, first.id)
      snapshot("03-tasks-nested-comments", toggle(view, first.id, "comments"))
    end

    test "4 two levels deep: a task, its comments, a comment's author",
         %{conn: conn, world: world, first: first, comments: comments} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")
      expand(view, first.id)
      toggle(view, first.id, "comments")
      inner = nested(first.id, "comments")
      comment = List.last(comments)
      expand(view, inner, comment.id)
      snapshot("04-tasks-two-levels", toggle(view, inner, comment.id, "author"))
    end

    test "5 the picker open on a reference cell, the current record marked",
         %{conn: conn, world: world, first: first} do
      Ash.update!(first, %{assignee_id: world.member.id}, authorize?: false)
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      pick(view, first.id, "assignee")
      snapshot("05-tasks-picker", render_async(view, 10_000))
    end

    test "6 the create panel with a reference field; a panel's picker for several records",
         %{conn: conn, world: world, first: first} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      snapshot("06a-tasks-create-panel", open_create(view))
      cancel_panel(view)

      act(view, first.id, "set_labels")
      pick_input(view, "labels")
      snapshot("06b-tasks-labels-picker", render_async(view, 10_000))
    end

    test "8 a cell whose save failed, and a row action that failed",
         %{conn: conn, world: world, tasks: tasks} do
      [mine, foreign | _] = Enum.reverse(tasks)
      Ash.update!(mine, %{assignee_id: world.member.id}, authorize?: false)
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")
      save(view, mine.id, "title", "")
      snapshot("08-tasks-failures", act(view, foreign.id, "archive"))
    end

    test "9a after an action on the selected rows that failed on some, and a table action's result",
         %{conn: conn, world: world, tasks: tasks} do
      [mine, foreign | _] = Enum.reverse(tasks)
      Ash.update!(mine, %{assignee_id: world.member.id}, authorize?: false)
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")
      snapshot("09a-tasks-bulk-failures", run_bulk(view, "archive", [mine.id, foreign.id]))

      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/labels")
      snapshot("09b-labels-table-action", table_act(view, "label", "count_unused"))
    end

    test "10 the dashboard: two tables placed in a page, a masked column, a live update's notice",
         %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/dashboard")
      render_async(view, 10_000)

      [project | _] = world.projects
      Ash.create!(Task, %{title: "Arrived meanwhile", project_id: project.id}, as(world.admin))
      AshDataTable.Test.flush(view)
      snapshot("10-dashboard", render_async(view, 10_000))
    end
  end

  describe "what the page offers" do
    setup do
      on_exit(fn ->
        Demo.Support.Ets.stop([Demo.Support.Given.Card, Demo.Support.Given.Remark])
      end)
    end

    test "11 \"Open\" first in every row's actions cell", %{conn: conn} do
      for title <- ["First", "Second"],
          do: Ash.Seed.seed!(Demo.Support.Given.Card, %{title: title})

      {:ok, view, _html} =
        live_isolated(conn, DemoWeb.Support.GivenLive,
          session: %{"test" => self(), "open" => "Open"}
        )

      snapshot("11-cards-open", render_async(view, 10_000))
    end
  end

  describe "the panels of map cells and unions" do
    setup do
      on_exit(fn -> Demo.Support.Ets.stop(Site) end)
    end

    test "7a a map cell's panel, with groups", %{conn: conn} do
      site =
        Ash.Seed.seed!(Site, %{
          name: "Harbour",
          place: %Place{street: "Quay 1", city: "Kiel", floor: 2, since: ~D[2020-05-01]},
          contact: %Contact{name: "Ida", place: %Place{street: "Lane 5", city: "Bonn"}},
          parts: [
            %Part{id: "11111111-2222-4333-8444-555555555555", name: "Crane", quantity: 2},
            %Part{id: "21111111-2222-4333-8444-555555555555", name: "Winch"}
          ]
        })

      {:ok, view, _html} =
        conn
        |> Phoenix.ConnTest.init_test_session(%{
          "assigns" => %{current_user: %{id: "ada", name: "ada", role: :admin}}
        })
        |> live("/support/sites")

      snapshot("07a-site-map-panel", edit(view, "site", site.id, "place"))
      cancel_panel(view, "site")
      snapshot("07b-site-groups-panel", edit(view, "site", site.id, "parts"))
    end

    test "7c a union's panel", %{conn: conn} do
      Generator.reseed(1)

      specimen =
        Generator.generate(
          Generator.specimen(label: "Shown", a_union: %Ash.Union{type: :number, value: 12})
        )

      {:ok, view, _html} = live(conn, "/specimens")
      edit(view, "specimen", specimen.id, "a_union")

      # the panel alone: the generator gives a specimen's other fields
      # values that follow from today
      snapshot("07c-specimen-union-panel", view |> element("#specimen-panel") |> render())
    end
  end

  describe "the argument line" do
    setup %{conn: conn} do
      attic = Ash.create!(Shelf, %{name: "Attic", closed: false})

      for {name, amount} <- [{"apple", 1}, {"banana", 5}, {"cherry", 10}] do
        stock =
          Ash.create!(Stock, %{name: name, amount: amount, kind: :plain, shelf_id: attic.id},
            authorize?: false
          )

        Ash.create!(Lot, %{code: "L-#{name}", size: amount, stock_id: stock.id})
      end

      on_exit(fn -> Demo.Support.Ets.stop([Stock, Lot, Shelf]) end)

      %{
        conn: Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: %{role: :admin}}})
      }
    end

    test "9c the fill message, and a value Ash refuses", %{conn: conn} do
      {:ok, view, html} = live(conn, "/support/stocks")
      snapshot("09c-stocks-fill", html)

      argue(view, "stock", a: %{"at_least" => "0"})
      snapshot("09d-stocks-refused", argue(view, "stock", a: %{"at_least" => "-1"}))
    end
  end
end
