defmodule AshTableProto.Model do
  @moduledoc """
  THROWAWAY PROTOTYPE (#11). Columns from `Ash.Resource.Info`, row items and cell values.

  A table config (`cfg`) is a plain map:

      %{resource: R, label: "Tasks", update_action: :update,
        column_actions: %{price: :reprice},
        nested: %{relationship: :comments, cfg: %{...}} | nil}
  """

  def columns(cfg, limit) do
    attrs = Ash.Resource.Info.public_attributes(cfg.resource)
    attrs = if is_integer(limit), do: Enum.take(attrs, limit), else: attrs

    for {attr, ci} <- Enum.with_index(attrs) do
      {type, extra} = type(attr)
      action = Map.get(cfg[:column_actions] || %{}, attr.name, cfg[:update_action])

      editable =
        type != :readonly and not attr.primary_key? and attr.writable? and
          accepts?(cfg.resource, action, attr.name)

      Map.merge(extra, %{
        ci: ci,
        name: attr.name,
        label: attr.name |> to_string() |> String.replace("_", " ") |> String.capitalize(),
        type: type,
        editable: editable,
        action: if(editable, do: action)
      })
    end
  end

  defp accepts?(_resource, nil, _name), do: false

  defp accepts?(resource, action, name) do
    case Ash.Resource.Info.action(resource, action) do
      %{type: :update, accept: accept} -> name in accept
      _ -> false
    end
  end

  defp type(%{type: type} = attr) do
    Code.ensure_loaded(type)

    cond do
      type in [Ash.Type.String, Ash.Type.CiString] -> {:text, %{}}
      type == Ash.Type.Integer -> {:number, %{step: "1"}}
      type in [Ash.Type.Decimal, Ash.Type.Float] -> {:number, %{step: "any"}}
      type == Ash.Type.Boolean -> {:boolean, %{}}
      type == Ash.Type.Date -> {:date, %{}}
      type in [Ash.Type.UtcDatetime, Ash.Type.DateTime] -> {:datetime, %{}}
      function_exported?(type, :values, 0) -> {:enum, %{options: enum_options(type, attr)}}
      true -> {:readonly, %{}}
    end
  end

  defp enum_options(type, attr) do
    values = Enum.map(type.values(), &to_string/1)
    if attr.allow_nil?, do: ["" | values], else: values
  end

  @doc "Row items for one page. `aria-rowindex` is 1-based and counts the header row."
  def rows(records, %{page: page, page_size: page_size}) do
    offset = (page - 1) * page_size

    for {rec, i} <- Enum.with_index(records) do
      %{id: rec.id, idx: offset + i + 2, rec: rec, open: false, errs: %{}}
    end
  end

  @doc """
  The cells of one row. Each cell is a small map so a keyed comprehension over
  them only re-sends the cells whose map changed.
  """
  def cells(row, columns, gid, offset) do
    for col <- columns do
      text = format(Map.get(row.rec, col.name))
      err = row.errs[col.name]

      attrs =
        [id: "#{gid}-#{row.id}-#{col.ci}", "aria-colindex": col.ci + 1 + offset] ++
          if(col.editable, do: [], else: ["aria-readonly": "true"]) ++
          if(err, do: ["aria-invalid": "true", "data-old": text], else: [])

      case {col.type, err} do
        {:boolean, nil} ->
          %{ci: col.ci, attrs: attrs, kind: :bool, text: text, label: col.label, ro: !col.editable}

        {:boolean, {typed, msg}} ->
          %{ci: col.ci, attrs: attrs, kind: :bool, text: typed, label: col.label, ro: false, msg: msg}

        {_, nil} ->
          %{ci: col.ci, attrs: attrs, kind: :plain, text: text}

        {_, {typed, msg}} ->
          %{ci: col.ci, attrs: attrs, kind: :invalid, text: typed, msg: msg}
      end
    end
  end

  # The shown text is also what the editor starts from, so it must round-trip
  # through the editor of the column's type (the hook turns the space of a
  # datetime into the "T" of datetime-local).
  def format(nil), do: ""
  def format(%Decimal{} = d), do: Decimal.to_string(d, :normal)
  def format(%Date{} = d), do: Date.to_iso8601(d)
  def format(%DateTime{} = d), do: Calendar.strftime(d, "%Y-%m-%d %H:%M")
  def format(v) when is_binary(v), do: v
  def format(v), do: to_string(v)
end
