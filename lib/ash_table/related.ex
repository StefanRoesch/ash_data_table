defmodule AshTable.Related do
  @moduledoc false
  # A table limited to the records related to one record ("the comments of
  # this task"), as a URL names it: the full view of a nested table. The
  # table's parameter `of` holds the record and the relationship:
  #
  #     ?comment[of][task][comments]=822827e2-…
  #     ?task[of][task_label][task][task_id]=…&task[of][task_label][task][label_id]=…
  #
  # that is `ID[of][PARENT][RELATIONSHIP]=KEY`: the short name of the parent's
  # resource, the name of its relationship, and the parent's primary key; the
  # key by attribute where it has several.
  #
  # What is named is only ever looked up, never made: the parent among the
  # resources the application knows, by its short name as text, and only one
  # whose table offers this person that relationship to this table's
  # resource; the key's values are cast to the types of the primary key.
  # Anything else is no limit at all, and the table shows itself as if
  # nothing had been asked.
  #
  # A parent's key in a URL proves nothing. The table reads the parent as
  # the person on every read (`AshTable.Query.read_related/4`), as a nested
  # table does.

  alias Ash.Resource.Info
  alias AshTable.Model
  alias AshTable.Model.Relationship
  alias AshTable.Resource.Relating
  alias AshTable.Routes

  @param "of"

  @typedoc """
  The limit a URL names: the relationship the table is reached through, the
  parent's primary key, and the limit as the parameter `of` holds it.
  """
  @type t :: %{via: Relationship.t(), key: map, param: map}

  @doc "The name of the parameter, among those of a table."
  def param, do: @param

  @doc """
  The limit that a table's parameters name, for the table of `resource` and
  the person `reader` says is asking. Nil when they name none, or one that
  is not to be had: see above.

  `endpoint` is the host's, which says whose application's resources are
  looked through.
  """
  @spec from_params(Ash.Resource.t(), term, keyword, module | nil) :: t | nil
  def from_params(resource, %{@param => %{} = named}, reader, endpoint) do
    with [{parent_name, %{} = relationships}] <- Map.to_list(named),
         [{relationship_name, key}] <- Map.to_list(relationships),
         %Relationship{} = via <-
           offered(resource, parent_name, relationship_name, reader, endpoint),
         {:ok, key} <- cast_key(via.source, key),
         {:ok, param} <- to_param(via, key) do
      %{via: via, key: key, param: param}
    else
      _ -> nil
    end
  end

  def from_params(_resource, _params, _reader, _endpoint), do: nil

  @doc """
  The limit as the parameter `of` holds it, for a table reached through
  `via` from the record with the primary key `key`.
  """
  @spec to_param(Relationship.t(), map) :: {:ok, map} | :error
  def to_param(%Relationship{} = via, key) when is_map(key) do
    with {:ok, value} <- key_param(via.source, key) do
      {:ok, %{name(via.source) => %{Atom.to_string(via.name) => value}}}
    end
  end

  @doc """
  Where the records of a nested table are shown in the full view: the page
  the router mounts the destination's table at, with the limit in the
  table's parameters. Nil when the router mounts no such page, and when that
  page could not tell which record is meant.
  """
  @spec path(module | nil, module | nil, Relationship.t(), map) :: String.t() | nil
  def path(router, endpoint, %Relationship{} = via, key) do
    with %{path: path, id: id} <- Routes.table(router, via.destination),
         {:ok, param} <- to_param(via, key),
         # the page has to find the parent again by the name it is given
         [_one] <- named(via.destination, name(via.source), via.name, endpoint) do
      path <> "?" <> Plug.Conn.Query.encode(%{id => %{@param => param}})
    else
      _ -> nil
    end
  end

  # The relationship of that name which the table of a resource of that
  # short name offers this person, to this table's resource. Looked up as
  # text, so that text from the outside is never turned into an atom.
  defp offered(resource, parent_name, relationship_name, reader, endpoint) do
    case named(resource, parent_name, relationship_name, endpoint) do
      [parent] ->
        model = parent |> Model.build() |> Model.for_actor(reader)

        with %Relationship{destination: ^resource} = via <-
               Model.relationship(model, relationship_name),
             do: via

      _none_or_several ->
        nil
    end
  end

  # The resources of that short name whose table has such a relationship to
  # this resource, and lets its rows expand at all.
  defp named(resource, parent_name, relationship_name, endpoint)
       when is_binary(parent_name) and
              (is_binary(relationship_name) or is_atom(relationship_name)) do
    relationship_name = to_string(relationship_name)

    for parent <- known(resource, endpoint),
        name(parent) == parent_name,
        Relating.table?(parent),
        model = Model.build(parent),
        model.max_depth > 0,
        match?(
          %Relationship{destination: ^resource},
          Model.relationship(model, relationship_name)
        ) do
      parent
    end
  end

  defp named(_resource, _parent_name, _relationship_name, _endpoint), do: []

  # The resources a parent is looked for among: those of the domains the
  # application lists (`config :my_app, ash_domains: […]`), and those of the
  # table's own domain.
  defp known(resource, endpoint) do
    [Info.domain(resource) | domains(endpoint)]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.flat_map(&Ash.Domain.Info.resources/1)
    |> Enum.uniq()
  end

  defp domains(nil), do: []

  defp domains(endpoint) do
    case endpoint.config(:otp_app) do
      nil -> []
      otp_app -> Ash.Info.domains(otp_app)
    end
  end

  # What a resource is called in a URL: its short name.
  defp name(resource), do: resource |> Info.short_name() |> Atom.to_string()

  # The primary key from a URL: the one value of a key of one attribute, the
  # values by attribute of a key of several, each cast to its attribute's type.
  defp cast_key(parent, key) do
    case {Info.primary_key(parent), key} do
      {[name], value} when is_binary(value) ->
        cast_key(parent, [name], %{Atom.to_string(name) => value})

      {[_, _ | _] = names, %{} = values} when map_size(values) == length(names) ->
        cast_key(parent, names, values)

      _other ->
        :error
    end
  end

  defp cast_key(parent, names, values) do
    Enum.reduce_while(names, {:ok, %{}}, fn name, {:ok, key} ->
      attribute = Info.attribute(parent, name)

      with value when is_binary(value) <- values[Atom.to_string(name)],
           {:ok, cast} when not is_nil(cast) <-
             Ash.Type.cast_input(attribute.type, value, attribute.constraints) do
        {:cont, {:ok, Map.put(key, name, cast)}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  # And the other way: a key as text.
  defp key_param(parent, key) do
    case Info.primary_key(parent) do
      [name] ->
        text(key[name])

      [_, _ | _] = names ->
        Enum.reduce_while(names, {:ok, %{}}, fn name, {:ok, param} ->
          case text(key[name]) do
            {:ok, text} -> {:cont, {:ok, Map.put(param, Atom.to_string(name), text)}}
            :error -> {:halt, :error}
          end
        end)

      [] ->
        :error
    end
  end

  defp text(nil), do: :error

  defp text(value) do
    if String.Chars.impl_for(value), do: {:ok, to_string(value)}, else: :error
  end
end
