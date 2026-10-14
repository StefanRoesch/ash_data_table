defmodule AshDataTable.Resource.Exposing do
  @moduledoc false
  # What an aggregate or a calculation column shows of fields that a field
  # policy protects, for the verifier that warns about it.
  #
  # Ash's rule (its policies guide, "References to related data & fields"):
  # an aggregate applies the read policy of the related resource and not its
  # field policies, and a calculation applies no policy at all to what it
  # references. Such a field is protected by a field policy of its own, on
  # the resource that declares it. The table shows these fields to people as
  # columns to read, sort and filter by, so it says when one is not.
  #
  # Only what the declarations say is looked at: the field and the `filter`
  # of an aggregate, and the references of a calculation's expression. A
  # calculation computed in Elixir cannot be looked into.

  alias Ash.Resource.Info

  @typedoc """
  A protected field a column shows: on `resource`, reached `through` the
  aggregate's field, its filter, or a path of relationships from a
  calculation (empty for a field of the resource itself).
  """
  @type exposure :: %{
          resource: Ash.Resource.t(),
          field: atom,
          through: :field | :filter | [atom]
        }

  @doc """
  The protected fields that the aggregate or the calculation shows, on
  `resource`, which declares it. Empty when it shows none, and when the
  resource protects the field itself with a field policy that names it.
  """
  @spec exposures(Ash.Resource.t(), struct) :: [exposure]
  def exposures(resource, %{name: name} = field) do
    if protected?(resource, name), do: [], else: field |> reached(resource) |> Enum.uniq()
  end

  defp reached(%Ash.Resource.Aggregate{} = aggregate, resource) do
    destination = Info.related(resource, aggregate.relationship_path)

    of_field =
      if aggregate.field && protected?(destination, aggregate.field),
        do: [%{resource: destination, field: aggregate.field, through: :field}],
        else: []

    of_filter =
      for {[], name} <- references(destination, aggregate.filter),
          protected?(destination, name),
          do: %{resource: destination, field: name, through: :filter}

    of_field ++ of_filter
  end

  defp reached(
         %Ash.Resource.Calculation{
           name: name,
           calculation: {Ash.Resource.Calculation.Expression, opts}
         },
         resource
       ) do
    for {path, field} <- references(resource, opts[:expr]),
        {path, field} != {[], name},
        related = Info.related(resource, path),
        not is_nil(related),
        protected?(related, field),
        do: %{resource: related, field: field, through: path}
  end

  defp reached(_computed_in_elixir, _resource), do: []

  @doc """
  Whether a field policy of the resource protects the field: one that names
  it and does more than let everybody see it. The policy that
  `field_policy :*` with `authorize_if always()` makes for every other
  field protects nothing.
  """
  @spec protected?(Ash.Resource.t(), atom) :: boolean
  def protected?(resource, field) do
    Ash.Policy.Authorizer in Info.authorizers(resource) and
      resource
      |> Ash.Policy.Info.field_policies()
      |> Enum.any?(&(field in List.wrap(&1.fields) and not trivial?(&1)))
  end

  defp trivial?(policy) do
    Enum.all?(List.wrap(policy.condition), &always?/1) and
      Enum.all?(policy.policies, fn check ->
        check.type == :authorize_if and always?({check.check_module, check.check_opts})
      end)
  end

  defp always?({Ash.Policy.Check.Static, opts}), do: opts[:result] == true
  defp always?(_check), do: false

  @doc """
  The fields an expression of `resource` references, each with the path of
  relationships it is reached through: empty for a field of the resource
  itself. Empty for an expression that cannot be read.
  """
  @spec references(Ash.Resource.t(), term) :: [{[atom], atom}]
  def references(_resource, nothing) when nothing in [nil, []], do: []

  def references(resource, expression) do
    with {:ok, expression} <-
           Ash.Filter.hydrate_refs(expression, %{resource: resource, public?: false}) do
      for %{relationship_path: path, attribute: attribute} <- Ash.Filter.list_refs(expression),
          name = name(attribute),
          do: {path, name}
    else
      _unreadable -> []
    end
  end

  defp name(%{name: name}) when is_atom(name), do: name
  defp name(name) when is_atom(name), do: name
  defp name(_other), do: nil
end
