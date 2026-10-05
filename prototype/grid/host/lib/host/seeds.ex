defmodule Host.Seeds do
  @moduledoc """
  THROWAWAY PROTOTYPE (#11). Deterministic in-memory seed, run at boot.

  600 tasks (so a 500-row page has a next page). The first 60 tasks get 25
  comments each (a full nested page, for the "many nested tables open"
  measurement); the others get 3.
  """
  @tasks 600
  @people ~w(Ada Grace Linus Barbara Edsger Margaret Dennis Radia)
  @teams ~w(core web data infra)
  @words ~w(migrate audit index cache queue report export import sync render login billing search invoice)

  def run do
    tasks = for i <- 1..@tasks, do: task(i)

    %{status: :success} =
      Ash.bulk_create(tasks, Host.Work.Task, :seed, return_errors?: true, stop_on_error?: true)

    comments =
      for task_id <- 1..@tasks,
          n <- 1..if(task_id <= 60, do: 25, else: 3) do
        id = task_id * 100 + n

        %{
          id: id,
          task_id: task_id,
          body: "Comment #{n} on task #{task_id}: #{pick(@words, id)} needs another look",
          author: pick(@people, id),
          rating: rem(id, 5) + 1,
          resolved: rem(id, 3) == 0,
          posted_on: Date.add(~D[2026-01-01], rem(id, 270))
        }
      end

    %{status: :success} =
      Ash.bulk_create(comments, Host.Work.Comment, :seed,
        return_errors?: true,
        stop_on_error?: true
      )

    :ok
  end

  defp task(i) do
    progress = rem(i * 7, 101)

    %{
      id: i,
      title: "#{String.capitalize(pick(@words, i))} the #{pick(@words, i * 3 + 1)} #{i}",
      status: pick([:todo, :in_progress, :review, :done, :blocked], i),
      priority: pick([:low, :medium, :high, :urgent], i * 5),
      progress: progress,
      done: progress == 100,
      due_on: Date.add(~D[2026-10-05], rem(i * 3, 90)),
      price: Decimal.new("#{rem(i * 37, 900) + 10}.#{rem(i, 10)}0"),
      assignee: pick(@people, i * 3),
      starts_at: DateTime.add(~U[2026-10-05 08:00:00Z], rem(i * 45, 60 * 24 * 30), :minute),
      description:
        "Longer text for task #{i}. " <>
          String.duplicate("#{pick(@words, i)} #{pick(@words, i + 4)} ", rem(i, 4) + 2),
      estimate_hours: rem(i * 11, 40) + 1,
      spent_hours: rem(i * 5, 40),
      billable: rem(i, 4) != 0,
      budget: Decimal.new("#{rem(i * 113, 5000) + 100}.00"),
      team: pick(@teams, i),
      sprint: rem(i, 12) + 1,
      story_points: pick([1, 2, 3, 5, 8, 13], i),
      reviewed: rem(i, 5) == 0,
      reviewer: pick(@people, i * 7 + 2),
      started_on: Date.add(~D[2026-09-01], rem(i * 2, 30)),
      finished_on: if(progress == 100, do: Date.add(~D[2026-10-01], rem(i, 20))),
      last_touched_at: DateTime.add(~U[2026-10-01 12:00:00Z], rem(i * 17, 5000), :minute),
      notes: "Note #{i}: #{pick(@words, i * 2)}",
      label: pick(~w(bug feature chore spike), i),
      component: pick(~w(api ui db jobs auth), i * 3),
      severity: rem(i, 5) + 1,
      external_ref: "EXT-#{10_000 + i}",
      archived: rem(i, 17) == 0,
      score: Decimal.new("#{rem(i * 13, 100)}.5")
    }
  end

  defp pick(list, i), do: Enum.at(list, rem(i, length(list)))
end
