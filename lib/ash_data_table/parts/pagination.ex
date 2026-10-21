defmodule AshDataTable.Parts.Pagination do
  @moduledoc false
  # The pages of a table and "Rows per page": the part `pagination` of
  # `AshDataTable.Kit.Default`.
  use Phoenix.Component

  alias AshDataTable.Parts

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
  #
  # Its projection (`AshDataTable.Kit.Projection`, `pagination`).
  attr :id, :string, required: true
  attr :nested?, :boolean, required: true
  attr :element, :map, required: true
  attr :range, :map, required: true
  attr :previous, :map, required: true
  attr :next, :map, required: true
  attr :pages, :list, required: true
  attr :sizes, :map, required: true
  attr :texts, :map, required: true
  attr :messages, :map, required: true
  attr :kit, :atom, required: true

  def pagination(assigns) do
    ~H"""
    <nav :if={not @nested?} {@element} class={@kit.class(:pagination, %{nested?: false})}>
      <.pages {assigns} />
    </nav>
    <div :if={@nested?} {@element} class={@kit.class(:pagination, %{nested?: true})}>
      <.pages {assigns} />
    </div>
    """
  end

  defp pages(assigns) do
    ~H"""
    <%!-- `me-auto`: under a table of its own the range is at one end and the
    controls together at the other. --%>
    <p {@range} class="me-auto text-sm">{@texts.range}</p>
    <div class="join">
      <button type="button" {@previous} class="join-item btn btn-sm">
        {@texts.previous}
      </button>
      <%!-- The page numbers have an element to themselves, which the layout
      does not see: Previous and Next are then always the first and the last
      of three, and a patch that adds or takes away a number leaves them
      where they are, with their focus. The current page is marked by its fill,
      which forced colours take away: there it is underlined. --%>
      <span :if={@pages != []} class="contents [&>:first-child]:ms-[calc(var(--border)*-1)]">
        <button
          :for={page <- @pages}
          type="button"
          {page.button}
          class={[
            "join-item btn btn-sm forced-colors:aria-[current=page]:underline",
            page.current? && "btn-active"
          ]}
        >
          {page.number}
        </button>
      </span>
      <button type="button" {@next} class="join-item btn btn-sm">
        {@texts.next}
      </button>
    </div>
    <%!-- The page sizes a person can choose between, for a table that offers
    some: after the buttons, so that Previous and Next stay where they are. A
    form of its own, of one menu, which applies when it changes. --%>
    <form :if={@sizes} {@sizes.form} class="flex items-center gap-2">
      <label {@sizes.label} class="text-sm">{@texts.rows_per_page}</label>
      <select {@sizes.select} class={["select select-sm w-auto", Parts.Editors.control_edge()]}>
        <option :for={option <- @sizes.options} value={option.size} selected={option.chosen?}>
          {option.size}
        </option>
      </select>
    </form>
    """
  end
end
