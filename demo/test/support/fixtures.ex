defmodule Demo.Fixtures do
  @moduledoc """
  The per-test data set and the way to act as one of the five actors.

      setup %{conn: conn} do
        world = world(tasks: 30)
        %{world: world, conn: log_in(conn, world.member)}
      end

  `use DemoWeb.ConnCase` and `use Demo.DataCase` import both functions.
  """

  alias Demo.Generator

  @doc """
  Builds an organization with its admin, member and viewer, a second
  organization with the outsider, projects, labels and tasks, through
  `Demo.Generator.world/1` (see there for the options, such as `tasks: 30`).

  The data is the same on every run: the random state is seeded first
  (`seed: 42` unless given). Ids and emails are the test's own rather than the
  fixed ones of `Demo.Actors` (the test cases call
  `Demo.Generator.distinct_ids/0`), so tests can run concurrently; pass
  `fixed?: true` to get the fixed ones.

  Returns a map with `:organization`, `:other_organization`, the actors
  `:admin`, `:member`, `:viewer`, `:outsider` and `:nobody` (`nil`), and
  `:projects`, `:labels`, `:tasks`, `:other_tasks`, `:comments`.
  """
  def world(opts \\ []) do
    {seed, opts} = Keyword.pop(opts, :seed, 42)
    Generator.reseed(seed)
    Generator.world(opts)
  end

  @doc """
  Makes `conn` act as `actor`: a `Demo.Tracker.User`, a user id, or `nil` for
  nobody. It sets the session exactly as the actor switcher does, so both the
  `DemoWeb.Actor` plug and its `on_mount` hook see the actor.
  """
  def log_in(conn, actor) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> DemoWeb.Actor.put_actor(actor)
  end

  @doc """
  Makes `conn` ask in `locale`, as the language switcher does: the tables of
  the pages it opens speak that language. `log_in/2` comes first, as it
  starts the session.
  """
  def in_locale(conn, locale) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> DemoWeb.Locale.put_locale(locale)
  end

  @doc "The options that make an Ash call run as `actor` in their organization."
  def as(actor), do: [actor: actor, tenant: Demo.Actors.tenant(actor)]
end
