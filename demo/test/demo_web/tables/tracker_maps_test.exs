defmodule DemoWeb.Tables.TrackerMapsTest do
  @moduledoc """
  The values made of fields in the issue tracker, on Postgres: a project's
  `client`, an embedded resource with an address inside it, and its
  `milestones`, an array of embedded resources with a primary key, at
  `/projects`; and a task's `recurrence`, a map that declares its fields,
  at `/tasks` ("Repeats").

  Everything else a table does with such a value is in
  `map_table_test.exs`.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.{Address, Client, Milestone, Project, Task}

  @kickoff "0a000000-0000-4000-8000-000000000001"
  @handover "0a000000-0000-4000-8000-000000000002"

  setup do
    world = world(tasks: 0, other_tasks: 0, projects: 0)

    project =
      Generator.generate(
        Generator.project(
          organization_id: world.organization.id,
          name: "Website",
          client: %Client{
            name: "Nordwind GmbH",
            email: "office@nordwind.test",
            key_account?: true,
            address: %Address{street: "Kai 1", city: "Kiel", postcode: "24103"},
            credit_note: "private"
          },
          milestones: [
            %Milestone{id: @kickoff, title: "Kick-off", due_on: ~D[2026-11-02], reached?: true},
            %Milestone{id: @handover, title: "Handover"}
          ]
        )
      )

    bare =
      Generator.generate(
        Generator.project(
          organization_id: world.organization.id,
          name: "Billing",
          client: nil,
          milestones: []
        )
      )

    task =
      Generator.generate(
        Generator.task(
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.member.id,
          title: "Send the invoices",
          recurrence: %{every: 2, unit: :week, until: ~D[2027-01-31]},
          inserted_at: ~U[2026-01-02 12:00:00.000000Z]
        )
      )

    once =
      Generator.generate(
        Generator.task(
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          title: "Buy a stamp",
          recurrence: nil,
          inserted_at: ~U[2026-01-01 12:00:00.000000Z]
        )
      )

    %{world: world, project: project, bare: bare, task: task, once: once}
  end

  defp stored(%Project{id: id}), do: Ash.get!(Project, id, authorize?: false)
  defp stored(%Task{id: id}), do: Ash.get!(Task, id, authorize?: false)

  defp field(html, id, name), do: Enum.find(panel(html, id).fields, &(&1.name == name))

  describe "a project's client and milestones" do
    setup %{conn: conn, world: world} do
      {:ok, view, html} = conn |> log_in(world.admin) |> live("/projects")
      %{view: view, html: html}
    end

    test "are shown on one line each: the client with its address, the milestones one after the other",
         %{html: html, project: project, bare: bare} do
      assert text(html, cell("project", project.id, "client")) ==
               "Name: Nordwind GmbH, Email: office@nordwind.test, Key account?: Yes, Address: Street: Kai 1, City: Kiel, Postcode: 24103"

      assert text(html, cell("project", project.id, "milestones")) ==
               "Title: Kick-off, Due on: 2026-11-02, Reached?: Yes; Title: Handover, Reached?: No"

      assert text(html, cell("project", bare.id, "client")) == ""
      assert text(html, cell("project", bare.id, "milestones")) == ""
      refute html =~ "private"
    end

    test "are neither sorted nor filtered by", %{html: html} do
      for field <- ~w(client milestones) do
        assert attribute(html, "#project-head-#{field}", "data-sort") == []
        assert attribute(html, "#project-filter-#{field}", "data-filter") == []
      end
    end

    test "the client is edited in the side panel, field by field, and saved through `update`",
         %{view: view, project: project} do
      html = edit(view, "project", project.id, "client")

      assert %{heading: "Client: Website", submit: "Save"} = panel(html, "project")

      assert Enum.map(panel(html, "project").fields, &{&1.name, &1.control, &1.value}) == [
               {"client", "group", true},
               {"client.name", "textarea", "Nordwind GmbH"},
               {"client.email", "textarea", "office@nordwind.test"},
               {"client.key_account?", "checkbox", "true"},
               {"client.address", "group", true},
               {"client.address.street", "textarea", "Kai 1"},
               {"client.address.city", "textarea", "Kiel"},
               {"client.address.postcode", "textarea", "24103"}
             ]

      html =
        run_panel(view, "project",
          client: %{
            "name" => "Nordwind AG",
            "key_account?" => "false",
            "address" => %{"city" => "Lübeck", "postcode" => "23552"}
          }
        )

      refute panel(html, "project")

      assert text(html, cell("project", project.id, "client")) ==
               "Name: Nordwind AG, Email: office@nordwind.test, Key account?: No, Address: Street: Kai 1, City: Lübeck, Postcode: 23552"

      assert %Client{
               name: "Nordwind AG",
               key_account?: false,
               credit_note: "private",
               address: %Address{street: "Kai 1", city: "Lübeck"}
             } = stored(project).client
    end

    test "what the embedded resources refuse is shown at their fields, and nothing is saved",
         %{view: view, project: project} do
      edit(view, "project", project.id, "client")

      html =
        run_panel(view, "project",
          client: %{"name" => "N", "email" => "nobody", "address" => %{"postcode" => "abc"}}
        )

      assert field(html, "project", "client.name").errors ==
               ["length must be greater than or equal to 2"]

      assert field(html, "project", "client.email").errors == ["must be an email address"]

      assert field(html, "project", "client.address.postcode").errors == [
               "must match the pattern ~r/^\\d{5}$/"
             ]

      assert field(html, "project", "client.address.city").value == "Kiel"
      assert stored(project).client.name == "Nordwind GmbH"
    end

    test "a project without a client gets one, with its fields filled in", %{
      view: view,
      bare: bare
    } do
      html = edit(view, "project", bare.id, "client")
      assert Enum.map(panel(html, "project").fields, &{&1.name, &1.value}) == [{"client", false}]

      html = add_group(view, "project", ["client"])
      assert field(html, "project", "client.address").value == false
      assert field(html, "project", "client.key_account?").value == "false"

      html = run_panel(view, "project", client: %{"name" => "Lumen"})

      assert text(html, cell("project", bare.id, "client")) == "Name: Lumen, Key account?: No"
      assert %Client{name: "Lumen", address: nil} = stored(bare).client
    end

    test "the milestones are edited as a list: Ash updates the one that stays, creates the new one and drops the one taken away",
         %{view: view, project: project} do
      html = edit(view, "project", project.id, "milestones")

      assert Enum.map(panel(html, "project").fields, &{&1.name, &1.control, &1.value}) == [
               {"milestones", "groups", 2},
               {"milestones.0.title", "textarea", "Kick-off"},
               {"milestones.0.due_on", "date", "2026-11-02"},
               {"milestones.0.reached?", "checkbox", "true"},
               {"milestones.1.title", "textarea", "Handover"},
               {"milestones.1.due_on", "date", ""},
               {"milestones.1.reached?", "checkbox", "false"}
             ]

      remove_group(view, "project", ["milestones", "1"])
      add_group(view, "project", ["milestones"])

      html =
        run_panel(view, "project",
          milestones: %{
            "0" => %{"title" => "Kick-off meeting"},
            "1" => %{"title" => "Launch", "due_on" => "2027-03-01"}
          }
        )

      assert text(html, cell("project", project.id, "milestones")) ==
               "Title: Kick-off meeting, Due on: 2026-11-02, Reached?: Yes; Title: Launch, Due on: 2027-03-01, Reached?: No"

      assert [
               %Milestone{id: @kickoff, title: "Kick-off meeting"},
               %Milestone{title: "Launch"} = launch
             ] =
               stored(project).milestones

      refute launch.id in [@kickoff, @handover]
    end

    test "a milestone that is refused has the message at its field", %{
      view: view,
      project: project
    } do
      edit(view, "project", project.id, "milestones")

      html = run_panel(view, "project", milestones: %{"1" => %{"title" => "H"}})

      assert field(html, "project", "milestones.1.title").errors ==
               ["length must be greater than or equal to 3"]

      assert Enum.map(stored(project).milestones, & &1.title) == ["Kick-off", "Handover"]
    end

    test "a new project is created with its client, from the groups of the create panel",
         %{view: view} do
      html = open_create(view, "project")

      assert {"client", "group", false} in Enum.map(
               panel(html, "project").fields,
               &{&1.name, &1.control, &1.value}
             )

      assert {"milestones", "groups", 0} in Enum.map(
               panel(html, "project").fields,
               &{&1.name, &1.control, &1.value}
             )

      add_group(view, "project", ["client"])
      add_group(view, "project", ["client", "address"])
      add_group(view, "project", ["milestones"])

      html =
        run_panel(view, "project",
          name: "Portal",
          client: %{"name" => "Lumen", "address" => %{"street" => "Ring 3", "city" => "Bonn"}},
          milestones: %{"0" => %{"title" => "Start"}}
        )

      refute panel(html, "project")

      assert [created] =
               Project |> Ash.read!(authorize?: false) |> Enum.filter(&(&1.name == "Portal"))

      assert %Client{name: "Lumen", address: %Address{street: "Ring 3", city: "Bonn"}} =
               created.client

      assert [%Milestone{title: "Start", reached?: false}] = created.milestones

      assert text(html, cell("project", created.id, "client")) ==
               "Name: Lumen, Key account?: No, Address: Street: Ring 3, City: Bonn"
    end
  end

  describe "who edits a project's client" do
    test "a viewer is offered no editor, and an event of theirs opens nothing",
         %{conn: conn, world: world, project: project} do
      {:ok, view, html} = conn |> log_in(world.viewer) |> live("/projects")

      assert editors(html, "project") == []
      refute panel(edit(view, "project", project.id, "client"), "project")
    end

    test "a member edits it", %{conn: conn, world: world, project: project} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/projects")

      edit(view, "project", project.id, "client")
      html = run_panel(view, "project", client: %{"name" => "Nordwind KG"})

      refute panel(html, "project")
      assert stored(project).client.name == "Nordwind KG"
    end
  end

  describe "a task's recurrence" do
    setup %{conn: conn, world: world} do
      {:ok, view, html} = conn |> log_in(world.admin) |> live("/tasks")
      %{view: view, html: html}
    end

    test "is shown on one line, under the column's label", %{html: html, task: task, once: once} do
      assert "Repeats" in headers(html, "task")
      assert text(html, cell(task.id, "recurrence")) == "Every: 2, Unit: Week, Until: 2027-01-31"
      assert text(html, cell(once.id, "recurrence")) == ""
    end

    test "is edited in the side panel, with the control of each declared field", %{
      view: view,
      task: task
    } do
      html = edit(view, task.id, "recurrence")

      assert %{heading: "Repeats: Send the invoices", submit: "Save"} = panel(html)

      assert Enum.map(
               panel(html).fields,
               &{&1.name, &1.label, &1.control, &1.value, &1.required?}
             ) ==
               [
                 {"recurrence", "Repeats", "group", true, false},
                 {"recurrence.every", "Every", "number", "2", true},
                 {"recurrence.unit", "Unit", "select", "week", true},
                 {"recurrence.until", "Until", "date", "2027-01-31", false}
               ]

      html = run_panel(view, recurrence: %{"every" => "1", "unit" => "month", "until" => ""})

      refute panel(html)
      assert text(html, cell(task.id, "recurrence")) == "Every: 1, Unit: Month"
      assert stored(task).recurrence == %{every: 1, unit: :month}
    end

    test "what a field's constraints refuse is shown at that field", %{view: view, task: task} do
      edit(view, task.id, "recurrence")

      html = run_panel(view, recurrence: %{"every" => "0"})

      assert field(html, "task", "recurrence.every").errors ==
               ["must be greater than or equal to 1"]

      assert stored(task).recurrence.every == 2
    end

    test "is taken away, and added to a task that had none", %{view: view, task: task, once: once} do
      edit(view, task.id, "recurrence")
      remove_group(view, ["recurrence"])
      html = run_panel(view, %{})

      assert text(html, cell(task.id, "recurrence")) == ""
      assert stored(task).recurrence == nil

      edit(view, once.id, "recurrence")
      add_group(view, ["recurrence"])
      html = run_panel(view, recurrence: %{"every" => "3", "unit" => "day"})

      assert text(html, cell(once.id, "recurrence")) == "Every: 3, Unit: Day"
    end

    test "a member saves it on their own task and is refused on another's, in the panel",
         %{conn: conn, world: world, task: task, once: once} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      edit(view, task.id, "recurrence")
      html = run_panel(view, recurrence: %{"every" => "5"})
      refute panel(html)
      assert stored(task).recurrence.every == 5

      edit(view, once.id, "recurrence")
      add_group(view, ["recurrence"])
      html = run_panel(view, recurrence: %{"every" => "3", "unit" => "day"})

      assert panel(html).errors == ["You are not allowed to change this."]
      assert announcement(html) == "Repeats was not saved: You are not allowed to change this."
      assert stored(once).recurrence == nil
    end
  end

  describe "in German" do
    test "the fields of a value are called in German, in the cell and in the panel",
         %{conn: conn, world: world, task: task} do
      {:ok, view, html} = conn |> log_in(world.admin) |> in_locale("de") |> live("/tasks")

      assert "Wiederholung" in headers(html, "task")
      assert text(html, cell(task.id, "recurrence")) == "Alle: 2, Einheit: Woche, Bis: 2027-01-31"

      html = edit(view, task.id, "recurrence")

      assert %{heading: "Wiederholung: Send the invoices", submit: "Speichern"} = panel(html)

      assert Enum.map(panel(html).fields, & &1.label) == [
               "Wiederholung",
               "Alle",
               "Einheit",
               "Bis"
             ]

      assert attribute(html, "[id='task-panel-f-recurrence-remove']", "aria-label") ==
               ["Wiederholung entfernen"]
    end
  end
end
