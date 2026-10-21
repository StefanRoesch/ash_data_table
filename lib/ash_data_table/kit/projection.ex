defmodule AshDataTable.Kit.Projection do
  @moduledoc """
  What a part of a table is given to draw (ADR 0004): one finished,
  plain-data projection per part, made by the table and the same for
  every kit, so that a kit only draws.

  SHAPES
  """

  alias AshDataTable.Kit.Projection

  @parts %{
    status: Projection.Status,
    message: Projection.Message,
    confirm: Projection.Confirm,
    pagination: Projection.Pagination,
    picker: Projection.Picker,
    related: Projection.Related,
    full_view: Projection.FullView,
    selection_line: Projection.SelectionLine,
    heading: Projection.Heading
  }

  @doc false
  # The projection of `part`, made of `inputs`: the entry fields that part
  # depends on. `{part, key}` is one key of it, made of the inputs that key
  # depends on, which the drawing gives one by one: LiveView sends a key
  # again only when what it is made of changed. `:message` gives a list,
  # one per message the table says now.
  def of({part, key}, inputs) do
    module = Map.fetch!(@parts, part)

    if keyed?(module),
      do: module.key(key, inputs),
      else: Map.fetch!(module.of(inputs), key)
  end

  def of(part, inputs) do
    module = Map.fetch!(@parts, part)

    if keyed?(module),
      do: Map.new(module.keys(), &{&1, module.key(&1, inputs)}),
      else: module.of(inputs)
  end

  @doc false
  # The parts given a projection.
  def parts, do: [:status, :message, :confirm, :pagination, :picker, :related]

  @doc false
  # The keys of the projection of `part`.
  def keys(part), do: Map.fetch!(@parts, part).keys()

  # Whether a part's projection is made key by key (`key/2`), else whole
  # (`of/1`, a part drawn seldom, whose keys all change together).
  defp keyed?(module), do: Code.ensure_loaded!(module) && function_exported?(module, :key, 2)
end
