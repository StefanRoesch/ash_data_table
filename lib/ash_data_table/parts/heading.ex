defmodule AshDataTable.Parts.Heading do
  @moduledoc false
  # The line of the table's name: the name, create and the table actions.
  # Moved out of `AshDataTable.Live.TableComponent` in stage 1 of the
  # refactor (docs/architecture/target.md); it still draws from the
  # component's assigns.
  use Phoenix.Component

  # The create button of a table: it opens the action panel with the inputs
  # of the table's create action.
  attr :id, :string, required: true
  attr :action, :map, required: true
  attr :target, :any, required: true

  def create(assigns) do
    ~H"""
    <button
      type="button"
      id={"#{@id}-create"}
      class="btn btn-sm"
      phx-click="create"
      phx-target={@target}
    >
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
      id={"#{@id}-do-#{action.name}"}
      class="btn btn-sm"
      data-table-action={action.name}
      phx-click="table_act"
      phx-value-action={action.name}
      phx-target={@target}
    >
      {action.label}
    </button>
    """
  end

  # Part of the component's `render/1` until stage 1 of the refactor. Its
  # markup keeps the indentation it had there, held by `phx-no-format`, so
  # that the text in it, and with it the page, is the same byte for byte.
  attr :heading, :any, required: true
  attr :id, :any, required: true
  attr :label, :any, required: true
  attr :model, :any, required: true
  attr :myself, :any, required: true
  attr :nested?, :any, required: true
  attr :offered, :any, required: true
  attr :page, :any, required: true
  attr :related, :any, required: true

  def heading(assigns) do
    ~H"""
    <%!-- The line of the table's name: the name at one end, and what the
    table lets a person create at the other. A nested table has its name on
    the line that opens it, and a table limited to related records says what
    it shows on the line below. --%>
    <div
      :if={
        not @nested? and
          (@heading || (@page && (@model.create || @offered != []) && is_nil(@related)))
      }
      phx-no-format
      id={"#{@id}-header"}
      class="mb-4 flex min-h-8 items-center justify-between gap-2"
    >
        <.dynamic_tag
          :if={@heading}
          tag_name={if is_integer(@heading), do: "h#{@heading}", else: "div"}
          id={"#{@id}-name"}
          class="text-lg font-semibold"
        >
          {@label}
        </.dynamic_tag>
        <%!-- not beside an error: a table that could not read offers nothing --%>
        <div
          :if={@page && (@model.create || @offered != []) && is_nil(@related)}
          class="ms-auto flex flex-wrap items-center justify-end gap-2"
        >
          <.create :if={@model.create} id={@id} action={@model.create} target={@myself} />
          <.table_actions id={@id} actions={@offered} target={@myself} />
        </div>
      </div>
    """
  end
end
