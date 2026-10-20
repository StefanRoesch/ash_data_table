defmodule Demo.Records do
  @moduledoc """
  The records that several table tests make alike: tasks of the world's
  first organization, people, labels on a task, and the two pages of the
  picker's tests. A test file imports what it uses:

      import Demo.Records, only: [task: 2, task: 3, labels: 3]
  """

  # `live/2` gets the page through the endpoint: `get/2`, `@endpoint`
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest, only: [live: 2]

  alias Demo.Generator

  @endpoint DemoWeb.Endpoint
  @moment ~U[2026-01-01 12:00:00.000000Z]

  @doc """
  A task of the world's first organization, in its first project, reported
  by the admin, made at 2026-01-01 12:00, with `overrides` over that.
  """
  def task(world, title, overrides \\ []) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          title: title,
          inserted_at: @moment
        ] ++ overrides
      )
    )
  end

  @doc """
  The same in progress (40 %), assigned to nobody, without an internal note,
  each made a moment after the one before.
  """
  def task_in_progress(world, title, overrides \\ []) do
    task(
      world,
      title,
      [
        assignee_id: nil,
        status: :in_progress,
        progress: 40,
        internal_note: nil,
        inserted_at:
          DateTime.add(@moment, System.unique_integer([:positive, :monotonic]), :millisecond)
      ] ++ overrides
    )
  end

  @doc """
  A task of the world's first organization, in its first project, reported
  by the admin and assigned to nobody, every field given: called
  "Task DD" and made `day` days after 2026-01-01 12:00, so the highest
  day comes first.
  """
  def task_on_day(world, day, overrides) do
    task(
      world,
      "Task #{String.pad_leading("#{day}", 2, "0")}",
      [
        assignee_id: nil,
        description: nil,
        status: :in_progress,
        priority: :medium,
        progress: 40,
        estimate_hours: Decimal.new("12.5"),
        billable?: false,
        due_on: nil,
        completed_at: nil,
        external_ref: nil,
        internal_note: nil,
        inserted_at: DateTime.add(@moment, day, :day)
      ] ++ overrides
    )
  end

  @doc "A person of the world's first organization."
  def person(world, name, overrides \\ []) do
    Generator.generate(
      Generator.user([organization_id: world.organization.id, name: name] ++ overrides)
    )
  end

  @doc "A label of the world's first organization, put on `task`."
  def label(world, task, name) do
    label =
      Generator.generate(Generator.label(organization_id: world.organization.id, name: name))

    Generator.generate(
      Generator.task_label(
        organization_id: world.organization.id,
        task_id: task.id,
        label_id: label.id
      )
    )

    label
  end

  @doc "The labels named, each put on `task`."
  def labels(world, task, names), do: Enum.map(names, &label(world, task, &1))

  @doc """
  The page of the picker's tests: Ada and Grace, the task "Write the
  report" assigned to Ada, and `/tasks` as the admin sees it.
  """
  def assigned(conn) do
    world = Demo.Fixtures.world(tasks: 0, other_tasks: 0)
    ada = person(world, "Ada Lovelace")
    grace = person(world, "Grace Hopper")
    task = task_in_progress(world, "Write the report", assignee_id: ada.id)
    {:ok, view, _html} = conn |> Demo.Fixtures.log_in(world.admin) |> live("/tasks")

    %{world: world, ada: ada, grace: grace, task: task, view: view}
  end

  @doc """
  The page of the picker's tests of hand-made events: Ada, the task "Write
  the report" assigned to her, a project of the other organization
  (`foreign`), and `/tasks` as the admin sees it.
  """
  def foreign(conn) do
    world = Demo.Fixtures.world(tasks: 0, other_tasks: 0)

    foreign =
      Generator.generate(
        Generator.project(organization_id: world.other_organization.id, name: "Foreign")
      )

    ada = person(world, "Ada Lovelace")
    task = task_in_progress(world, "Write the report", assignee_id: ada.id)
    {:ok, view, _html} = conn |> Demo.Fixtures.log_in(world.admin) |> live("/tasks")

    %{world: world, ada: ada, task: task, foreign: foreign, view: view}
  end
end
