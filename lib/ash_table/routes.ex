defmodule AshTable.Routes do
  @moduledoc false
  # Where the host's router mounts the table of a resource. `ash_table` puts
  # the resource and the table's id into the metadata of its route, and
  # `Phoenix.Router.routes/1` lists the routes with it.

  @typedoc "A mounted table: the path of its page and the table's id, which names its URL parameters."
  @type t :: %{path: String.t(), id: String.t()}

  @doc """
  The page the router mounts the table of `resource` at: of several, the
  first in the router's order. Nil when it mounts none, and without a
  router.

  A route whose path has a parameter (`/teams/:team/tasks`) is not one a
  link can be made to from elsewhere, and is passed over.
  """
  @spec table(module | nil, Ash.Resource.t()) :: t | nil
  def table(nil, _resource), do: nil

  def table(router, resource) do
    Enum.find_value(Phoenix.Router.routes(router), fn
      %{path: path, metadata: %{ash_table: %{resource: ^resource, id: id}}} ->
        if static?(path), do: %{path: path, id: id}

      _other ->
        nil
    end)
  end

  defp static?(path), do: not String.contains?(path, [":", "*"])
end
