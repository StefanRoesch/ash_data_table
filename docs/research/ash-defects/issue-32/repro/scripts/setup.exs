defmodule Setup do
  # id, name, visible
  # id, name, visible, manager_id
  @users [{1, "Alice", true, 2}, {2, "Bob", false, 3}, {3, "Carol", true, 1}, {4, "Dave", false, nil}]
  # id, title, assignee_id
  @tasks [{1, "t1", 1}, {2, "t2", 2}, {3, "t3", 3}, {4, "t4", 4}, {5, "t5", nil}]
  # id, label, visible, task_id
  @badges [{1, "gold", true, 1}, {2, "HIDDEN-silver", false, 2}, {3, "bronze", true, 3}, {4, "HIDDEN-iron", false, 4}]
  # id, body, visible, task_id
  @comments [{1, "b-pub1", true, 1}, {2, "a-HIDDEN1", false, 1}, {3, "a-HIDDEN2", false, 2}, {4, "c-pub3", true, 3},
             {5, "a-HIDDEN4", false, 4}, {6, "z-pub4", true, 4}]

  def pg! do
    cfg = V32.Repo.config()
    "ashbug_32" = cfg[:database]
    case Ecto.Adapters.Postgres.storage_up(cfg) do
      :ok -> IO.puts("created database ashbug_32")
      {:error, :already_up} -> :ok
    end
    {:ok, _} = V32.Repo.start_link()
    for sql <- [
          "DROP TABLE IF EXISTS comments, badges, seals, tasks, users",
          "CREATE TABLE users (id bigint PRIMARY KEY, name text, visible boolean DEFAULT true, manager_id bigint)",
          "CREATE TABLE tasks (id bigint PRIMARY KEY, title text, assignee_id bigint REFERENCES users(id))",
          "CREATE TABLE badges (id bigint PRIMARY KEY, label text, visible boolean DEFAULT true, task_id bigint REFERENCES tasks(id))",
          "CREATE TABLE seals (id bigint PRIMARY KEY, label text, visible boolean DEFAULT true, task_id bigint UNIQUE REFERENCES tasks(id))",
          "CREATE TABLE comments (id bigint PRIMARY KEY, body text, visible boolean DEFAULT true, task_id bigint REFERENCES tasks(id))"
        ], do: V32.Repo.query!(sql)
  end

  def seed!(ns) do
    a = %{role: :admin}
    for {id, n, v, m} <- @users, do: Ash.create!(Module.concat(ns, User), %{id: id, name: n, visible: v, manager_id: m}, actor: a)
    for {id, t, u} <- @tasks, do: Ash.create!(Module.concat(ns, Task), %{id: id, title: t, assignee_id: u}, actor: a)
    for {id, l, v, t} <- @badges, do: Ash.create!(Module.concat(ns, Badge), %{id: id, label: l, visible: v, task_id: t}, actor: a)
    for {id, l, v, t} <- @badges, do: Ash.create!(Module.concat(ns, Seal), %{id: id, label: l, visible: v, task_id: t}, actor: a)
    for {id, b, v, t} <- @comments, do: Ash.create!(Module.concat(ns, Comment), %{id: id, body: b, visible: v, task_id: t}, actor: a)
    :ok
  end
end
