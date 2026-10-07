# Can a library detect, from Ash.Resource.Info / Ash.Policy.Info alone, an aggregate that exposes a field
# the destination resource protects by a field policy while the declaring resource does not protect the aggregate?
defmodule Detect do
  def field_policies_for(resource, field) do
    if Ash.Policy.Authorizer in Ash.Resource.Info.authorizers(resource) do
      resource |> Ash.Policy.Info.field_policies() |> Enum.filter(&(field in List.wrap(&1.fields)))
    else
      []
    end
  end

  # a policy that is `authorize_if always()` only (what `field_policy :* do authorize_if always() end` expands to) protects nothing
  def trivial?(fp) do
    always? = fn {mod, opts} -> mod == Ash.Policy.Check.Static and opts[:result] == true end
    Enum.all?(List.wrap(fp.condition), always?) and
      Enum.all?(fp.policies, &(&1.type == :authorize_if and always?.({&1.check_module, &1.check_opts})))
  end

  def protected?(resource, field), do: resource |> field_policies_for(field) |> Enum.any?(&(not trivial?(&1)))

  def filter_refs(nil, _), do: []
  def filter_refs(filter, dest) do
    {:ok, f} = Ash.Filter.parse(dest, filter)
    f |> Ash.Filter.list_refs() |> Enum.filter(&(&1.relationship_path == [])) |> Enum.map(fn %{attribute: %{name: n}} -> n; %{attribute: n} -> n end)
  end

  def report(resource) do
    for agg <- Ash.Resource.Info.aggregates(resource) do
      dest = Ash.Resource.Info.related(resource, agg.relationship_path)
      via_field = agg.field && protected?(dest, agg.field)
      via_filter = agg.filter |> filter_refs(dest) |> Enum.filter(&protected?(dest, &1))
      own = protected?(resource, agg.name)
      cond do
        (via_field || via_filter != []) and not own ->
          IO.puts("  WARN  #{inspect(resource)}.#{agg.name} (#{agg.kind}#{if agg.field, do: " of #{agg.field}"}) reaches protected #{inspect(dest)} field(s) #{inspect(Enum.uniq(List.wrap(via_field && agg.field) ++ via_filter))}#{if via_filter != [], do: " [in its filter]"}; no field policy for the aggregate on the declaring resource#{if Ash.Policy.Authorizer not in Ash.Resource.Info.authorizers(resource), do: " (it has no policy authorizer at all)"}")
        via_field || via_filter != [] -> IO.puts("  ok    #{inspect(resource)}.#{agg.name}: protected by its own field policy")
        true -> :ok
      end
    end
  end
end

IO.puts("field policies as Ash.Policy.Info reports them for Agg.Ets.Thing:")
for fp <- Ash.Policy.Info.field_policies(Agg.Ets.Thing), do: IO.puts("  fields=#{inspect(fp.fields)} policies=#{inspect(Enum.map(fp.policies, &{&1.type, &1.check_module, &1.check_opts |> Keyword.take([:result, :field, :value])}))}")
for r <- [Agg.Ets.ParentNA, Agg.Ets.ParentA, Agg.Ets.ParentFP] do
  IO.puts("#{inspect(r)}: authorizers=#{inspect(Ash.Resource.Info.authorizers(r))}")
  Detect.report(r)
end
