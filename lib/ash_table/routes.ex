defmodule AshTable.Routes do
  @moduledoc false
  # Where the host's router mounts the table of a resource. `ash_table` puts
  # the resource and the table's id into the metadata of its route, and
  # `Phoenix.Router.routes/1` lists the routes with it.

  @typedoc "A mounted table: the path of its page and the table's id, which names its URL parameters."
  @type t :: %{path: String.t(), id: String.t()}

  @doc """
  The page the router mounts the table of `resource` at, for a link from a
  table that was told `authorize?` about authorization (nil when it was
  told nothing): of several, the first in the router's order that is
  mounted the same way. Nil when it mounts none, and without a router.

  A route whose path has a parameter (`/teams/:team/tasks`) is not one a
  link can be made to from elsewhere, and is passed over.
  """
  @spec table(module | nil, Ash.Resource.t(), boolean | nil) :: t | nil
  def table(router, resource, authorize? \\ nil)
  def table(nil, _resource, _authorize?), do: nil

  def table(router, resource, authorize?) do
    Enum.find_value(Phoenix.Router.routes(router), fn
      %{path: path, metadata: %{ash_table: %{resource: ^resource, id: id} = mounted}} ->
        if static?(path) and unchecked?(Map.get(mounted, :authorize?)) == unchecked?(authorize?),
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
