defmodule AshTableProto.State do
  @moduledoc """
  THROWAWAY PROTOTYPE (#11). The table state every variant keeps: columns,
  page, sort and the description of the nested table.
  """
  import Phoenix.Component, only: [assign: 2, assign_new: 3]
  alias AshTableProto.Model

  @inputs [:cfg, :cols, :page_size, :scope]

  @doc "Assigns the inputs; returns `{:reload | :keep, socket}`."
  def assign_inputs(socket, assigns, module) do
    first? = not is_map_key(socket.assigns, :page)
    old = Map.take(socket.assigns, @inputs)
    socket = socket |> assign(assigns) |> assign_new(:scope, fn -> nil end)
    a = socket.assigns

    if first? or old != Map.take(a, @inputs) do
      {:reload,
       assign(socket,
         page: 1,
         sort: if(first?, do: nil, else: a.sort),
         columns: Model.columns(a.cfg, a.cols),
         nested: nested(a.cfg, module)
       )}
    else
      {:keep, socket}
    end
  end

  defp nested(%{nested: %{relationship: name, cfg: cfg}} = parent, module) do
    rel = Ash.Resource.Info.relationship(parent.resource, name)

    %{
      module: module,
      # a nested table lays itself out like its parent
      cfg: Map.put(cfg, :layout, parent[:layout]),
      label: cfg.label,
      source_attribute: rel.source_attribute,
      destination_attribute: rel.destination_attribute
    }
  end

  defp nested(_cfg, _module), do: nil

  def column(columns, name), do: Enum.find(columns, &(to_string(&1.name) == name))

  @doc "asc, desc, none."
  def next_sort(sort, columns, name) do
    col = column(columns, name)

    case sort do
      {n, :asc} when n == col.name -> {col.name, :desc}
      {n, :desc} when n == col.name -> nil
      _ -> {col.name, :asc}
    end
  end

  def next_page(%{page: page, page_size: page_size, total: total}, "next"),
    do: if(page * page_size >= total, do: page, else: page + 1)

  def next_page(%{page: page}, "prev"), do: max(page - 1, 1)

  def label(a), do: a.cfg.label
end
