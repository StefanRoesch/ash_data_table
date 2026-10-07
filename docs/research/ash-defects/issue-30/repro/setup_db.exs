# Creates ONLY the database ashbug_30 and its three tables.
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, c} = Postgrex.start_link(hostname: "127.0.0.1", port: 5477, username: "ash_table", password: "ash_table", database: "postgres")
%{rows: rows} = Postgrex.query!(c, "SELECT 1 FROM pg_database WHERE datname = 'ashbug_30'", [])
if rows == [], do: Postgrex.query!(c, "CREATE DATABASE ashbug_30", [])
{:ok, d} = Postgrex.start_link(hostname: "127.0.0.1", port: 5477, username: "ash_table", password: "ash_table", database: "ashbug_30")
for sql <- [
  "DROP TABLE IF EXISTS tasks, links, orgs",
  "CREATE TABLE orgs (id uuid PRIMARY KEY, name text)",
  "CREATE TABLE tasks (id uuid PRIMARY KEY, title text, hours bigint, secret bigint, code text, owner_id uuid, org_id uuid)",
  "CREATE TABLE links (org_id uuid NOT NULL, task_id uuid NOT NULL, PRIMARY KEY (org_id, task_id))"
], do: Postgrex.query!(d, sql, [])
IO.puts("database ashbug_30 ready")
