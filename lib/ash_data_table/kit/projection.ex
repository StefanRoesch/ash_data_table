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
    heading: Projection.Heading,
    panel: Projection.Panel,
    grid: Projection.Grid,
    root: Projection.Root
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

  # The parts drawn inside another, whose projections are in that one's
  # (question 25 of the design note): the keys of each.
  @inner %{
    columns: [
      :control,
      :button,
      :text,
      :count,
      :list,
      :status,
      :label,
      :entries,
      :reset,
      :least,
      :most,
      :texts,
      :messages
    ],
    argument_line: [:form, :nested?, :arguments],
    argument: [
      :id,
      :named,
      :name,
      :label,
      :editor,
      :item,
      :required?,
      :values,
      :value,
      :invalid?,
      :limits,
      :counted,
      :element,
      :described,
      :error,
      :count,
      :group,
      :rows,
      :add,
      :texts,
      :messages
    ],
    count: [:element, :length, :max, :over?],
    field: [
      :id,
      :name,
      :element,
      :editor,
      :label,
      :required?,
      :secret?,
      :item,
      :values,
      :value,
      :boxless,
      :invalid?,
      :places,
      :limits,
      :counted,
      :described,
      :labelled?,
      :group_label,
      :labelledby,
      :error,
      :reference,
      :references,
      :list,
      :file,
      :component,
      :control,
      :clear,
      :count,
      :group,
      :groups,
      :union,
      :texts,
      :messages,
      :locale
    ],
    control: [
      :id,
      :name,
      :value,
      :editor,
      :secret?,
      :invalid?,
      :required?,
      :described,
      :limits,
      :values
    ],
    list: [:element, :item, :limits, :name, :template, :rows, :texts, :messages],
    header_cell: [:element, :label, :button, :mark, :resizer, :texts, :messages],
    resizer: [:element],
    filter_cell: [:element, :filter],
    filter: [
      :cell_type,
      :takes,
      :yes_no,
      :operators,
      :choice,
      :input,
      :range,
      :several,
      :clear,
      :error,
      :texts,
      :messages
    ],
    row: [
      :selecting,
      :radio,
      :expandable?,
      :lead,
      :columns,
      :actions,
      :relationships,
      :colspan,
      :texts,
      :messages
    ],
    cell: [
      :name,
      :label,
      :colindex,
      :header?,
      :cell_type,
      :editor,
      :max_lines,
      :sensitive?,
      :values,
      :attrs,
      :component,
      :typed,
      :texts,
      :messages,
      :locale
    ],
    actions_cell: [:colindex, :open, :buttons],
    detail: [:relationships, :colspan],
    line: [:relationship, :line, :colspan, :table],
    footer: [:element, :summaries, :pager, :full_view],
    summary_cell: [:element, :summary?, :state, :value, :text, :texts, :messages, :locale],
    editor: [
      :id,
      :label,
      :editor,
      :required?,
      :sensitive?,
      :values,
      :limits,
      :counted,
      :count,
      :control,
      :clearable?,
      :texts,
      :messages
    ],
    failure: [:text, :message]
  }

  @doc false
  # The parts given a projection.
  def parts, do: Map.keys(@parts) ++ Map.keys(@inner)

  @doc false
  # The keys of the projection of `part`.
  def keys(part) when is_map_key(@inner, part), do: Map.fetch!(@inner, part)
  def keys(part), do: Map.fetch!(@parts, part).keys()

  # Whether a part's projection is made key by key (`key/2`), else whole
  # (`of/1`, a part drawn seldom, whose keys all change together).
  defp keyed?(module), do: Code.ensure_loaded!(module) && function_exported?(module, :key, 2)
end
