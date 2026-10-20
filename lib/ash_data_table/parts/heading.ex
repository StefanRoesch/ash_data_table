defmodule AshDataTable.Parts.Heading do
  @moduledoc false
  # The heading line of a table: its name, "Columns" (the kit's `columns/1`),
  # the argument line (the kit's `argument_line/1`), and at the far end
  # create and the table actions. The part `heading` of
  # `AshDataTable.Kit.Default`.
  use Phoenix.Component

  alias AshDataTable.Attrs
  alias AshDataTable.Kit
  alias AshDataTable.Kit.Words

  # The create button of a table: it opens the action panel with the inputs
  # of the table's create action.
  attr :id, :string, required: true
  attr :action, :map, required: true
  attr :target, :any, required: true

  def create(assigns) do
    ~H"""
    <button type="button" {Attrs.create(@id, @target)} class="btn btn-sm">
      {@action.label}
    </button>
    """
  end

  # The buttons of a table's table actions, beside its create button and
  # looking as it does. Each sends its action to the table; what happens
  # then is the table's to say.
  attr :id, :string, required: true
  attr :actions, :list, required: true
  attr :target, :any, required: true

  def table_actions(assigns) do
    ~H"""
    <button
      :for={action <- @actions}
      type="button"
      {Attrs.table_action(@id, action, @target)}
      class="btn btn-sm"
    >
      {action.label}
    </button>
    """
  end

  # one per argument of the model, what its input is drawn with
  attr :arguments, :list, required: true
  attr :heading, :any, required: true
  attr :id, :any, required: true
  attr :kit, :atom, required: true
  attr :label, :any, required: true
  attr :model, :any, required: true
  attr :myself, :any, required: true
  attr :nested?, :any, required: true
  attr :offered, :any, required: true
  attr :page, :any, required: true
  attr :related, :any, required: true
  attr :state, :any, required: true

  def heading(assigns) do
    ~H"""
    <%!-- One line, the same for a table on the page and a nested one: the
    name, "Columns", the inputs of the read action, and at the far end what
    the table lets a person create and run. It wraps only where it does not
    fit. A nested table's name is its line's (`Parts.Related.line`), which
    this line is moved onto (`AshDataTable.Live.Drawing`); its controls are
    Tab stops there, after the line's button. --%>
    <div
      :if={
        @nested? or !!@heading or columns?(@model) or @model.arguments != [] or
          acts?(@page, @model, @offered, @related)
      }
      id={"#{@id}-header"}
      class={@kit.class(:heading, %{nested?: @nested?})}
    >
      <.dynamic_tag
        :if={@heading && not @nested?}
        tag_name={if is_integer(@heading), do: "h#{@heading}", else: "div"}
        id={"#{@id}-name"}
        class="text-lg font-semibold"
      >
        {@label}
      </.dynamic_tag>
      <Kit.part
        :if={columns?(@model)}
        part={:columns}
        kit={@kit}
        id={@id}
        columns={hideable(@model)}
        label_column={@model.label_column}
        keeps_one?={is_nil(@model.label_column)}
        state={@state}
        nested?={@nested?}
        class={nil}
        texts={
          Words.texts(:columns, %{
            columns: hideable(@model),
            label_column: @model.label_column,
            state: @state,
            label: @label,
            nested?: @nested?
          })
        }
        messages={
          Words.messages(:columns, %{
            columns: hideable(@model),
            label_column: @model.label_column,
            state: @state,
            label: @label,
            nested?: @nested?
          })
        }
      />
      <Kit.part
        part={:argument_line}
        kit={@kit}
        id={@id}
        arguments={@arguments}
        model={@model}
        myself={@myself}
        nested?={@nested?}
      />
      <div
        :if={acts?(@page, @model, @offered, @related)}
        class="ms-auto flex flex-wrap items-center justify-end gap-2"
      >
        <.create
          :if={@model.create}
          id={@id}
          action={@model.create}
          target={@myself}
        />
        <.table_actions id={@id} actions={@offered} target={@myself} />
      </div>
    </div>
    """
  end

  # Whether the table has columns a person can hide: more than one, and one
  # that is no label. Worked out where it is used, from `model`, so that
  # LiveView sends what depends on it again only when the model changed.
  defp columns?(model), do: length(model.columns) > 1 and hideable(model) != []

  # The columns a person can hide: every column but the label column.
  defp hideable(%{label_column: nil} = model), do: model.columns

  defp hideable(%{label_column: %{name: name}} = model),
    do: Enum.reject(model.columns, &(&1.name == name))

  # Whether the line offers create or table actions: not beside an error (a
  # table that could not read offers nothing), and not for a table limited
  # to related records, which offers them above its grid.
  defp acts?(page, model, offered, related),
    do: !!page and (!!model.create or offered != []) and is_nil(related)
end
