defmodule Spike.TableModel.FromManifest do
  @moduledoc """
  Proof of concept: the table model built on `Ash.Info.Manifest`.
  Lines marked `# GAP` read `Ash.Resource.Info` because the manifest lacks the fact.
  """
  alias Ash.Info.Manifest
  alias Ash.Resource.Info

  @doc """
  Options: `:otp_app` (required), `:read_action`, `:columns` (names, default: all public
  fields in declaration order), `:edit` (keyword of column => update action, `:default`
  for the rest).
  """
  def build(resource, opts) do
    read = opts[:read_action] || Info.primary_action!(resource, :read).name
    edit = opts[:edit] || [default: Info.primary_action!(resource, :update).name]
    actions = Enum.uniq([read | Keyword.values(edit)])

    {:ok, manifest} =
      Manifest.generate(
        otp_app: Keyword.fetch!(opts, :otp_app),
        action_entrypoints: Enum.map(actions, &{resource, &1}),
        # needed so a private attribute named as a column has a Field at all
        include_private_attributes?: true
      )

    res = Manifest.get_resource!(Manifest.resource_lookup(manifest), resource)
    types = Manifest.type_lookup(manifest)
    action_lookup = Manifest.action_lookup(manifest)
    read_action = Manifest.get_action(action_lookup, resource, read)
    # GAP: keyset pagination narrows what is sortable; the manifest flag ignores it
    pagination_type = if match?(%{offset?: false, keyset?: true}, read_action.pagination), do: :keyset, else: :offset
    names = opts[:columns] || default_columns(resource)

    %{
      resource: resource,
      # GAP: no domain on the manifest resource
      domain: Info.domain(resource),
      primary_key: res.primary_key,
      read_action: read,
      pagination: pagination(read_action.pagination, resource, read),
      columns:
        Enum.map(names, fn name ->
          field = Map.fetch!(res.fields, name)
          action = Keyword.get(edit, name, edit[:default])
          column(resource, field, types, action, Manifest.get_action(action_lookup, resource, action), pagination_type)
        end)
    }
  end

  # GAP: `fields` is a map; declaration order comes from Resource.Info
  defp default_columns(resource) do
    Enum.map(Info.public_attributes(resource) ++ Info.public_calculations(resource) ++ Info.public_aggregates(resource), & &1.name)
  end

  defp column(resource, field, types, action_name, action, pagination_type) do
    %{
      name: field.name,
      kind: field.kind,
      label: humanize(field.name),
      description: field.description,
      type: type(field.type, types),
      allow_nil?: field.allow_nil?,
      primary_key?: field.primary_key?,
      sensitive?: field.sensitive?,
      # GAP: no public? flag once private attributes are included
      public?: Info.public_field(resource, field.name) != nil,
      # GAP: manifest `sortable?` is the bare DSL flag (true for module calculations and arrays)
      sortable?: Info.sortable?(resource, field.name, pagination_type: pagination_type),
      filterable?: field.filterable?,
      operators: Enum.map(field.filter_operators || [], & &1.name),
      functions: Enum.map(field.filter_functions || [], & &1.name),
      default: default(resource, field),
      edit: edit(resource, field, action_name, action),
      belongs_to: belongs_to(resource, field.name)
    }
  end

  defp type(%{kind: :type_ref, module: module, constraints: constraints}, types) do
    definition = Manifest.get_type!(types, module)
    %{type(definition, types) | module: module, constraints: normalize(constraints)}
  end

  defp type(%{kind: :array} = t, types) do
    %{kind: :array, module: nil, constraints: normalize(t.constraints), values: nil, item: type(t.item_type, types)}
  end

  defp type(t, _types) do
    %{kind: t.kind, module: t.module, constraints: normalize(t.constraints), values: values(t), item: nil}
  end

  # GAP: enum labels are not in the manifest
  defp values(%{kind: :enum, values: values, module: module}) do
    labelled? = function_exported?(module, :label, 1)
    Enum.map(values, &{&1, (labelled? && module.label(&1)) || humanize(&1)})
  end

  defp values(_), do: nil

  # GAP: only `has_default?` is carried
  defp default(_resource, %{has_default?: false}), do: nil

  defp default(resource, field) do
    case Info.attribute(resource, field.name).default do
      fun when is_function(fun) -> :dynamic
      {m, f, a} when is_atom(m) and is_atom(f) and is_list(a) -> :dynamic
      value -> {:static, value}
    end
  end

  defp edit(_resource, %{kind: kind}, _action_name, _action) when kind != :attribute, do: nil

  defp edit(resource, field, action_name, action) do
    input = Enum.find(action.inputs, &(&1.name == field.name))
    # GAP: an argument named like the attribute is indistinguishable in `inputs`
    accepted? = field.name in Info.action(resource, action_name).accept
    if input && accepted?, do: %{action: action_name, allow_nil?: input.allow_nil?, required?: input.required?}
  end

  # GAP: relationship keys are not in the manifest
  defp belongs_to(resource, name) do
    Enum.find_value(Info.relationships(resource), fn
      %{type: :belongs_to, source_attribute: ^name} = rel ->
        %{relationship: rel.name, destination: rel.destination, destination_attribute: rel.destination_attribute}

      _ ->
        nil
    end)
  end

  defp pagination(nil, _resource, _read), do: nil

  defp pagination(p, resource, read) do
    %{
      offset?: p.offset?,
      keyset?: p.keyset?,
      required?: p.required?,
      # GAP: `countable?` folds `true` and `:by_default` together
      countable: Info.action(resource, read).pagination.countable,
      default_limit: p.default_limit,
      max_page_size: p.max_page_size
    }
  end

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
