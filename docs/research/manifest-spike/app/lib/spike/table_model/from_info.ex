defmodule Spike.TableModel.FromInfo do
  @moduledoc """
  Proof of concept: the same table model built on `Ash.Resource.Info` alone.
  Lines marked `# REBUILD` re-derive something the manifest computes.
  """
  alias Ash.Resource.Info

  @ordered [:<, :>, :<=, :>=]

  # REBUILD: the manifest's type-module => kind table (24 entries there; the ones a cell needs here)
  @kinds %{
    Ash.Type.String => :string,
    Ash.Type.CiString => :ci_string,
    Ash.Type.Integer => :integer,
    Ash.Type.Float => :float,
    Ash.Type.Decimal => :decimal,
    Ash.Type.Boolean => :boolean,
    Ash.Type.UUID => :uuid,
    Ash.Type.UUIDv7 => :uuid,
    Ash.Type.Date => :date,
    Ash.Type.Time => :time,
    Ash.Type.TimeUsec => :time_usec,
    Ash.Type.DateTime => :datetime,
    Ash.Type.UtcDatetime => :utc_datetime,
    Ash.Type.UtcDatetimeUsec => :utc_datetime_usec,
    Ash.Type.NaiveDatetime => :naive_datetime,
    Ash.Type.Duration => :duration,
    Ash.Type.Binary => :binary,
    Ash.Type.Map => :map,
    Ash.Type.Union => :union,
    Ash.Type.Term => :term
  }

  @doc "Same options as `FromManifest.build/2`; `:otp_app` is not needed."
  def build(resource, opts \\ []) do
    read = opts[:read_action] || Info.primary_action!(resource, :read).name
    edit = opts[:edit] || [default: Info.primary_action!(resource, :update).name]
    read_action = Info.action(resource, read)
    pagination_type = if match?(%{offset?: false, keyset?: true}, read_action.pagination), do: :keyset, else: :offset
    names = opts[:columns] || default_columns(resource)

    %{
      resource: resource,
      domain: Info.domain(resource),
      primary_key: Info.primary_key(resource),
      read_action: read,
      pagination: pagination(read_action.pagination),
      columns:
        Enum.map(names, fn name ->
          action = Keyword.get(edit, name, edit[:default])
          column(resource, Info.field(resource, name), Info.action(resource, action), pagination_type)
        end)
    }
  end

  defp default_columns(resource) do
    Enum.map(Info.public_attributes(resource) ++ Info.public_calculations(resource) ++ Info.public_aggregates(resource), & &1.name)
  end

  defp column(resource, field, action, pagination_type) do
    kind = field_kind(field)
    {type_module, constraints} = type_of(resource, field)
    type = type(type_module, constraints)
    filterable? = Map.get(field, :filterable?, true)
    {operators, functions} = if filterable?, do: predicates(resource, type), else: {[], []}

    %{
      name: field.name,
      kind: kind,
      label: humanize(field.name),
      description: Map.get(field, :description),
      type: type,
      allow_nil?: allow_nil?(field),
      primary_key?: Map.get(field, :primary_key?, false),
      # REBUILD: the manifest hard-codes false for aggregates
      sensitive?: kind != :aggregate and Map.get(field, :sensitive?, false),
      public?: field.public?,
      sortable?: Info.sortable?(resource, field.name, pagination_type: pagination_type),
      filterable?: filterable?,
      operators: operators,
      functions: functions,
      default: default(field),
      edit: edit(field, kind, action),
      belongs_to: belongs_to(resource, field.name)
    }
  end

  defp field_kind(%Ash.Resource.Attribute{}), do: :attribute
  defp field_kind(%Ash.Resource.Calculation{}), do: :calculation
  defp field_kind(%Ash.Resource.Aggregate{}), do: :aggregate

  # REBUILD: aggregates carry no type of their own; it follows from kind and target field
  defp type_of(resource, %Ash.Resource.Aggregate{} = aggregate) do
    case Ash.Query.Aggregate.aggregate_type(resource, aggregate) do
      {:ok, type, constraints} -> {type, constraints}
      _ -> {aggregate.type, aggregate.constraints || []}
    end
  end

  defp type_of(_resource, field), do: {field.type, field.constraints || []}

  # REBUILD: aggregate nullability (the manifest uses Ash.Info.Manifest.Generator.ResultNullability)
  defp allow_nil?(%Ash.Resource.Aggregate{kind: kind}) when kind in [:count, :exists], do: false
  defp allow_nil?(%Ash.Resource.Aggregate{kind: :list}), do: false
  defp allow_nil?(%Ash.Resource.Aggregate{}), do: true
  defp allow_nil?(field), do: field.allow_nil?

  # REBUILD: type classification (NewType unwrapping, enums, embedded resources, arrays)
  defp type({:array, inner}, constraints) do
    %{kind: :array, module: nil, constraints: normalize(constraints), values: nil, item: type(inner, Keyword.get(constraints, :items, []))}
  end

  defp type(module, constraints) do
    module = Ash.Type.get_type(module)
    base = if Ash.Type.NewType.new_type?(module), do: Ash.Type.get_type(Ash.Type.NewType.subtype_of(module)), else: module
    enum? = Spark.implements_behaviour?(module, Ash.Type.Enum)

    {kind, values} =
      cond do
        enum? -> {:enum, labelled(module, module.values())}
        base in [Ash.Type.Atom, Ash.Type.Module] and is_list(constraints[:one_of]) -> {:enum, labelled(module, constraints[:one_of])}
        base in [Ash.Type.Atom, Ash.Type.Module] -> {:atom, nil}
        Ash.Type.embedded_type?(module) -> {:embedded_resource, nil}
        # the declared module first: Ash.Type.UtcDatetime is itself a NewType of Ash.Type.DateTime
        true -> {Map.get(@kinds, module) || Map.get(@kinds, base, :unknown), nil}
      end

    %{kind: kind, module: module, constraints: normalize(constraints), values: values, item: nil}
  end

  defp labelled(module, values) do
    labelled? = function_exported?(module, :label, 1)
    Enum.map(values, &{&1, (labelled? && module.label(&1)) || humanize(&1)})
  end

  # REBUILD: which predicate operators and functions apply to a field type
  # (Ash.Info.Manifest.Generator.OperatorResolver + CapabilitiesBuilder, 453 lines there)
  defp predicates(resource, type) do
    candidates = candidates(type)
    blacklist = if type.kind in [:array, :boolean], do: @ordered, else: []
    overloads = overloads(type.module)

    operators =
      for op <- Ash.Filter.builtin_predicate_operators(),
          name = if(function_exported?(op, :operator, 0), do: op.operator(), else: op.name()),
          name not in blacklist,
          applies?(op.types(), candidates) or name in overloads,
          uniq: true,
          do: name

    data_layer = Ash.DataLayer.data_layer(resource)
    extra = if data_layer && function_exported?(data_layer, :functions, 1), do: data_layer.functions(resource), else: []

    functions =
      for fun <- Ash.Filter.builtin_functions() ++ extra,
          Code.ensure_loaded?(fun),
          fun.predicate?(),
          fun.args() != :var_args,
          applies?(fun.args(), candidates),
          uniq: true,
          do: fun.name()

    {operators, functions}
  end

  defp candidates(%{kind: :array} = type), do: [type]

  defp candidates(%{module: module} = type) do
    if Ash.Type.NewType.new_type?(module) do
      [type, %{kind: nil, module: Ash.Type.get_type(Ash.Type.NewType.subtype_of(module)), item: nil}]
    else
      [type]
    end
  end

  defp overloads(nil), do: []

  defp overloads(module) do
    if function_exported?(module, :operator_overloads, 0), do: Map.keys(module.operator_overloads()), else: []
  end

  defp applies?(signatures, candidates) when is_list(signatures) do
    Enum.any?(signatures, fn
      [first | _] -> Enum.any?(candidates, &arg_matches?(first, &1))
      sentinel when sentinel in [:same, :any] -> true
      _ -> false
    end)
  end

  defp applies?(_, _), do: false

  defp arg_matches?(arg, _type) when arg in [:same, :any], do: true
  defp arg_matches?({:array, inner}, %{kind: :array, item: item}), do: arg_matches?(inner, item)
  defp arg_matches?({:array, _}, _type), do: false
  defp arg_matches?({module, constraints}, type) when is_atom(module) and is_list(constraints), do: arg_matches?(module, type)
  defp arg_matches?(arg, %{module: module}) when is_atom(arg) and not is_nil(module), do: Ash.Type.get_type(arg) == module
  defp arg_matches?(_, _), do: false

  defp default(%Ash.Resource.Attribute{default: default}) do
    case default do
      nil -> nil
      fun when is_function(fun) -> :dynamic
      {m, f, a} when is_atom(m) and is_atom(f) and is_list(a) -> :dynamic
      value -> {:static, value}
    end
  end

  defp default(_), do: nil

  # REBUILD: per-action allow_nil?/required? of an accepted attribute (ActionBuilder)
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

  # REBUILD: pagination defaults live on the action struct; `false` means none
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
