defmodule DemoWeb.Tables.ProjectBudgetTest do
  @moduledoc """
  A sensitive column on Postgres: a project's `budget`, at `/projects`. It
  is masked for those who may see it (admins and members), until they ask
  for the value of one cell; a viewer, from whom a field policy hides the
  field, has no column. Nothing of a budget is in the page, or in what the
  server sends, before somebody asks.

  Everything else a table does with a sensitive field is in
  `sensitive_table_test.exs`.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Project

  # values that are found nowhere else in a page: not in an id, not in a date
  @budget "7654321.5"
  @other "8642097"

  setup do
    world = world(tasks: 0, other_tasks: 0, projects: 0)

    project = fn name, budget ->
      Generator.generate(
        Generator.project(
          organization_id: world.organization.id,
          name: name,
          budget: budget && Decimal.new(budget),
          client: nil,
          milestones: []
        )
      )
    end

    %{
      world: world,
      rich: project.("Alpha", @budget),
      other: project.("Beta", @other),
      bare: project.("Gamma", nil)
    }
  end

  defp stored(project), do: Ash.get!(Project, project.id, authorize?: false)
  defp names(html), do: column(html, "project", "name")

  describe "for a member, who may see the budget" do
    setup %{conn: conn, world: world} do
      conn = log_in(conn, world.member)
      {:ok, view, html} = live(conn, "/projects")
      %{conn: conn, view: view, html: html}
    end

    test "a cell with a budget shows the mask, the same for every value, and a button named with the column",
         %{html: html, rich: rich, other: other} do
      for project <- [rich, other] do
        assert masked(html, "project", project.id, "budget") == %{
                 mask: "••••••",
                 hidden?: true,
                 said: "Hidden",
                 shown: "",
                 live: ["polite"],
                 button: "Show",
                 label: "Show Budget",
                 tabindex: nil
               }
      end
    end

    test "a cell without a budget is empty, and has no button", %{html: html, bare: bare} do
      assert text(html, cell("project", bare.id, "budget")) == ""
      assert masked(html, "project", bare.id, "budget") == nil
    end

    test "no budget is in the page: not as it is first rendered, and not once it is live",
         %{conn: conn, html: html} do
      rendered = conn |> get("/projects") |> html_response(200)

      for page <- [rendered, html] do
        refute page =~ @budget
        refute page =~ "7654321"
        refute page =~ @other
      end
    end

    test "the column is neither sorted nor filtered by, and a URL that says so is not followed",
         %{conn: conn, html: html} do
      assert attribute(html, "#project-head-budget", "data-sort") == []
      assert attribute(html, "#project-head-budget", "aria-sort") == []
      assert attribute(html, "#project-filter-budget", "data-filter") == []
      assert filter_controls(html, "project", "budget").input == nil

      {:ok, _view, html} =
        live(conn, "/projects?project[sort]=-budget&project[f][budget]=#{@other}")

      # in the read action's order, with every project: neither was applied
      assert names(html) == ["Alpha", "Beta", "Gamma"]
      refute html =~ @other
    end

    test "an event that sorts or filters by it changes nothing", %{view: view} do
      forge(view, "project", "sort", %{"column" => "budget"})

      html =
        forge(view, "project", "filter", %{
          "filter" => %{"budget" => %{"o" => "equals", "v" => @other}}
        })

      assert names(html) == ["Alpha", "Beta", "Gamma"]
      assert names(render_async(view)) == ["Alpha", "Beta", "Gamma"]
    end

    test "asking for one cell is answered with its value, to the hook alone", %{
      view: view,
      rich: rich
    } do
      wire =
        wire(view, fn ->
          html = reveal(view, "project", rich.id, "budget")
          assert_reply view, %{ok: true, value: @budget}
          # nothing of it is rendered: the hook shows it, and takes it away
          refute html =~ "7654321"
        end)

      # once, in the answer; and no other budget with it
      assert wire |> String.split("7654321") |> length() == 2
      refute wire =~ @other
      refute render(view) =~ "7654321"
      assert masked(render(view), "project", rich.id, "budget").mask == "••••••"
    end

    test "the record is read again when it is asked for: the value is the one it has now", %{
      view: view,
      rich: rich
    } do
      Ash.update!(rich, %{budget: Decimal.new("1122334")}, authorize?: false)

      reveal(view, "project", rich.id, "budget")
      assert_reply view, %{ok: true, value: "1122334"}
    end

    test "nothing is sent of a budget when the table reads again", %{view: view} do
      wire =
        wire(view, fn ->
          view |> element("#project-sort-name") |> render_click()
          assert names(render_async(view)) == ["Alpha", "Beta", "Gamma"]
          view |> element("#project-sort-name") |> render_click()
          assert names(render_async(view)) == ["Gamma", "Beta", "Alpha"]
        end)

      # the rows went over the wire again, and no budget with them
      assert wire =~ "Gamma"
      refute wire =~ "7654321"
      refute wire =~ @other
    end

    test "a row that is asked for and is not on the page, or a column that is not sensitive, is answered with nothing",
         %{view: view, rich: rich, world: world} do
      reveal(view, "project", Ash.UUID.generate(), "budget")
      assert_reply view, %{ok: false}

      reveal(view, "project", rich.id, "name")
      assert_reply view, %{ok: false}

      reveal(view, "project", rich.id, "organization_id")
      assert_reply view, %{ok: false}

      # a project of another organization is no row of this page
      foreign =
        Generator.generate(
          Generator.project(
            organization_id: world.other_organization.id,
            name: "Abroad",
            budget: Decimal.new("9988776")
          )
        )

      wire =
        wire(view, fn ->
          reveal(view, "project", foreign.id, "budget")
          assert_reply view, %{ok: false}
        end)

      refute wire =~ "9988776"
    end

    test "a record that is gone when it is asked for is said to be gone", %{
      view: view,
      rich: rich
    } do
      Ash.destroy!(rich, authorize?: false)

      reveal(view, "project", rich.id, "budget")
      assert_reply view, %{ok: false, error: "This record is no longer available."}
    end

    test "the editor hides what is typed, and holds nothing of the record", %{
      html: html,
      rich: rich
    } do
      assert editor(html, "project", "budget") == %{
               control: "password",
               choices: nil,
               confirm: nil
             }

      assert attribute(html, "#project-editor-budget", "data-editor") == ["secret"]
      # what the cell says its editor holds: nothing
      assert attribute(html, cell("project", rich.id, "budget"), "data-value") == [""]
      assert attribute(html, cell("project", rich.id, "budget"), "data-saved") == []
    end

    test "what is typed is saved, and is not sent back", %{view: view, rich: rich} do
      wire =
        wire(view, fn ->
          html = save(view, "project", rich.id, "budget", "4455667")
          assert_reply view, %{ok: true}
          refute html =~ "4455667"
          assert masked(html, "project", rich.id, "budget").mask == "••••••"
        end)

      refute wire =~ "4455667"
      assert Decimal.equal?(stored(rich).budget, Decimal.new("4455667"))
    end

    test "an editor nothing was typed into saves nothing: the budget is not emptied", %{
      view: view,
      rich: rich
    } do
      before = stored(rich)

      html = save(view, "project", rich.id, "budget", "")

      assert_reply view, %{ok: true}
      assert failure(html, "project", rich.id, "budget") == nil
      assert Decimal.equal?(stored(rich).budget, Decimal.new(@budget))
      assert stored(rich).updated_at == before.updated_at
    end

    test "a cell that was empty gets a budget, and then its mask", %{view: view, bare: bare} do
      html = save(view, "project", bare.id, "budget", "1500")

      assert Decimal.equal?(stored(bare).budget, Decimal.new("1500"))
      assert masked(html, "project", bare.id, "budget").label == "Show Budget"
    end

    test "a save that fails marks the cell, which shows its mask and never what was typed", %{
      view: view,
      rich: rich
    } do
      wire =
        wire(view, fn ->
          html = save(view, "project", rich.id, "budget", "33x44x55")
          assert_reply view, %{ok: false}

          assert %{message: "is invalid", shown: shown} =
                   failure(html, "project", rich.id, "budget")

          assert shown =~ "••••••"
          refute html =~ "33x44x55"
          # what the hook compares the next edit with: nothing
          assert attribute(html, cell("project", rich.id, "budget"), "data-value") == [""]
          assert attribute(html, cell("project", rich.id, "budget"), "data-saved") == [""]
          assert announcement(html, "project") == "Budget was not saved: is invalid"
        end)

      refute wire =~ "33x44x55"
      refute wire =~ "7654321"

      # nor does the server keep either: the row's record is held for the
      # failed cell, without its budget, and what was typed is not held
      held = kept(view)
      assert held =~ "is invalid"
      refute held =~ "33x44x55"
      refute held =~ "7654321"
      assert Decimal.equal?(stored(rich).budget, Decimal.new(@budget))

      # Escape gives the failed edit up
      html = discard(view, "project", rich.id, "budget")
      assert failure(html, "project", rich.id, "budget") == nil
    end

    test "\"Clear\" in the editor empties the budget, and nothing of it is sent", %{
      view: view,
      html: html,
      rich: rich,
      other: other
    } do
      assert html =~ ~s(aria-label="Clear Budget")

      wire =
        wire(view, fn ->
          html = clear(view, "project", rich.id, "budget")
          assert_reply view, %{ok: true}
          assert text(html, cell("project", rich.id, "budget")) == ""
          assert masked(html, "project", rich.id, "budget") == nil
        end)

      refute wire =~ "7654321"
      assert stored(rich).budget == nil
      assert Decimal.equal?(stored(other).budget, Decimal.new(@other))
    end

    test ~s["Set budget" has "Clear" for a project with a budget, which empties it when the action runs],
         %{view: view, rich: rich, bare: bare} do
      html = act(view, "project", bare.id, "set_budget")
      assert text(html, "#project-panel-f-budget-clear") == nil
      cancel_panel(view, "project")

      html = act(view, "project", rich.id, "set_budget")
      assert text(html, "#project-panel-f-budget-clear") == "Clear"
      assert attribute(html, "#project-panel-f-budget-clear", "aria-label") == ["Clear Budget"]

      html = clear_in_panel(view, "project", "budget")
      assert text(html, "#project-panel-f-budget-cleared") == "Will be cleared."
      assert Decimal.equal?(stored(rich).budget, Decimal.new(@budget))

      wire =
        wire(view, fn ->
          html = run_panel(view, "project", %{})
          assert panel(html, "project") == nil
          assert masked(html, "project", rich.id, "budget") == nil
        end)

      refute wire =~ "7654321"
      assert stored(rich).budget == nil
    end

    test "the budget is spoken of in the person's language", %{conn: conn, rich: rich} do
      {:ok, _view, html} = conn |> in_locale("de") |> live("/projects")

      assert %{said: "Verborgen", button: "Anzeigen", label: "Budget anzeigen"} =
               masked(html, "project", rich.id, "budget")

      assert attribute(html, "#{cell("project", rich.id, "budget")} button", "data-hide") ==
               ["Verbergen"]

      assert attribute(html, "#{cell("project", rich.id, "budget")} button", "data-hide-label") ==
               ["Budget verbergen"]
    end
  end

  describe "for an admin" do
    test "the field of the create panel hides what is typed, and starts empty", %{
      conn: conn,
      world: world
    } do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/projects")

      html = open_create(view, "project")

      assert attribute(html, "#project-panel-f-budget", "type") == ["password"]
      assert attribute(html, "#project-panel-f-budget", "autocomplete") == ["off"]
      assert attribute(html, "#project-panel-f-budget", "value") in [[], [""]]

      # what is typed comes back with the form, as in any field: the browser
      # would lose it otherwise when another field is changed
      html = type_in_panel(view, "project", name: "Delta", budget: "5566778")
      assert attribute(html, "#project-panel-f-budget", "value") == ["5566778"]
    end

    test "a project that is created with a budget has its mask, and the page nothing of the budget",
         %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/projects")

      open_create(view, "project")

      wire =
        wire(view, fn ->
          html = run_panel(view, "project", name: "Delta", budget: "5566778")
          refute html =~ "5566778"
        end)

      refute wire =~ "5566778"

      [created] =
        Project |> Ash.read!(authorize?: false) |> Enum.filter(&(&1.name == "Delta"))

      assert Decimal.equal?(created.budget, Decimal.new("5566778"))
      assert masked(render(view), "project", created.id, "budget").mask == "••••••"
    end

    test "a field that is left empty gives the action nothing", %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/projects")

      open_create(view, "project")
      run_panel(view, "project", name: "Epsilon", budget: "")

      [created] =
        Project |> Ash.read!(authorize?: false) |> Enum.filter(&(&1.name == "Epsilon"))

      assert created.budget == nil
    end
  end

  describe "for a viewer, from whom a field policy hides the budget" do
    setup %{conn: conn, world: world} do
      {:ok, view, html} = conn |> log_in(world.viewer) |> live("/projects")
      %{view: view, html: html}
    end

    test "there is no column, and nothing of a budget in the page", %{html: html} do
      refute "Budget" in headers(html, "project")
      assert attribute(html, "[id$='-c-budget']", "id") == []
      refute html =~ "7654321"
    end

    test "asking for a cell all the same is answered with nothing", %{view: view, rich: rich} do
      wire =
        wire(view, fn ->
          reveal(view, "project", rich.id, "budget")
          assert_reply view, %{ok: false}
        end)

      refute wire =~ "7654321"
    end

    test "a save of it all the same saves nothing", %{view: view, rich: rich} do
      save(view, "project", rich.id, "budget", "1")
      assert_reply view, %{ok: false}
      assert Decimal.equal?(stored(rich).budget, Decimal.new(@budget))
    end

    test "nor does emptying it", %{view: view, rich: rich} do
      clear(view, "project", rich.id, "budget")
      assert_reply view, %{ok: false}
      assert Decimal.equal?(stored(rich).budget, Decimal.new(@budget))
    end
  end
end
