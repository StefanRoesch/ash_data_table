defmodule AshDataTable.Parts.Pagination do
  @moduledoc false
  # The pages of a table and "Rows per page": the part `pagination` of
  # `AshDataTable.Kit.Default`.
  use Phoenix.Component

  alias AshDataTable.Attrs
  alias AshDataTable.Model
  alias AshDataTable.Parts

  # Whether there are pages to go through.
  def pages?(page, model), do: not is_nil(page) and model.pagination.strategy != :none

  # The pages of a table: where the page is among the records, and the
  # controls to go to another. Under a table of its own it is a navigation
  # landmark after the grid, whose controls are ordinary tab stops. In a
  # nested table it is a group in the last row of the grid, its controls Tab
  # stops as well. There the controls follow the range
  # at the left: the right end of a nested table may be out of sight.
  #
  # The hook keeps focus on the control that was used, or sends it on when
  # that control is gone (see `.Pagination` below).
  #
  # A table that offers page sizes has a menu after the buttons,
  # `ID-page-size`, with its label "Rows per page" (in the form
  # `ID-page-size-form`). Choosing sends `page_size`, and the table reads
  # its first page with that size.
  attr :id, :string, required: true
  attr :nested?, :boolean, required: true
  attr :page, :map, required: true
  attr :model, :map, required: true
  attr :state, :map, required: true
  attr :row_count, :integer, required: true
  attr :label, :string, required: true
  attr :target, :any, required: true
  attr :kit, :atom, required: true
  attr :texts, :map, required: true
  attr :pages, :list, required: true

  def pagination(assigns) do
    ~H"""
    <nav
      :if={not @nested?}
      {Attrs.pagination(@id, @texts.label, false)}
      class={@kit.class(:pagination, %{nested?: false})}
    >
      <.pages {assigns} />
    </nav>
    <div
      :if={@nested?}
      {Attrs.pagination(@id, @texts.label, true)}
      class={@kit.class(:pagination, %{nested?: true})}
    >
      <.pages {assigns} />
    </div>
    """
  end

  defp pages(assigns) do
    ~H"""
    <%!-- `me-auto`: under a table of its own the range is at one end and the
    controls together at the other. --%>
    <p id={"#{@id}-range"} class="me-auto text-sm">{@texts.range}</p>
    <div class="join">
      <button
        type="button"
        id={"#{@id}-previous"}
        class="join-item btn btn-sm"
        disabled={is_nil(@page.previous)}
        phx-click={Attrs.event(@id, "page")}
        phx-value-to="previous"
        phx-target={@target}
      >
        {@texts.previous}
      </button>
      <%!-- The page numbers have an element to themselves, which the layout
      does not see: Previous and Next are then always the first and the last
      of three, and a patch that adds or takes away a number leaves them
      where they are, with their focus. The current page is marked by its fill,
      which forced colours take away: there it is underlined. --%>
      <span
        :if={@model.pagination.strategy == :offset}
        class="contents [&>:first-child]:ms-[calc(var(--border)*-1)]"
      >
        <button
          :for={{number, label} <- Enum.zip(@pages, @texts.go_to_page)}
          type="button"
          id={"#{@id}-page-#{number}"}
          class={[
            "join-item btn btn-sm forced-colors:aria-[current=page]:underline",
            number == @state.page && "btn-active"
          ]}
          aria-label={label}
          aria-current={number == @state.page && "page"}
          phx-click={Attrs.event(@id, "page")}
          phx-value-to={number}
          phx-target={@target}
        >
          {number}
        </button>
      </span>
      <button
        type="button"
        id={"#{@id}-next"}
        class="join-item btn btn-sm"
        disabled={is_nil(@page.next)}
        phx-click={Attrs.event(@id, "page")}
        phx-value-to="next"
        phx-target={@target}
      >
        {@texts.next}
      </button>
    </div>
    <%!-- The page sizes a person can choose between, for a table that offers
    some: after the buttons, so that Previous and Next stay where they are. A
    form of its own, of one menu, which applies when it changes. --%>
    <form
      :if={@model.pagination.page_sizes != []}
      id={"#{@id}-page-size-form"}
      phx-change={Attrs.event(@id, "page_size")}
      phx-target={@target}
      class="flex items-center gap-2"
    >
      <label for={"#{@id}-page-size"} class="text-sm">{@texts.rows_per_page}</label>
      <select
        id={"#{@id}-page-size"}
        name="size"
        class={["select select-sm w-auto", Parts.Editors.control_edge()]}
      >
        <option
          :for={size <- @model.pagination.page_sizes}
          value={size}
          selected={size == Model.Pagination.size(@model.pagination, @state.per)}
        >
          {size}
        </option>
      </select>
    </form>
    """
  end
end
