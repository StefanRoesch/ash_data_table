defmodule Spike.TableModel.Hybrid do
  @moduledoc """
  Proof of concept: `Ash.Resource.Info` for structure, plus two of the manifest generator's
  own building blocks for the two things that are expensive to rebuild:

    * `Ash.Info.Manifest.Generator.TypeResolver.resolve/2` (and `resolve_definition/1`) for type kinds
    * `Ash.Info.Manifest.Generator.OperatorResolver.resolve/3` for filter operators and functions

  `Ash.Info.Manifest.generate/1` is never called, so there is no reachability walk and
  nothing app-wide to cache except the operator catalogue.
  """
  alias Ash.Info.Manifest.Generator.{CapabilitiesBuilder, OperatorResolver, TypeResolver}
  alias Ash.Resource.Info

  @doc "Same options as `FromInfo.build/2`."
  def build(resource, opts \\ []) do
    read = opts[:read_action] || Info.primary_action!(resource, :read).name
    edit = opts[:edit] || [default: Info.primary_action!(resource, :update).name]
    read_action = Info.action(resource, read)
    pagination_type = if match?(%{offset?: false, keyset?: true}, read_action.pagination), do: :keyset, else: :offset
    names = opts[:columns] || default_columns(resource)
    context = %{resource: resource, data_layer: Ash.DataLayer.data_layer(resource), capabilities: capabilities(resource), pagination_type: pagination_type}

    %{
      resource: resource,
      domain: Info.domain(resource),
      primary_key: Info.primary_key(resource),
      read_action: read,
      pagination: pagination(read_action.pagination),
      columns:
        Enum.map(names, fn name ->
          action = Keyword.get(edit, name, edit[:default])
          column(context, Info.field(resource, name), Info.action(resource, action))
        end)
    }
  end

  # The catalogue depends on Ash's builtins, the data layer and `config :ash, :custom_expressions`,
  # not on any resource's fields, so it is built once per data layer and kept.
  defp capabilities(resource) do
    data_layer = Ash.DataLayer.data_layer(resource)

    case :persistent_term.get({__MODULE__, :capabilities, data_layer}, nil) do
      nil ->
        {capabilities, _sort} = CapabilitiesBuilder.build(resources_by_data_layer: %{data_layer => [resource]})
        :persistent_term.put({__MODULE__, :capabilities, data_layer}, capabilities)
        capabilities

      capabilities ->
        capabilities
    end
  end

  defp default_columns(resource) do
    Enum.map(Info.public_attributes(resource) ++ Info.public_calculations(resource) ++ Info.public_aggregates(resource), & &1.name)
  end

  defp column(context, field, action) do
    kind = field_kind(field)
    {type_module, constraints} = type_of(context.resource, field)
    resolved = TypeResolver.resolve(type_module, constraints)
    filterable? = Map.get(field, :filterable?, true)

    {operators, functions} =
      if filterable?, do: OperatorResolver.resolve(resolved, context.capabilities, context.data_layer), else: {[], []}

    %{
      name: field.name,
      kind: kind,
      label: humanize(field.name),
      description: Map.get(field, :description),
      type: type(resolved),
      allow_nil?: allow_nil?(field),
      primary_key?: Map.get(field, :primary_key?, false),
      sensitive?: kind != :aggregate and Map.get(field, :sensitive?, false),
      public?: field.public?,
      sortable?: Info.sortable?(context.resource, field.name, pagination_type: context.pagination_type),
      filterable?: filterable?,
      operators: Enum.map(operators, & &1.name),
      functions: Enum.map(functions, & &1.name),
      default: default(field),
      edit: edit(field, kind, action),
      belongs_to: belongs_to(context.resource, field.name)
    }
  end

  defp field_kind(%Ash.Resource.Attribute{}), do: :attribute
  defp field_kind(%Ash.Resource.Calculation{}), do: :calculation
  defp field_kind(%Ash.Resource.Aggregate{}), do: :aggregate

  # ResourceBuilder.resolve_aggregate_type/2 does exactly this but is `@doc false`
  defp type_of(resource, %Ash.Resource.Aggregate{} = aggregate) do
    case Ash.Query.Aggregate.aggregate_type(resource, aggregate) do
      {:ok, type, constraints} -> {type, constraints}
      _ -> {aggregate.type, aggregate.constraints || []}
    end
  end

  defp type_of(_resource, field), do: {field.type, field.constraints || []}

  defp allow_nil?(%Ash.Resource.Aggregate{kind: kind}) when kind in [:count, :exists, :list], do: false
  defp allow_nil?(%Ash.Resource.Aggregate{}), do: true
  defp allow_nil?(field), do: field.allow_nil?

  defp type(%{kind: :type_ref, module: module, constraints: constraints}) do
    %{type(TypeResolver.resolve_definition(module)) | module: module, constraints: normalize(constraints)}
  end

  defp type(%{kind: :array} = t) do
    %{kind: :array, module: nil, constraints: normalize(t.constraints), values: nil, item: type(t.item_type)}
  end

  defp type(t), do: %{kind: t.kind, module: t.module, constraints: normalize(t.constraints), values: values(t), item: nil}

  defp values(%{kind: :enum, values: values, module: module}) do
    labelled? = function_exported?(module, :label, 1)
    Enum.map(values, &{&1, (labelled? && module.label(&1)) || humanize(&1)})
  end

  defp values(_), do: nil

  defp default(%Ash.Resource.Attribute{default: default}) do
    case default do
      nil -> nil
      fun when is_function(fun) -> :dynamic
      {m, f, a} when is_atom(m) and is_atom(f) and is_list(a) -> :dynamic
      value -> {:static, value}
    end
  end

  defp default(_), do: nil

  defp edit(_field, kind, _action) when kind != :attribute, do: nil

  defp edit(field, :attribute, action) do
    if field.name in action.accept do
      allow_nil_input = Map.get(action, :allow_nil_input, []) || []
      required = Map.get(action, :require_attributes, []) || []

      %{
        action: action.name,
        allow_nil?: field.name in allow_nil_input or (field.name not in required and field.allow_nil?),
        required?: field.name not in allow_nil_input and field.name in required
      }
    end
  end

  defp belongs_to(resource, name) do
    Enum.find_value(Info.relationships(resource), fn
      %{type: :belongs_to, source_attribute: ^name} = rel ->
        %{relationship: rel.name, destination: rel.destination, destination_attribute: rel.destination_attribute}

      _ ->
        nil
    end)
  end

  defp pagination(%{} = p) do
    %{offset?: p.offset?, keyset?: p.keyset?, required?: p.required?, countable: p.countable, default_limit: p.default_limit, max_page_size: p.max_page_size}
  end

  defp pagination(_), do: nil

  defp normalize(constraints) do
    Enum.map(constraints, fn
      {:match, {Spark.Regex, :cache, [source, _opts]}} -> {:match, source}
      {:match, %Regex{} = regex} -> {:match, Regex.source(regex)}
      {:items, items} -> {:items, normalize(items)}
      other -> other
    end)
  end

  defp humanize(name), do: name |> to_string() |> String.replace("_", " ") |> String.capitalize()
end
