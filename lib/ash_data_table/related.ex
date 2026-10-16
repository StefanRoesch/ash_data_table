defmodule AshDataTable.Related do
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
  # A resource has several tables, and each offers relationships of its own:
  # the parent is the table that offers the relationship. A named table of
  # the parent is named by the resource's short name, `_` and the table's
  # name (`comment[of][task_board][comments]=…`), and the relationship has to
  # be one that nests this very table: a page of a named table is the full
  # view of the nested tables that show that named table, and of no other.
  #
  # What is named is only ever looked up, never made: the parent among the
  # resources the application knows, by its short name as text, and only one
  # whose table offers this person that relationship to this table's
  # resource; the key's values are cast to the types of the primary key.
  # Anything else is no limit at all, and the table shows itself as if
  # nothing had been asked.
  #
  # A parent's key in a URL proves nothing. The table reads the parent as
  # the person on every read (`AshDataTable.Query.read_related/4`), as a nested
  # table does, through the read action of the parent's table as it runs
  # without arguments. So the table of a parent whose read action requires
  # one has no full view of its nested tables.

  alias Ash.Resource.Info
  alias AshDataTable.Model
  alias AshDataTable.Model.Relationship
  alias AshDataTable.Resource.Relating
  alias AshDataTable.Routes

  @param "of"

  @typedoc """
  The limit a URL names: the relationship the table is reached through, the
  parent's primary key, and the limit as the parameter `of` holds it.
  """
  @type t :: %{via: Relationship.t(), key: map, param: map}

  @doc "The name of the parameter, among those of a table."
  def param, do: @param

  @doc """
  The limit that a table's parameters name, for the table `table` of
  `resource` (`:default` for its default table) and the person `reader`
  says is asking. Nil when they name none, or one that is not to be had:
  see above.

  `endpoint` is the host's, which says whose application's resources are
  looked through.
  """
  @spec from_params(Ash.Resource.t(), atom, term, keyword, module | nil) :: t | nil
  def from_params(resource, table, %{@param => %{} = named}, reader, endpoint) do
    with [{parent_name, %{} = relationships}] <- Map.to_list(named),
         [{relationship_name, key}] <- Map.to_list(relationships),
         %Relationship{} = via <-
           offered({resource, table}, parent_name, relationship_name, reader, endpoint),
         {:ok, key} <- cast_key(via.source, key),
         {:ok, param} <- to_param(via, key) do
      %{via: via, key: key, param: param}
    else
      _ -> nil
    end
  end

  def from_params(_resource, _table, _params, _reader, _endpoint), do: nil

  @doc """
  The limit as the parameter `of` holds it, for a table reached through
  `via` from the record with the primary key `key`.
  """
  @spec to_param(Relationship.t(), map) :: {:ok, map} | :error
  def to_param(%Relationship{} = via, key) when is_map(key) do
    with {:ok, value} <- key_param(via.source, key) do
      {:ok, %{name(via.source, via.source_table) => %{Atom.to_string(via.name) => value}}}
    end
  end

  @doc """
  Where the records of a nested table are shown in the full view: the page
  the router mounts the nested table at (the table of the destination that
  the relationship nests, and no other of its tables), with the limit in
  the table's parameters. Nil when the router mounts no such page, and when
  that page could not tell which record is meant.

  `authorize?` is what the nested table was told about authorization, nil
  for nothing: the page is one that is mounted the same way
  (`AshDataTable.Routes.table/4`).
  """
  @spec path(module | nil, module | nil, Relationship.t(), map, boolean | nil) ::
          String.t() | nil
  def path(router, endpoint, %Relationship{} = via, key, authorize? \\ nil) do
    with %{path: path, id: id} <- Routes.table(router, via.destination, via.table, authorize?),
         {:ok, param} <- to_param(via, key),
         # the page has to find the parent again by the name it is given
         [_one] <-
           named(
             {via.destination, via.table},
             name(via.source, via.source_table),
             via.name,
             endpoint
           ) do
      path <> "?" <> Plug.Conn.Query.encode(%{id => %{@param => param}})
    else
      _ -> nil
    end
  end

  # The relationship of that name which the table of a resource of that
  # short name offers this person, to this table's resource. Looked up as
  # text, so that text from the outside is never turned into an atom.
  defp offered({resource, table} = shown, parent_name, relationship_name, reader, endpoint) do
    case named(shown, parent_name, relationship_name, endpoint) do
      [model] ->
        with %Relationship{destination: ^resource, table: ^table} = via <-
               model |> Model.for_actor(reader) |> Model.relationship(relationship_name),
             do: via

      _none_or_several ->
        nil
    end
  end

  # The tables of that name (a resource's short name, with `_` and the
  # table's name for a named table) that have such a relationship to this
  # table of this resource, and let their rows expand at all: their models,
  # as they are for everybody.
  #
  # Not one whose read action requires an argument: the full view reads the
  # parent through that action, and a URL that names a record says nothing
  # of what the parent's table was given when the record was found.
  defp named({resource, table}, parent_name, relationship_name, endpoint)
       when is_binary(parent_name) and
              (is_binary(relationship_name) or is_atom(relationship_name)) do
    relationship_name = to_string(relationship_name)

    for parent <- known(resource, endpoint),
        # a name can only be one that starts with the resource's own
        String.starts_with?(parent_name, name(parent, :default)),
        Relating.table?(parent),
        %{name: parent_table} <- AshDataTable.Resource.Info.tables(parent),
        name(parent, parent_table) == parent_name,
        model = Model.build(parent, table: parent_table),
        model.max_depth > 0,
        not needs_argument?(parent, model.read_action),
        match?(
          %Relationship{destination: ^resource, table: ^table},
          Model.relationship(model, relationship_name)
        ) do
      model
    end
  end

  defp named(_shown, _parent_name, _relationship_name, _endpoint), do: []

  defp needs_argument?(resource, read_action) do
    resource
    |> Info.action(read_action)
    |> Map.fetch!(:arguments)
    |> Enum.any?(&AshDataTable.Resource.Arguing.needed?/1)
  end

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
      otp_app -> Application.get_env(otp_app, :ash_domains, [])
    end
  end

  # What a table of a resource is called in a URL: the resource's short
  # name, and for a named table that, `_` and the table's name.
  defp name(resource, :default), do: resource |> Info.short_name() |> Atom.to_string()
  defp name(resource, table), do: name(resource, :default) <> "_" <> Atom.to_string(table)

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
