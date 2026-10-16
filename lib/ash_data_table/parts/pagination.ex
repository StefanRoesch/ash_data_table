defmodule AshDataTable.Parts.Pagination do
  @moduledoc false
  # The pages of a table and "Rows per page".
  # Moved out of `AshDataTable.Live.TableComponent` in stage 1 of the
  # refactor (docs/architecture/target.md); it still draws from the
  # component's assigns.
  use Phoenix.Component

  alias AshDataTable.Attrs
  alias AshDataTable.Model
  alias AshDataTable.Parts
  alias AshDataTable.Text

  # Whether there are pages to go through.
  def pages?(page, model), do: not is_nil(page) and model.pagination.strategy != :none

  # The pages of a table: where the page is among the records, and the
  # controls to go to another. Under a table of its own it is a navigation
  # landmark after the grid, whose controls are ordinary tab stops. In a
  # nested table it is a group in the last row of the grid, and its controls
  # are reached through that row's cell. There the controls follow the range
  # at the left: the right end of a nested table may be out of sight.
  #
  # The hook keeps focus on the control that was used, or sends it on when
  # that control is gone (see `.Pagination` below).
  #
  # A table that offers page sizes has a menu after the buttons,
  # `ID-page-size`, with its label "Rows per page" (in the form
  # `ID-page-size-form`). Choosing sends `page_size`, and the table reads
  # its first page with that size. In a nested table the menu is reached as
  # the buttons are: Enter on the row's cell, then Left and Right Arrow.
  attr :id, :string, required: true
  attr :nested?, :boolean, required: true
  attr :page, :map, required: true
  attr :model, :map, required: true
  attr :state, :map, required: true
  attr :row_count, :integer, required: true
  attr :label, :string, required: true
  attr :target, :any, required: true

  def pagination(assigns) do
    ~H"""
    <nav
      :if={not @nested?}
      {Attrs.pagination(@id, @label, false)}
      class="mt-4 flex flex-wrap items-center justify-between gap-4"
    >
      <.pages {assigns} />
    </nav>
    <div
      :if={@nested?}
      {Attrs.pagination(@id, @label, true)}
      class="sticky left-4 flex w-fit flex-wrap items-center justify-start gap-4"
    >
      <.pages {assigns} />
    </div>
    """
  end

  defp pages(assigns) do
    ~H"""
    <%!-- `me-auto`: under a table of its own the range is at one end and the
    controls together at the other. --%>
    <p id={"#{@id}-range"} class="me-auto text-sm">{range_text(@page, @row_count, @state)}</p>
    <div class="join">
      <button
        type="button"
        id={"#{@id}-previous"}
        class="join-item btn btn-sm"
        tabindex={@nested? && "-1"}
        disabled={is_nil(@page.previous)}
        phx-click={Parts.Common.event(@id, "page")}
        phx-value-to="previous"
        phx-target={@target}
      >
        {Text.t(:previous)}
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
          :for={number <- page_numbers(@page, @state)}
          type="button"
          id={"#{@id}-page-#{number}"}
          class={[
            "join-item btn btn-sm forced-colors:aria-[current=page]:underline",
            number == @state.page && "btn-active"
          ]}
          tabindex={@nested? && "-1"}
          aria-label={Text.t(:go_to_page, page: number)}
          aria-current={number == @state.page && "page"}
          phx-click={Parts.Common.event(@id, "page")}
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
        tabindex={@nested? && "-1"}
        disabled={is_nil(@page.next)}
        phx-click={Parts.Common.event(@id, "page")}
        phx-value-to="next"
        phx-target={@target}
      >
        {Text.t(:next)}
      </button>
    </div>
    <%!-- The page sizes a person can choose between, for a table that offers
    some: after the buttons, so that Previous and Next stay where they are. A
    form of its own, of one menu, which applies when it changes. --%>
    <form
      :if={@model.pagination.page_sizes != []}
      id={"#{@id}-page-size-form"}
      phx-change={Parts.Common.event(@id, "page_size")}
      phx-target={@target}
      class="flex items-center gap-2"
    >
      <label for={"#{@id}-page-size"} class="text-sm">{Text.t(:rows_per_page)}</label>
      <select
        id={"#{@id}-page-size"}
        name="size"
        tabindex={@nested? && "-1"}
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

  defp range_text(%{offset: offset, total: total}, row_count, _state)
       when is_integer(offset) and row_count > 0 do
    bindings = [from: offset + 1, to: offset + row_count, total: total]
    if total, do: Text.t(:range_of_total, bindings), else: Text.t(:range, bindings)
  end

  defp range_text(%{offset: offset}, _row_count, state) when is_integer(offset),
    do: Text.t(:page, page: state.page)

  # Keyset pagination: the page does not know its place among the others, so
  # the total is all there is to say, when the action counts.
  defp range_text(%{total: total}, _row_count, _state) when is_integer(total),
    do: Text.n(:records, total)

  defp range_text(_page, _row_count, _state), do: nil

  # The page numbers offered: the first, the last and those around the
  # current one, of the pages there are; and the current one, also when the
  # URL asked for a page beyond the last. Without a total only the current
  # page is known.
  defp page_numbers(%{pages: pages}, %{page: current}) when is_integer(pages) do
    [1, pages | Enum.to_list((current - 2)..(current + 2)//1)]
    |> Enum.filter(&((&1 >= 1 and &1 <= pages) or &1 == current))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp page_numbers(_page, %{page: current}), do: [current]
end
