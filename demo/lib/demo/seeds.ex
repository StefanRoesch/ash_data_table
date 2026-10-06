defmodule Demo.Seeds do
  @moduledoc """
  The demo's seed data. `run/1` empties the database and fills it again, so it
  can be repeated at will and always gives the same records with the same ids
  (dates are relative to today).

  Profiles:

    * `:standard` - two organizations, the fixed actors plus colleagues,
      10 projects, 400 tasks, about 500 comments, 36 specimens
    * `:large` - the same with 50,000 tasks and about 60,000 comments

  Nothing here goes through an action: records are written straight to the
  data layer, so no actor and no policy is involved.
  """
  import Demo.Generator

  alias Demo.Actors

  @profiles %{
    standard: %{acme: 320, globex: 80},
    large: %{acme: 45_000, globex: 5_000}
  }

  @doc "The profile named by the `SEED` environment variable, `:standard` by default."
  def profile_from_env do
    case System.get_env("SEED", "standard") do
      "large" ->
        :large

      "standard" ->
        :standard

      other ->
        raise ArgumentError, "unknown SEED profile #{inspect(other)}; use standard or large"
    end
  end

  def run(profile \\ :standard) when is_map_key(@profiles, profile) do
    counts = Map.fetch!(@profiles, profile)
    started = System.monotonic_time(:millisecond)

    reset!()
    reseed()

    acme = seed_organization(:acme, [:admin, :member, :viewer], 6, 6, counts.acme)
    globex = seed_organization(:globex, [:outsider], 4, 4, counts.globex)
    specimens = generate_many(specimen(), 36)

    summary = %{
      profile: profile,
      organizations: 2,
      users: acme.users + globex.users,
      projects: acme.projects + globex.projects,
      labels: acme.labels + globex.labels,
      tasks: acme.tasks + globex.tasks,
      comments: acme.comments + globex.comments,
      task_labels: acme.task_labels + globex.task_labels,
      specimens: length(specimens),
      milliseconds: System.monotonic_time(:millisecond) - started
    }

    IO.puts("Seeded: " <> inspect(summary))
    summary
  end

  @doc "Empties every table of the demo."
  def reset! do
    Demo.Repo.query!("TRUNCATE organizations, specimens CASCADE")
    :ok
  end

  defp seed_organization(key, actor_keys, colleagues, project_count, task_count) do
    org = generate(organization(Map.to_list(Actors.organization(key))))

    actors =
      for actor_key <- actor_keys do
        actor = Actors.user(actor_key)

        generate(
          user(
            id: actor.id,
            name: actor.name,
            email: Ash.CiString.new(actor.email),
            role: actor.role,
            organization_id: org.id
          )
        )
      end

    others =
      insert_many!(
        user(organization_id: org.id, role: pick([:member, :member, :member, :viewer, :admin])),
        colleagues
      )

    user_ids = Enum.map(actors ++ others, & &1.id)

    projects =
      project_names()
      |> Enum.take(project_count)
      |> Enum.map(&generate(project(organization_id: org.id, name: &1)))

    labels =
      label_names()
      |> Enum.zip(colours())
      |> Enum.map(fn {name, colour} ->
        generate(label(organization_id: org.id, name: name, colour: colour))
      end)

    tasks =
      insert_many!(
        task(
          organization_id: org.id,
          # Drawn in this order for every task (see Demo.Generator).
          # About one task in six has no assignee.
          assignee_id: pick([nil, nil | user_ids]),
          reporter_id: pick(user_ids),
          project_id: pick(Enum.map(projects, & &1.id))
        ),
        task_count
      )

    comments =
      tasks
      |> comment_on_any(user_ids, organization_id: org.id)
      |> insert_many!(round(task_count * 1.2))

    %{
      users: length(user_ids),
      projects: length(projects),
      labels: length(labels),
      tasks: length(tasks),
      comments: length(comments),
      task_labels: label_tasks!(tasks, labels)
    }
  end
end
