defmodule AshTable.Routes do
  @moduledoc false
  # Where the host's router mounts a table of a resource. `ash_table` puts
  # the resource, the name of its table and the table's id into the metadata
  # of its route, and `Phoenix.Router.routes/1` lists the routes with it.

  @typedoc "A mounted table: the path of its page and the table's id, which names its URL parameters."
  @type t :: %{path: String.t(), id: String.t()}

  @doc """
  The id a table has unless it is given one: the last part of the resource's
  module name, underscored (`"task"`), and for a named table that, `_` and
  the table's name (`"task_board"`). So the tables of one resource differ on
  a page and in a URL without anything written.

  From the module's name alone: the router asks, which does not look at the
  resource.
  """
  @spec default_id(module, atom) :: String.t()
  def default_id(resource, table \\ :default)

  def default_id(resource, table) when table in [nil, :default],
    do: resource |> Module.split() |> List.last() |> Macro.underscore()

  def default_id(resource, table) when is_atom(table),
    do: default_id(resource, :default) <> "_" <> Atom.to_string(table)

  @doc """
  The page the router mounts the table `table` of `resource` at (`:default`
  for its default table), for a link from a table that was told
  `authorize?` about authorization (nil when it was told nothing): of
  several, the first in the router's order that mounts that same table the
  same way. Nil when it mounts none, and without a router: a page of
  another table of the resource is not one of this table.

  A route whose path has a parameter (`/teams/:team/tasks`) is not one a
  link can be made to from elsewhere, and is passed over.
  """
  @spec table(module | nil, Ash.Resource.t(), atom, boolean | nil) :: t | nil
  def table(router, resource, table, authorize?)
  def table(nil, _resource, _table, _authorize?), do: nil

  def table(router, resource, table, authorize?) do
    table = table || :default

    Enum.find_value(Phoenix.Router.routes(router), fn
      %{path: path, metadata: %{ash_table: %{resource: ^resource, id: id} = mounted}} ->
        if static?(path) and Map.get(mounted, :table, :default) == table and
             unchecked?(Map.get(mounted, :authorize?)) == unchecked?(authorize?),
           do: %{path: path, id: id}

      _other ->
        nil
    end)
  end

  # Whether a table was told not to authorize: by its route, or where it is
  # placed. A link leads from one table to another only between tables that
  # are alike in this: a person is never sent from a page that authorizes
  # to one that was mounted without (`authorize?: false`), which shows
  # everybody's records, nor the other way, where they would be shown
  # other records than the table they came from showed.
  defp unchecked?(authorize?), do: authorize? == false

  defp static?(path), do: not String.contains?(path, [":", "*"])
end
