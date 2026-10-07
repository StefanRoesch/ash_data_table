# Creates ONLY the database ashbug_31 (if missing) and (re)creates its three tables, then seeds PG and ETS.
defmodule Setup do
  @users [{1, "Alice", true}, {2, "Bob", false}, {3, "Carol", true}, {4, "Dave", false}, {5, "Erin", false}]
  @people [{1, "Ann"}, {2, "Bea"}, {3, "Cy"}, {4, "Dan"}, {5, "Eve"}]
  # id, title, secret, assignee_id, owner_id
  @tasks [{1, "t1", "d", 4, 4}, {2, "t2", "a", 1, 1}, {3, "t3", "b", 2, 2}, {4, "t4", "c", 3, 3}, {5, "t5", nil, nil, nil}, {6, "t6", "e", 5, 5}]

  def pg! do
    cfg = Bug.Repo.config()
    "ashbug_31" = cfg[:database]
    case Ecto.Adapters.Postgres.storage_up(cfg) do
      :ok -> IO.puts("created database ashbug_31")
      {:error, :already_up} -> :ok
    end
    {:ok, _} = Bug.Repo.start_link()
    for sql <- [
          "DROP TABLE IF EXISTS tasks, users, people",
          "CREATE TABLE users (id bigint PRIMARY KEY, name text, visible boolean DEFAULT true)",
          "CREATE TABLE people (id bigint PRIMARY KEY, name text)",
          "CREATE TABLE tasks (id bigint PRIMARY KEY, title text, secret text, assignee_id bigint REFERENCES users(id), owner_id bigint REFERENCES people(id))"
        ],
        do: Bug.Repo.query!(sql)
  end

  def seed!(ns) do
    admin = %{role: :admin}
    for {id, name, vis} <- @users, do: Ash.create!(Module.concat(ns, User), %{id: id, name: name, visible: vis}, actor: admin)
    for {id, name} <- @people, do: Ash.create!(Module.concat(ns, Person), %{id: id, name: name}, actor: admin)
    for {id, t, s, a, o} <- @tasks,
        do: Ash.create!(Module.concat(ns, Task), %{id: id, title: t, secret: s, assignee_id: a, owner_id: o}, actor: admin)
    :ok
  end
end
