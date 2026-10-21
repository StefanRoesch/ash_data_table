defmodule AshDataTable.Parts.Heading do
  @moduledoc false
  # The heading line of a table: its name, "Columns" (the kit's `columns/1`),
  # the argument line (the kit's `argument_line/1`), and at the far end
  # create and the table actions. The part `heading` of
  # `AshDataTable.Kit.Default`.
  use Phoenix.Component

  alias AshDataTable.Kit

  # Create and the buttons of the table actions, of their projections
  # (`AshDataTable.Kit.Projection`: `create`, nil for none, and `actions`,
  # each a label and the button's bundle). Each sends its action to the
  # table; what happens then is the table's to say.
  attr :create, :map, required: true
  attr :actions, :list, required: true

  def acts(assigns) do
    ~H"""
    <button :if={@create} type="button" {@create.button} class="btn btn-sm">
      {@create.label}
    </button>
    <button :for={action <- @actions} type="button" {action.button} class="btn btn-sm">
      {action.label}
    </button>
    """
  end

  # Its projection (`AshDataTable.Kit.Projection`, `heading`).
  attr :id, :string, required: true
  attr :shown?, :boolean, required: true
  attr :nested?, :boolean, required: true
  attr :element, :map, required: true
  attr :title, :map, required: true
  attr :columns, :map, required: true
  attr :argument_line, :map, required: true
  attr :acts?, :boolean, required: true
  attr :create, :map, required: true
  attr :actions, :list, required: true
  attr :kit, :atom, required: true

  def heading(assigns) do
    ~H"""
    <%!-- One line, the same for a table on the page and a nested one: the
    name, "Columns", the inputs of the read action, and at the far end what
    the table lets a person create and run. It wraps only where it does not
    fit. A nested table's name is its line's (`Parts.Related.line`), which
    this line is moved onto (`AshDataTable.Live.Drawing`); its controls are
    Tab stops there, after the line's button. --%>
    <div :if={@shown?} {@element} class={@kit.class(:heading, %{nested?: @nested?})}>
      <.dynamic_tag
        :if={@title}
        tag_name={if @title.level, do: "h#{@title.level}", else: "div"}
        {@title.element}
        class="text-lg font-semibold"
      >
        {@title.text}
      </.dynamic_tag>
      <Kit.part :if={@columns} part={:columns} kit={@kit} id={@id} class={nil} {@columns} />
      <Kit.part :if={@argument_line} part={:argument_line} kit={@kit} id={@id} {@argument_line} />
      <div :if={@acts?} class="ms-auto flex flex-wrap items-center justify-end gap-2">
        <.acts create={@create} actions={@actions} />
      </div>
    </div>
    """
  end
end
