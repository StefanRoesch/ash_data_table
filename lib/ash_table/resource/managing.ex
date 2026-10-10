defmodule AshTable.Resource.Managing do
  @moduledoc false
  # An argument of an action that manages a relationship: one that a
  # `change manage_relationship(:argument, :relationship, …)` of the action
  # hands to a relationship of the resource. Shared by the verifiers (which
  # report a mistake) and the table model (which builds on the answer).
  #
  # A table offers one thing for such an argument: choosing existing records
  # of the related resource, from that resource's own table. So only an
  # argument that holds keys is looked at here: the key of one related
  # record, or a list of such keys. An argument that holds a map, or a list
  # of maps, describes related records to create or to change; a table has no
  # form for that, and such an argument is what it was before.
  #
  # The change is found as Ash's interface extensions find it (ash_graphql,
  # ash_json_api, ash_admin, AshPhoenix): among the action's `changes`, the
  # first `Ash.Resource.Change.ManageRelationship` that names the argument.
  # What its `type` stands for is asked of Ash
  # (`Ash.Changeset.manage_relationship_opts/1`, as those extensions and
  # Ash's own verifier do).

  alias Ash.Resource.Info

  @typedoc """
  An argument that hands keys to a relationship:

    * `argument` - its name, and `relationship` the relationship it is
      handed to, as the resource declares it;
    * `key` - the attribute of the related resource whose value the argument
      holds: the one the change names (`value_is_key`), else the related
      resource's primary key;
    * `several?` - whether the argument holds a list of keys;
    * `allow_nil?` - whether the argument can be empty;
    * `relates?` - whether a key that names a record which is not related
      yet relates it (`on_lookup`): `:append` and `:append_and_remove` do;
    * `replaces?` - whether a related record that is left out is acted on
      (`on_missing`): unrelated, or destroyed. `:append_and_remove` and
      `:direct_control` do. What the argument is given is then everything
      the relationship is to hold;
    * `creates?` - whether a key that names no record makes one
      (`on_no_match: :create`): `:direct_control` and `:create` do.
  """
  @type t :: %{
          argument: atom,
          relationship: struct,
          key: atom,
          several?: boolean,
          allow_nil?: boolean,
          relates?: boolean,
          replaces?: boolean,
          creates?: boolean
        }

  @typedoc """
  Why an argument that a change hands to a relationship holds no keys a
  table could choose records for:

    * `:no_key` - the related resource has no one attribute to name a
      record by: a primary key of several attributes, or none, and the
      change names no `value_is_key`;
    * `{:not_a_key, type, key, key_type}` - the argument is not of the
      key's type, nor a list of it. A map, or a list of maps, among them.
  """
  @type not_keys :: :no_key | {:not_a_key, term, atom, term}

  @doc """
  What the argument of that name hands to a relationship, where a change of
  the action does so and the argument holds keys. `:none` where no change
  hands it to a relationship of the resource, and `{:error, reason}` where
  one does and the argument holds no keys.
  """
  @spec managed(Ash.Resource.t() | Spark.Dsl.t(), struct, atom) ::
          {:ok, t} | :none | {:error, not_keys}
  def managed(resource, action, name) when is_atom(name) do
    with %{} = argument <- Enum.find(Map.get(action, :arguments) || [], &(&1.name == name)),
         {relationship, opts} <- change(resource, action, name) do
      keys(argument, relationship, opts)
    else
      _no_argument_or_no_change -> :none
    end
  end

  @doc """
  The public arguments of the action that hand keys to the relationship of
  that name, in the action's order.
  """
  @spec into(Ash.Resource.t() | Spark.Dsl.t(), struct, atom) :: [t]
  def into(resource, action, relationship) do
    for %{public?: true, name: name} <- Map.get(action, :arguments) || [],
        {:ok, %{relationship: %{name: ^relationship}} = managed} <-
          [managed(resource, action, name)],
        do: managed
  end

  @doc """
  The public arguments of the action that a change hands to the relationship
  of that name, whatever they hold: each with what it hands over, or why it
  holds no keys.
  """
  @spec handed(Ash.Resource.t() | Spark.Dsl.t(), struct, atom) ::
          [{atom, {:ok, t} | {:error, not_keys}}]
  def handed(resource, action, relationship) do
    for %{public?: true, name: name} <- Map.get(action, :arguments) || [],
        {%{name: ^relationship}, _opts} <- [change(resource, action, name)],
        do: {name, managed(resource, action, name)}
  end

  # The relationship a change of the action hands the argument to, with the
  # options of the change as Ash reads them: those its `type` stands for,
  # and over them the ones the change says itself.
  defp change(resource, action, name) do
    found =
      Enum.find_value(Map.get(action, :changes) || [], fn
        %{change: {Ash.Resource.Change.ManageRelationship, opts}} ->
          if opts[:argument] == name, do: opts

        _another_change ->
          nil
      end)

    with opts when is_list(opts) <- found,
         %{} = relationship <- Info.relationship(resource, opts[:relationship]) do
      given = opts[:opts] || []

      defaults =
        case given[:type] do
          nil -> []
          type -> Ash.Changeset.manage_relationship_opts(type)
        end

      {relationship, Keyword.merge(defaults, given)}
    else
      _none -> nil
    end
  end

  defp keys(argument, relationship, opts) do
    with {:ok, key} <- key(relationship.destination, opts[:value_is_key]),
         {:ok, several?} <- holds(argument, key) do
      {:ok,
       %{
         argument: argument.name,
         relationship: relationship,
         key: key.name,
         several?: several?,
         allow_nil?: argument.allow_nil? != false,
         relates?: Keyword.get(opts, :on_lookup, :ignore) != :ignore,
         replaces?: Keyword.get(opts, :on_missing, :ignore) != :ignore,
         creates?: Ash.Changeset.ManagedRelationshipHelpers.could_create?(opts)
       }}
    end
  end

  # The attribute a record of the related resource is named by, as Ash
  # reads a value that is no map (`Ash.Changeset.manage_relationship/4`).
  defp key(destination, named) do
    name =
      named ||
        case compiled?(destination) && Info.primary_key(destination) do
          [name] -> name
          _several_or_none -> nil
        end

    case name && Info.attribute(destination, name) do
      %{} = attribute -> {:ok, attribute}
      _none -> {:error, :no_key}
    end
  end

  defp compiled?(destination), do: match?({:module, _module}, Code.ensure_compiled(destination))

  # Whether the argument holds one key, or a list of them: it is stored as
  # the key is.
  defp holds(%{type: {:array, type}} = argument, key) do
    if stored(type, (argument.constraints || [])[:items] || []) == stored(key),
      do: {:ok, true},
      else: {:error, {:not_a_key, argument.type, key.name, key.type}}
  end

  defp holds(%{type: type} = argument, key) do
    if stored(type, argument.constraints || []) == stored(key),
      do: {:ok, false},
      else: {:error, {:not_a_key, type, key.name, key.type}}
  end

  defp stored(%{type: type, constraints: constraints}), do: stored(type, constraints || [])
  defp stored(type, constraints), do: Ash.Type.storage_type(type, constraints)
end
